import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../data/account/account_models.dart';
import '../data/account/dashboard_models.dart';
import 'device_identity.dart';
import 'google_auth.dart';
import 'key_value_store.dart';

const String _kParentKey = 'auth.parent';
const String _kChildKey = 'auth.child';
const String _kActiveChildKey = 'auth.activeChild';

/// Đăng nhập và các thao tác tài khoản/hồ sơ bé với backend.
///
/// Một máy có thể giữ đồng thời:
///  * phiên của **phụ huynh/admin** (đăng nhập email + OTP hoặc Google), và/hoặc
///  * phiên của **bé** (chọn hồ sơ bé trên máy phụ huynh, hoặc nhập mã liên kết trên máy của bé).
/// Không có phiên nào = chế độ khách: app chạy như trước, hoàn toàn offline.
class AuthService extends ChangeNotifier {
  AuthService({
    ApiClient? api,
    KeyValueStore? store,
    GoogleAuth? google,
    DeviceIdentity? device,
    DateTime Function()? clock,
  }) : _store = store ?? SecureKeyValueStore(),
       _google = google ?? GoogleAuthService(),
       _clock = clock ?? DateTime.now {
    this.api = api ?? ApiClient();
    this.api.tokenFor = _tokenFor;
    this.api.onUnauthorized = _onUnauthorized;
    _device = device ?? StoredDeviceIdentity(_store);
  }

  static AuthService instance = AuthService();

  late final ApiClient api;
  final KeyValueStore _store;
  final GoogleAuth _google;
  final DateTime Function() _clock;
  late final DeviceIdentity _device;

  AuthSession? _parent;
  AuthSession? _child;
  ChildProfile? _activeChild;

  /// Thông báo cho người dùng khi phiên bị kết thúc ngoài ý muốn (hết hạn, thiết bị bị thu hồi). UI hiển thị rồi xoá.
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  AuthSession? get parent => _parent;
  AuthSession? get child => _child;

  /// Hồ sơ bé đang dùng máy này (null nếu không ở chế độ bé).
  ChildProfile? get activeChild => _child == null ? null : _activeChild;

  bool get isGuest => _parent == null && _child == null;
  bool get isParentSignedIn => _parent != null;
  bool get isAdmin => _parent?.role == UserRole.admin;
  bool get inChildMode => _child != null;

  /// Màn hình đầu tiên sau khi phụ huynh/admin đăng nhập.
  String get landingRoute => isAdmin ? '/admin' : '/children';

  String? _tokenFor(ApiAuth kind) => switch (kind) {
    ApiAuth.parent => _parent?.token,
    ApiAuth.child => _child?.token,
    ApiAuth.none => null,
  };

  Future<void> init() async {
    _parent = await _readSession(_kParentKey);
    _child = await _readSession(_kChildKey);
    final raw = await _store.read(_kActiveChildKey);
    if (raw != null && _child != null) {
      try {
        _activeChild = ChildProfile.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        await _store.delete(_kActiveChildKey);
      }
    }
    notifyListeners();
  }

  Future<AuthSession?> _readSession(String key) async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    try {
      final s = AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (!s.isExpired(_clock())) return s;
    } catch (_) {
      // dữ liệu hỏng: bỏ
    }
    await _store.delete(key);
    return null;
  }

  Future<void> _save(String key, AuthSession s) =>
      _store.write(key, jsonEncode(s.toJson()));

  void _onUnauthorized(ApiAuth kind) {
    switch (kind) {
      case ApiAuth.parent:
        _parent = null;
        unawaited(_store.delete(_kParentKey));
        notice.value = 'Phiên đăng nhập đã hết hạn, hãy đăng nhập lại.';
      case ApiAuth.child:
        _child = null;
        _activeChild = null;
        unawaited(_store.delete(_kChildKey));
        unawaited(_store.delete(_kActiveChildKey));
        notice.value =
            'Máy này đã được gỡ khỏi hồ sơ của bé. Nhờ bố mẹ liên kết lại nhé.';
      case ApiAuth.none:
        return;
    }
    notifyListeners();
  }

  // ---------- Đăng ký / đăng nhập (phụ huynh, admin) ----------

  /// Bước 1 đăng ký: máy chủ gửi mã 6 số tới email.
  Future<void> register(String email, String password, String fullName) async {
    await api.post(
      '/api/auth/register',
      body: {'email': email.trim(), 'password': password, 'fullName': fullName.trim()},
    );
  }

  /// Bước 1 đăng nhập: email + mật khẩu đúng thì máy chủ gửi mã OTP.
  Future<void> requestLoginOtp(String email, String password) async {
    await api.post(
      '/api/auth/login',
      body: {'userNameOrEmail': email.trim(), 'password': password},
    );
  }

  Future<void> resendOtp(String email) async {
    await api.post(
      '/api/auth/resend-otp',
      body: {'userNameOrEmail': email.trim()},
    );
  }

  /// Bước 2 (đăng ký hoặc đăng nhập): nhập mã → nhận phiên.
  Future<AuthSession> verifyOtp(String email, String code) async {
    final json = await api.post(
      '/api/auth/verify-otp',
      body: {'userNameOrEmail': email.trim(), 'code': code.trim()},
    );
    return _signInParent(json);
  }

  Future<void> forgotPassword(String email) async {
    await api.post('/api/auth/forgot-password', body: {'email': email.trim()});
  }

  Future<AuthSession> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    final json = await api.post(
      '/api/auth/reset-password',
      body: {'email': email.trim(), 'code': code.trim(), 'newPassword': newPassword},
    );
    return _signInParent(json);
  }

  /// Ném [GoogleCancelled] nếu người dùng huỷ, [GoogleNotConfigured] / [GoogleSignInFailed] nếu Google lỗi.
  Future<AuthSession> signInWithGoogle() async {
    final idToken = await _google.getIdToken();
    final json = await api.post(
      '/api/auth/google-login',
      body: {'idToken': idToken},
    );
    return _signInParent(json);
  }

  Future<AuthSession> _signInParent(dynamic json) async {
    final s = AuthSession.fromJson(json as Map<String, dynamic>);
    if (s.role == UserRole.child) {
      throw const ApiException('Tài khoản này không đăng nhập bằng email được.');
    }
    _parent = s;
    await _save(_kParentKey, s);
    notifyListeners();
    return s;
  }

  /// Đăng xuất hoàn toàn: xoá phiên trên máy ngay, rồi báo máy chủ thu hồi token (thất bại cũng không sao).
  Future<void> signOut() async {
    final parentToken = _parent?.token;
    final childToken = _child?.token;
    _parent = null;
    _child = null;
    _activeChild = null;
    await _store.delete(_kParentKey);
    await _store.delete(_kChildKey);
    await _store.delete(_kActiveChildKey);
    notifyListeners();
    await _google.signOut();
    await Future.wait([
      for (final t in [parentToken, childToken])
        if (t != null) _revoke(t),
    ]);
  }

  Future<void> _revoke(String token) async {
    try {
      await api
          .post('/api/auth/logout', token: token)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // mất mạng hoặc token đã chết: phiên cục bộ đã xoá là đủ
    }
  }

  // ---------- Hồ sơ bé (phụ huynh) ----------

  Future<List<ChildProfile>> loadChildren() async {
    final json = await api.get('/api/children', auth: ApiAuth.parent);
    return [
      for (final c in json as List<dynamic>)
        ChildProfile.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<ChildProfile> loadChild(String id) async => ChildProfile.fromJson(
    await api.get('/api/children/$id', auth: ApiAuth.parent)
        as Map<String, dynamic>,
  );

  Future<ChildProfile> createChild(
    String nickname,
    String? avatarKey,
    int? birthYear,
  ) async => ChildProfile.fromJson(
    await api.post(
          '/api/children',
          body: {'nickname': nickname.trim(), 'avatarKey': avatarKey, 'birthYear': birthYear},
          auth: ApiAuth.parent,
        )
        as Map<String, dynamic>,
  );

  Future<ChildProfile> updateChild(
    String id, {
    required String nickname,
    String? avatarKey,
    int? birthYear,
    required bool isActive,
  }) async {
    final updated = ChildProfile.fromJson(
      await api.put(
            '/api/children/$id',
            body: {
              'nickname': nickname.trim(),
              'avatarKey': avatarKey,
              'birthYear': birthYear,
              'isActive': isActive,
            },
            auth: ApiAuth.parent,
          )
          as Map<String, dynamic>,
    );
    if (_activeChild?.id == id) {
      _activeChild = updated;
      await _store.write(_kActiveChildKey, jsonEncode(updated.toJson()));
      notifyListeners();
    }
    return updated;
  }

  Future<ChildProfile> updateChildSettings(
    String id, {
    int? dailyLimitMinutes,
    required int dailyWordGoal,
  }) async => ChildProfile.fromJson(
    await api.put(
          '/api/children/$id/settings',
          body: {'dailyLimitMinutes': dailyLimitMinutes, 'dailyWordGoal': dailyWordGoal},
          auth: ApiAuth.parent,
        )
        as Map<String, dynamic>,
  );

  Future<void> deleteChild(String id) async {
    await api.delete('/api/children/$id', auth: ApiAuth.parent);
    if (_activeChild?.id == id) await _clearChild();
  }

  // ---------- Dashboard phụ huynh ----------

  /// Thẻ tóm tắt của mọi bé, theo id.
  Future<Map<String, ChildOverview>> loadOverview() async {
    final json = await api.get('/api/parent/overview', auth: ApiAuth.parent);
    return {
      for (final c in json as List<dynamic>)
        (c as Map<String, dynamic>)['id'] as String: ChildOverview.fromJson(c),
    };
  }

  Future<ChildDashboard> loadDashboard(String childId, int days) async => ChildDashboard.fromJson(
    await api.get('/api/parent/children/$childId/dashboard?days=$days', auth: ApiAuth.parent)
        as Map<String, dynamic>,
  );

  /// CSV để chép sang Excel/Google Sheets. [kind]: `daily` (từng ngày) hoặc `words` (từng từ).
  Future<String> exportCsv(String childId, {required String kind, int days = 30}) =>
      api.getText('/api/parent/children/$childId/export.csv?kind=$kind&days=$days', auth: ApiAuth.parent);

  /// Xoá toàn bộ tiến độ học của bé trên máy chủ (hồ sơ và thiết bị giữ nguyên).
  Future<void> resetChildProgress(String id) =>
      api.delete('/api/children/$id/progress', auth: ApiAuth.parent);

  Future<List<DeviceSession>> childDevices(String id) async {
    final json = await api.get('/api/children/$id/sessions', auth: ApiAuth.parent);
    return [
      for (final s in json as List<dynamic>)
        DeviceSession.fromJson(s as Map<String, dynamic>),
    ];
  }

  Future<void> revokeDevice(String childId, String sessionId) => api.delete(
    '/api/children/$childId/sessions/$sessionId',
    auth: ApiAuth.parent,
  );

  Future<void> revokeAllDevices(String childId) => api.post(
    '/api/children/$childId/revoke-sessions',
    auth: ApiAuth.parent,
  );

  Future<LinkCode> createLinkCode(String childId) async => LinkCode.fromJson(
    await api.post('/api/children/$childId/link-code', auth: ApiAuth.parent)
        as Map<String, dynamic>,
  );

  // ---------- Chế độ bé ----------

  /// Phụ huynh cho bé dùng ngay máy này: máy chủ cấp phiên role Child cho thiết bị này.
  Future<void> startChildSession(ChildProfile profile) async {
    if (_child != null) await leaveChildMode();
    final d = await _device.get();
    final json = await api.post(
      '/api/children/${profile.id}/session',
      body: {'deviceId': d.id, 'deviceName': d.name},
      auth: ApiAuth.parent,
    );
    await _enterChildMode(AuthSession.fromJson(json as Map<String, dynamic>), profile);
  }

  /// Máy của bé nhập mã liên kết do phụ huynh tạo. Không cần đăng nhập.
  Future<void> linkWithCode(String code) async {
    final d = await _device.get();
    final json = await api.post(
      '/api/auth/child-link',
      body: {'code': code.replaceAll(RegExp(r'\s'), ''), 'deviceId': d.id, 'deviceName': d.name},
    );
    final session = AuthSession.fromJson(json as Map<String, dynamic>);
    ChildProfile profile;
    _child = session; // để gọi được /api/child/me bằng token vừa nhận
    try {
      profile = ChildProfile.fromJson(
        await api.get('/api/child/me', auth: ApiAuth.child) as Map<String, dynamic>,
      );
    } catch (_) {
      profile = ChildProfile(id: '', nickname: session.fullName);
    }
    await _enterChildMode(session, profile);
  }

  Future<void> _enterChildMode(AuthSession s, ChildProfile profile) async {
    _child = s;
    _activeChild = profile;
    await _save(_kChildKey, s);
    await _store.write(_kActiveChildKey, jsonEncode(profile.toJson()));
    notifyListeners();
  }

  /// Thoát chế độ bé trên máy này (và thu hồi phiên của máy này trên máy chủ).
  Future<void> leaveChildMode() async {
    final token = _child?.token;
    await _clearChild();
    if (token != null) await _revoke(token);
  }

  Future<void> _clearChild() async {
    _child = null;
    _activeChild = null;
    await _store.delete(_kChildKey);
    await _store.delete(_kActiveChildKey);
    notifyListeners();
  }
}

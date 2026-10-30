import 'dart:convert';

import 'package:english_cam/core/api_client.dart';
import 'package:english_cam/data/account/account_models.dart';
import 'package:english_cam/services/auth_service.dart';
import 'package:english_cam/services/device_identity.dart';
import 'package:english_cam/services/google_auth.dart';
import 'package:english_cam/services/key_value_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

/// Thuần Dart: máy chủ giả trong bộ nhớ, kho lưu trong bộ nhớ.
({AuthService auth, FakeServer server, MemoryKeyValueStore store, FakeGoogle google}) _make({
  FakeServer? server,
  MemoryKeyValueStore? store,
  DateTime Function()? clock,
}) {
  final s = server ?? FakeServer();
  final st = store ?? MemoryKeyValueStore();
  final g = FakeGoogle();
  final auth = AuthService(
    api: ApiClient(baseUrl: 'https://api.test', transport: s.call),
    store: st,
    google: g,
    device: FakeDevice(),
    clock: clock,
  );
  return (auth: auth, server: s, store: st, google: g);
}

void main() {
  group('Đăng nhập phụ huynh', () {
    test('email + mật khẩu → OTP → lưu phiên, khôi phục được sau khi mở lại app', () async {
      final s = FakeServer()
        ..on('POST /api/auth/login', 200, {'requiresOtp': true})
        ..on('POST /api/auth/verify-otp', 200, authJson());
      final m = _make(server: s);

      await m.auth.requestLoginOtp('  lan@test.com ', 'Matkhau123');
      expect(m.auth.isGuest, isTrue, reason: 'chưa nhập OTP thì chưa đăng nhập');
      expect(s.bodyOf(s.calls.first)['userNameOrEmail'], 'lan@test.com');

      final session = await m.auth.verifyOtp('lan@test.com', ' 123456 ');
      expect(session.role, UserRole.parent);
      expect(m.auth.isParentSignedIn, isTrue);
      expect(m.auth.landingRoute, '/children');
      expect(s.bodyOf(s.to('POST /api/auth/verify-otp').single)['code'], '123456');

      // "Mở lại app": AuthService mới đọc cùng kho.
      final again = _make(server: s, store: m.store).auth;
      await again.init();
      expect(again.parent?.fullName, 'Mẹ Lan');
      expect(again.parent?.token, 'tok-parent');
    });

    test('admin được đưa tới trang quản trị', () async {
      final s = FakeServer()
        ..on('POST /api/auth/verify-otp', 200, authJson(role: 'Admin', name: 'Quản trị viên'));
      final m = _make(server: s);
      await m.auth.verifyOtp('a@b.com', '111111');
      expect(m.auth.isAdmin, isTrue);
      expect(m.auth.landingRoute, '/admin');
    });

    test('token role Child không được dùng làm phiên phụ huynh', () async {
      final s = FakeServer()..on('POST /api/auth/verify-otp', 200, authJson(role: 'Child'));
      final m = _make(server: s);
      await expectLater(m.auth.verifyOtp('a@b.com', '111111'), throwsA(isA<ApiException>()));
      expect(m.auth.isGuest, isTrue);
    });

    test('phiên đã hết hạn bị bỏ khi mở app', () async {
      final s = FakeServer()..on('POST /api/auth/verify-otp', 200, authJson(lifetime: const Duration(days: 7)));
      final first = _make(server: s);
      await first.auth.verifyOtp('lan@test.com', '123456');

      final later = _make(
        server: s,
        store: first.store,
        clock: () => DateTime.now().add(const Duration(days: 8)),
      );
      await later.auth.init();
      expect(later.auth.isGuest, isTrue);
      expect(await first.store.read('auth.parent'), isNull, reason: 'đã xoá khỏi kho');
    });

    test('dữ liệu hỏng trong kho không làm app sập', () async {
      final store = MemoryKeyValueStore()..data['auth.parent'] = '{không phải json';
      final m = _make(store: store);
      await m.auth.init();
      expect(m.auth.isGuest, isTrue);
    });

    test('Google: gửi idToken lên máy chủ; huỷ thì ném GoogleCancelled', () async {
      final s = FakeServer()..on('POST /api/auth/google-login', 200, authJson(name: 'Bố Nam'));
      final m = _make(server: s);
      await m.auth.signInWithGoogle();
      expect(s.bodyOf(s.calls.single), {'idToken': 'google-id-token'});
      expect(m.auth.parent?.fullName, 'Bố Nam');

      final m2 = _make(server: s);
      m2.google.error = GoogleCancelled();
      await expectLater(m2.auth.signInWithGoogle(), throwsA(isA<GoogleCancelled>()));
      expect(m2.auth.isGuest, isTrue);
    });

    test('quên mật khẩu → đặt lại → đăng nhập luôn', () async {
      final s = FakeServer()
        ..on('POST /api/auth/forgot-password', 200, {'message': 'ok'})
        ..on('POST /api/auth/reset-password', 200, authJson());
      final m = _make(server: s);
      await m.auth.forgotPassword('lan@test.com');
      await m.auth.resetPassword('lan@test.com', '654321', 'Moimatkhau9');
      expect(s.bodyOf(s.to('POST /api/auth/reset-password').single)['newPassword'], 'Moimatkhau9');
      expect(m.auth.isParentSignedIn, isTrue);
    });
  });

  group('Phiên bị kết thúc ngoài ý muốn (401)', () {
    test('token phụ huynh hết hạn → về khách + có thông báo', () async {
      final s = FakeServer()
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('GET /api/children', 401);
      final m = _make(server: s);
      await m.auth.verifyOtp('lan@test.com', '123456');
      await expectLater(m.auth.loadChildren(), throwsA(isA<ApiException>()));
      expect(m.auth.isParentSignedIn, isFalse);
      expect(m.auth.notice.value, contains('hết hạn'));
      expect(await m.store.read('auth.parent'), isNull);
    });

    test('nhập sai OTP (401 không kèm token) KHÔNG đăng xuất và KHÔNG báo hết phiên', () async {
      final s = FakeServer()..on('POST /api/auth/verify-otp', 401, {'message': 'OTP sai hoặc hết hạn'});
      final m = _make(server: s);
      await expectLater(
        m.auth.verifyOtp('lan@test.com', '000000'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'OTP sai hoặc hết hạn')),
      );
      expect(m.auth.notice.value, isNull);
    });

    test('máy của bé bị bố mẹ gỡ → thoát chế độ bé + thông báo, phiên phụ huynh giữ nguyên', () async {
      final s = FakeServer()
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('POST /api/children/c1/session', 200, authJson(role: 'Child', token: 'tok-child', userId: 'k1', name: 'Bi', email: ''))
        ..on('GET /api/child/me', 401);
      final m = _make(server: s);
      await m.auth.verifyOtp('lan@test.com', '123456');
      await m.auth.startChildSession(ChildProfile.fromJson(childJson()));
      expect(m.auth.inChildMode, isTrue);

      await expectLater(m.auth.api.get('/api/child/me', auth: ApiAuth.child), throwsA(isA<ApiException>()));
      expect(m.auth.inChildMode, isFalse);
      expect(m.auth.isParentSignedIn, isTrue);
      expect(m.auth.notice.value, contains('gỡ khỏi hồ sơ'));
      expect(await m.store.read('auth.child'), isNull);
    });
  });

  group('Chế độ bé', () {
    test('phụ huynh cho bé chơi: gửi mã + tên máy, lưu phiên và hồ sơ bé', () async {
      final s = FakeServer()
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('POST /api/children/c1/session', 200, authJson(role: 'Child', token: 'tok-child', userId: 'k1', name: 'Bi', email: ''));
      final m = _make(server: s);
      await m.auth.verifyOtp('lan@test.com', '123456');
      await m.auth.startChildSession(ChildProfile.fromJson(childJson(avatarKey: 'fox')));

      final req = s.to('POST /api/children/c1/session').single;
      expect(s.bodyOf(req), {'deviceId': 'device-123', 'deviceName': 'Máy thử'});
      expect(req.headers['Authorization'], 'Bearer tok-parent', reason: 'tạo phiên bằng token phụ huynh');
      expect(m.auth.child?.token, 'tok-child');
      expect(m.auth.activeChild?.avatarKey, 'fox');

      final again = _make(server: s, store: m.store).auth;
      await again.init();
      expect(again.inChildMode, isTrue);
      expect(again.activeChild?.nickname, 'Bi');
    });

    test('đổi từ bé A sang bé B: phiên của A bị thu hồi trên máy chủ', () async {
      final s = FakeServer()
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..handle('POST /api/children/a/session', (_) => FakeServer.json(200, authJson(role: 'Child', token: 'tok-A', name: 'A', email: '')))
        ..handle('POST /api/children/b/session', (_) => FakeServer.json(200, authJson(role: 'Child', token: 'tok-B', name: 'B', email: '')))
        ..on('POST /api/auth/logout', 204);
      final m = _make(server: s);
      await m.auth.verifyOtp('lan@test.com', '123456');
      await m.auth.startChildSession(ChildProfile.fromJson(childJson(id: 'a', nickname: 'A')));
      await m.auth.startChildSession(ChildProfile.fromJson(childJson(id: 'b', nickname: 'B')));

      expect(s.to('POST /api/auth/logout').single.headers['Authorization'], 'Bearer tok-A');
      expect(m.auth.child?.token, 'tok-B');
      expect(m.auth.activeChild?.nickname, 'B');
    });

    test('máy của bé nhập mã liên kết: bỏ khoảng trắng, lấy hồ sơ từ /api/child/me', () async {
      final s = FakeServer()
        ..on('POST /api/auth/child-link', 200, authJson(role: 'Child', token: 'tok-child', userId: 'k1', name: 'Bi', email: ''))
        ..on('GET /api/child/me', 200, childJson(avatarKey: 'panda', goal: 8));
      final m = _make(server: s);
      await m.auth.linkWithCode('1234 5678');

      final body = s.bodyOf(s.to('POST /api/auth/child-link').single);
      expect(body, {'code': '12345678', 'deviceId': 'device-123', 'deviceName': 'Máy thử'});
      expect(s.to('GET /api/child/me').single.headers['Authorization'], 'Bearer tok-child');
      expect(m.auth.isParentSignedIn, isFalse, reason: 'máy của bé không cần tài khoản');
      expect(m.auth.inChildMode, isTrue);
      expect(m.auth.activeChild?.dailyWordGoal, 8);
    });

    test('lấy hồ sơ thất bại vẫn vào chế độ bé với tên từ phiên', () async {
      final s = FakeServer()
        ..on('POST /api/auth/child-link', 200, authJson(role: 'Child', token: 'tok-child', name: 'Bi', email: ''))
        ..on('GET /api/child/me', 500);
      final m = _make(server: s);
      await m.auth.linkWithCode('12345678');
      expect(m.auth.inChildMode, isTrue);
      expect(m.auth.activeChild?.nickname, 'Bi');
    });

    test('mã sai: báo lỗi của máy chủ và không vào chế độ bé', () async {
      final s = FakeServer()..on('POST /api/auth/child-link', 401, {'message': 'Mã không đúng hoặc đã hết hạn'});
      final m = _make(server: s);
      await expectLater(m.auth.linkWithCode('00000000'), throwsA(isA<ApiException>()));
      expect(m.auth.inChildMode, isFalse);
      expect(m.auth.notice.value, isNull);
    });

    test('thoát chế độ bé: xoá cục bộ ngay, báo máy chủ thu hồi; mất mạng cũng không sao', () async {
      final s = FakeServer()
        ..on('POST /api/auth/child-link', 200, authJson(role: 'Child', token: 'tok-child', name: 'Bi', email: ''))
        ..on('GET /api/child/me', 200, childJson());
      final m = _make(server: s); // /api/auth/logout chưa khai báo → 404, coi như máy chủ lỗi
      await m.auth.linkWithCode('12345678');
      await m.auth.leaveChildMode();
      expect(m.auth.inChildMode, isFalse);
      expect(s.to('POST /api/auth/logout').single.headers['Authorization'], 'Bearer tok-child');
      expect(await m.store.read('auth.child'), isNull);
    });

    test('sửa hồ sơ bé đang dùng máy này thì chế độ bé cập nhật theo', () async {
      final s = FakeServer()
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('POST /api/children/c1/session', 200, authJson(role: 'Child', token: 'tok-child', name: 'Bi', email: ''))
        ..on('PUT /api/children/c1', 200, childJson(nickname: 'Bi Bo', avatarKey: 'bear'));
      final m = _make(server: s);
      await m.auth.verifyOtp('lan@test.com', '123456');
      await m.auth.startChildSession(ChildProfile.fromJson(childJson()));
      await m.auth.updateChild('c1', nickname: 'Bi Bo', avatarKey: 'bear', isActive: true);
      expect(m.auth.activeChild?.nickname, 'Bi Bo');
    });

    test('xoá đúng bé đang dùng máy này thì thoát chế độ bé', () async {
      final s = FakeServer()
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('POST /api/children/c1/session', 200, authJson(role: 'Child', token: 'tok-child', name: 'Bi', email: ''))
        ..on('DELETE /api/children/c1', 204);
      final m = _make(server: s);
      await m.auth.verifyOtp('lan@test.com', '123456');
      await m.auth.startChildSession(ChildProfile.fromJson(childJson()));
      await m.auth.deleteChild('c1');
      expect(m.auth.inChildMode, isFalse);
    });
  });

  group('Đăng xuất', () {
    test('xoá hết phiên ngay trên máy, thu hồi cả hai token trên máy chủ, đăng xuất Google', () async {
      final s = FakeServer()
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('POST /api/children/c1/session', 200, authJson(role: 'Child', token: 'tok-child', name: 'Bi', email: ''))
        ..on('POST /api/auth/logout', 204);
      final m = _make(server: s);
      await m.auth.verifyOtp('lan@test.com', '123456');
      await m.auth.startChildSession(ChildProfile.fromJson(childJson()));
      await m.auth.signOut();

      expect(m.auth.isGuest, isTrue);
      expect(m.store.data.keys.where((k) => k.startsWith('auth.')), isEmpty);
      final tokens = s.to('POST /api/auth/logout').map((c) => c.headers['Authorization']).toSet();
      expect(tokens, {'Bearer tok-parent', 'Bearer tok-child'});
      expect(m.google.signOuts, 1);
    });

    test('máy chủ không trả lời vẫn đăng xuất được', () async {
      final s = FakeServer()..on('POST /api/auth/verify-otp', 200, authJson());
      final m = _make(server: s);
      await m.auth.verifyOtp('lan@test.com', '123456');
      await m.auth.signOut(); // logout → 404
      expect(m.auth.isGuest, isTrue);
    });
  });

  group('Danh sách và thao tác hồ sơ bé', () {
    test('đọc danh sách, thiết bị, mã liên kết', () async {
      final s = FakeServer()
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('GET /api/children', 200, [childJson(), childJson(id: 'c2', nickname: 'Na', active: false)])
        ..on('GET /api/children/c1/sessions', 200, [
          {
            'id': 's1',
            'deviceId': 'd',
            'deviceName': 'Samsung A51',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'lastUsedAt': null,
            'expiresAt': DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String(),
          },
        ])
        ..on('POST /api/children/c1/link-code', 200, {
          'code': '12345678',
          'expiresAt': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
        });
      final m = _make(server: s);
      await m.auth.verifyOtp('lan@test.com', '123456');

      final list = await m.auth.loadChildren();
      expect(list.map((c) => c.nickname), ['Bi', 'Na']);
      expect(list.last.isActive, isFalse);
      expect((await m.auth.childDevices('c1')).single.deviceName, 'Samsung A51');
      expect((await m.auth.createLinkCode('c1')).pretty, '1234 5678');
      for (final c in s.calls.skip(1)) {
        expect(c.headers['Authorization'], 'Bearer tok-parent');
      }
    });

    test('cài đặt mục tiêu/giới hạn gửi đúng body (giới hạn tắt = null)', () async {
      final s = FakeServer()
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('PUT /api/children/c1/settings', 200, childJson(goal: 8));
      final m = _make(server: s);
      await m.auth.verifyOtp('lan@test.com', '123456');
      await m.auth.updateChildSettings('c1', dailyLimitMinutes: null, dailyWordGoal: 8);
      expect(
        jsonDecode(s.to('PUT /api/children/c1/settings').single.body!),
        {'dailyLimitMinutes': null, 'dailyWordGoal': 8},
      );
    });
  });

  group('Mã thiết bị', () {
    test('sinh một lần rồi giữ nguyên', () async {
      final oldPrint = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) {}; // plugin device_info không có trong test: nhánh dự phòng
      addTearDown(() => debugPrint = oldPrint);
      final store = MemoryKeyValueStore();
      final a = await StoredDeviceIdentity(store).get();
      final b = await StoredDeviceIdentity(store).get();
      expect(a.id, hasLength(32));
      expect(b.id, a.id);
      expect(a.name, isNotEmpty);
    });
  });
}

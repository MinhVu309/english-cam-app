import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../data/feedback/recognition_feedback.dart';
import 'auth_service.dart';

const String _kOutboxKey = 'feedback.outbox';
const int _kMaxQueued = 100;
const Duration _kMaxAge = Duration(days: 7);
const Duration _kDebounce = Duration(seconds: 3);

/// Gửi góp ý nhận diện lên backend, kiểu **offline-first**: lưu ngay vào hàng đợi trên máy (không mất khi mất mạng
/// hay tắt app), có mạng và có phiên đăng nhập thì gửi. Chỉ gửi chữ, không bao giờ gửi ảnh.
///
/// Mỗi ảnh chụp có một góp ý với `id` riêng: chọn lại trên cùng ảnh thì cập nhật góp ý trong hàng đợi (hoặc trên
/// máy chủ nếu đã gửi), không tạo thêm. Gửi tuần tự, cũ trước.
class FeedbackService with WidgetsBindingObserver {
  FeedbackService({
    AuthService? auth,
    DateTime Function()? clock,
    this.autoFlush = true,
  }) : _authOverride = auth,
       _clock = clock ?? DateTime.now;

  static FeedbackService instance = FeedbackService();

  final AuthService? _authOverride;
  final DateTime Function() _clock;

  /// Tự gửi sau mỗi lần lưu, khi quay lại app và khi đăng nhập. Test đặt false rồi gọi [flush] bằng tay.
  final bool autoFlush;

  AuthService get _auth => _authOverride ?? AuthService.instance;

  List<Map<String, dynamic>> _queue = [];
  bool _loaded = false;
  bool _flushing = false;
  bool _flushAgain = false;
  bool _attached = false;
  Timer? _debounce;

  /// Số góp ý đang chờ gửi.
  int get pending => _queue.length;

  /// Thân yêu cầu của các góp ý đang chờ gửi (cho test).
  @visibleForTesting
  List<Map<String, dynamic>> get queuedBodies => [
    for (final e in _queue) Map<String, dynamic>.from(e['body'] as Map),
  ];

  /// Nạp hàng đợi đã lưu, theo dõi đăng nhập/quay lại app để gửi bù. Gọi một lần khi khởi động.
  Future<void> start() async {
    await _load();
    if (_attached) return;
    _attached = true;
    _auth.addListener(_onAuth);
    if (autoFlush) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(flush());
    }
  }

  void stop() {
    _debounce?.cancel();
    if (_attached) {
      _auth.removeListener(_onAuth);
      if (autoFlush) WidgetsBinding.instance.removeObserver(this);
    }
    _attached = false;
  }

  bool _hadSession = false;

  void _onAuth() {
    final has = !_auth.isGuest;
    if (has && !_hadSession && autoFlush) unawaited(flush());
    _hadSession = has;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(flush());
  }

  /// Lưu (hoặc cập nhật theo `id`) một góp ý vào hàng đợi rồi hẹn gửi.
  Future<void> save(RecognitionFeedback fb) async {
    await _load();
    final entry = {
      'savedAt': _clock().toUtc().toIso8601String(),
      'body': fb.toJson(),
    };
    final i = _queue.indexWhere((e) => (e['body'] as Map)['id'] == fb.id);
    if (i >= 0) {
      _queue[i] = entry;
    } else {
      _queue.add(entry);
      while (_queue.length > _kMaxQueued) {
        _queue.removeAt(0);
      }
    }
    await _persist();
    if (autoFlush) {
      _debounce?.cancel();
      _debounce = Timer(_kDebounce, () => unawaited(flush()));
    }
  }

  /// Gửi hàng đợi. Lỗi mạng/máy chủ/hết phiên: giữ lại gửi sau. Máy chủ từ chối vì dữ liệu (400, 409): bỏ, đừng kẹt hàng đợi.
  /// Trả true nếu hàng đợi đã trống.
  Future<bool> flush() async {
    await _load();
    if (_flushing) {
      _flushAgain =
          true; // có thay đổi mới trong lúc đang gửi: gửi tiếp ngay khi xong
      return false;
    }
    _flushing = true;
    try {
      _dropExpired();
      while (_queue.isNotEmpty) {
        final kind = _tokenKind();
        if (kind == null) break; // chưa đăng nhập: để đó
        final entry = _queue.first;
        final body = Map<String, dynamic>.from(entry['body'] as Map);
        try {
          await _auth.api.post(
            '/api/feedback/recognition',
            body: body,
            auth: kind,
          );
          _removeIfUnchanged(entry);
        } on ApiException catch (e) {
          final retryLater =
              e.isNetwork ||
              e.status == 401 ||
              e.status == 429 ||
              (e.status ?? 0) >= 500;
          if (retryLater) break;
          debugPrint(
            'Feedback: bỏ góp ý bị từ chối (${e.status}): ${e.message}',
          );
          _removeIfUnchanged(entry);
        }
        await _persist();
      }
      await _persist();
    } catch (e) {
      debugPrint('Feedback flush failed: $e');
    } finally {
      _flushing = false;
      if (_flushAgain) {
        _flushAgain = false;
        if (_queue.isNotEmpty && autoFlush) unawaited(flush());
      }
    }
    return _queue.isEmpty;
  }

  ApiAuth? _tokenKind() {
    if (_auth.inChildMode) return ApiAuth.child;
    if (_auth.isParentSignedIn) return ApiAuth.parent;
    return null;
  }

  /// Chỉ bỏ nếu mục này chưa bị `save` thay thế trong lúc đang gửi (người dùng vừa chọn lại đáp án).
  void _removeIfUnchanged(Map<String, dynamic> sent) {
    final id = (sent['body'] as Map)['id'];
    final i = _queue.indexWhere((e) => (e['body'] as Map)['id'] == id);
    if (i >= 0 && identical(_queue[i], sent)) {
      _queue.removeAt(i);
    }
  }

  void _dropExpired() {
    final cutoff = _clock().toUtc().subtract(_kMaxAge);
    _queue.removeWhere(
      (e) => (DateTime.tryParse(e['savedAt'] as String? ?? '') ?? cutoff)
          .isBefore(cutoff),
    );
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        _kOutboxKey,
      );
      if (raw != null) {
        _queue = [
          for (final e in jsonDecode(raw) as List<dynamic>)
            Map<String, dynamic>.from(e as Map),
        ];
      }
    } catch (e) {
      debugPrint('Feedback outbox unreadable, starting empty: $e');
    }
  }

  Future<void> _persist() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _kOutboxKey,
        jsonEncode(_queue),
      );
    } catch (e) {
      debugPrint('Feedback outbox save failed: $e');
    }
  }
}

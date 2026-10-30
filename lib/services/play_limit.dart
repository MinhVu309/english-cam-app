import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Giới hạn thời gian chơi mỗi ngày do bố mẹ đặt cho bé (`dailyLimitMinutes` trên máy chủ).
///
/// Thời gian đã dùng hôm nay = số giây máy chủ đã biết + phần chưa gửi + thời gian đang mở app ([liveSeconds]).
/// Khi chạm giới hạn thì khoá ([locked]) cho đến khi sang ngày mới, bố mẹ tăng giới hạn, hoặc bố mẹ bấm
/// "cho chơi thêm" ([grantMore], sau cổng phụ huynh). Trong lúc khoá, thời gian không đếm tiếp nên bảng
/// theo dõi của bố mẹ không bị phồng lên vì máy bé nằm yên ở màn hình khoá.
///
/// Trạng thái được nhớ theo từng hồ sơ bé để tắt/mở lại app hoặc tắt mạng không làm bé chơi tiếp được.
/// Ngày chia theo giờ của máy (máy chủ chia theo UTC+7): lệch giờ chỉ xảy ra ở vài giờ quanh nửa đêm khi múi giờ
/// của máy khác Việt Nam, và lần đồng bộ kế tiếp sẽ sửa lại.
class PlayLimit extends ChangeNotifier {
  PlayLimit({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Số giây đang mở app mà chưa được ghi vào [recordedSeconds]. SyncService gắn vào.
  int Function() liveSeconds = () => 0;

  String? _profile;
  int? _limitMinutes;
  int _recorded = 0;
  int _bonus = 0;
  String _day = '';
  bool _locked = false;
  bool _warned = false;

  /// Giới hạn phút/ngày (null = không giới hạn).
  int? get limitMinutes => _limitMinutes;

  /// Giây đã dùng hôm nay đã được ghi nhận.
  int get recordedSeconds => _recorded;

  /// Giây được bố mẹ cho thêm hôm nay.
  int get bonusSeconds => _bonus;

  /// true khi bé hết giờ và app đang khoá.
  bool get locked => _locked;

  /// Giây đã dùng hôm nay (kể cả phần đang mở app chưa ghi).
  int get usedSeconds => _recorded + (_locked ? 0 : liveSeconds());

  /// Số giây còn lại hôm nay; null nếu không giới hạn.
  int? get remainingSeconds {
    final limit = _limitMinutes;
    if (limit == null) return null;
    return limit * 60 + _bonus - usedSeconds;
  }

  bool get _enabled => _profile != null && _limitMinutes != null;

  String get _key => 'p.$_profile.playlimit';

  String _today() {
    final d = _clock().toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ---------- Đổi hồ sơ ----------

  /// Chuyển sang hồ sơ bé khác (null = thoát chế độ bé: không còn giới hạn) và nạp trạng thái đã nhớ.
  Future<void> useProfile(String? profileId) async {
    _profile = profileId == null || profileId.isEmpty ? null : profileId;
    _limitMinutes = null;
    _recorded = 0;
    _bonus = 0;
    _day = _today();
    _locked = false;
    _warned = false;
    if (_profile != null) {
      try {
        final raw = (await SharedPreferences.getInstance()).getString(_key);
        if (raw != null) {
          final j = jsonDecode(raw) as Map<String, dynamic>;
          _limitMinutes = j['limit'] as int?;
          if (j['day'] == _day) {
            _recorded = j['recorded'] as int? ?? 0;
            _bonus = j['bonus'] as int? ?? 0;
          }
        }
      } catch (e) {
        debugPrint('PlayLimit load failed: $e');
      }
    }
    evaluate();
    notifyListeners();
  }

  // ---------- Cập nhật số liệu ----------

  /// Máy chủ vừa báo: giới hạn hiện tại và số giây đã dùng hôm nay ([serverSeconds] + [pendingSeconds] chưa gửi).
  void applySnapshot({
    required int? limitMinutes,
    required int serverSeconds,
    required int pendingSeconds,
  }) {
    if (_profile == null) return;
    _rollDay();
    _limitMinutes = limitMinutes;
    // Lô đã được máy chủ xác nhận thì SyncService đã bỏ khỏi hàng đợi trước khi gọi, nên tổng này luôn đủ,
    // không đếm trùng; và nó giảm được khi bố mẹ xoá tiến độ của bé.
    _recorded = serverSeconds + pendingSeconds;
    if (limitMinutes == null) _bonus = 0;
    evaluate();
    _save();
    notifyListeners();
  }

  /// SyncService vừa ghi [seconds] giây dùng app vào hàng đợi.
  void addRecorded(int seconds) {
    if (_profile == null || seconds <= 0) return;
    _rollDay();
    _recorded += seconds;
    evaluate();
    _save();
    notifyListeners();
  }

  /// Gọi định kỳ: khoá nếu hết giờ (kể cả phần đang mở app), hoặc sang ngày mới thì mở khoá.
  /// Trả true nếu vừa chuyển sang khoá (để SyncService ghi nốt thời gian đang đếm).
  bool evaluate() {
    _rollDay();
    final wasLocked = _locked;
    final remaining = remainingSeconds;
    final shouldLock = _enabled && remaining != null && remaining <= 0;
    if (shouldLock == _locked) return false;
    _locked = shouldLock;
    if (wasLocked != _locked) notifyListeners();
    return _locked;
  }

  /// Sang ngày mới: số đã dùng và thời gian cho thêm về 0.
  void _rollDay() {
    final today = _today();
    if (today == _day) return;
    _day = today;
    _recorded = 0;
    _bonus = 0;
    _locked = false;
    _warned = false;
  }

  /// true đúng một lần mỗi ngày khi bé sắp hết giờ (còn không quá [kWarnSeconds] giây): để Cam nhắc trước.
  bool takeWarning() {
    final remaining = remainingSeconds;
    if (_warned ||
        !_enabled ||
        _locked ||
        remaining == null ||
        remaining <= 0 ||
        remaining > kWarnSeconds) {
      return false;
    }
    return _warned = true;
  }

  /// Còn bấy nhiêu giây thì nhắc bé.
  static const int kWarnSeconds = 300;

  /// Bố mẹ cho bé chơi thêm [minutes] phút kể từ bây giờ (qua cổng phụ huynh).
  void grantMore(int minutes) {
    final limit = _limitMinutes;
    if (_profile == null || limit == null || minutes <= 0) return;
    _rollDay();
    // Đã vượt hạn mức bao nhiêu thì bù bấy nhiêu, để bé được đúng [minutes] phút từ lúc này chứ không bị trừ phần dư.
    final over = _recorded - limit * 60;
    _bonus = (_bonus > over ? _bonus : over) + minutes * 60;
    _locked = false;
    _warned = false;
    evaluate();
    _save();
    notifyListeners();
  }

  Future<void> _save() async {
    if (_profile == null) return;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode({
          'limit': _limitMinutes,
          'day': _day,
          'recorded': _recorded,
          'bonus': _bonus,
        }),
      );
    } catch (e) {
      debugPrint('PlayLimit save failed: $e');
    }
  }
}

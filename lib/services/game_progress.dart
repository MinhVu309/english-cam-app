import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/game_badge.dart';
import 'progress_service.dart';

const String _kStars = 'game_stars';
const String _kRounds = 'game_rounds';
const String _kPerfect = 'game_perfect';
const String _kFound = 'game_found';
const String _kBadges = 'game_badges';
const String _kStreak = 'game_streak_best';

/// Sao, số ván và huy hiệu của hai game; lưu trên máy bằng shared_preferences.
/// Chỉ cộng thêm, không bao giờ trừ sao khi bé trả lời sai.
class GameProgress extends ChangeNotifier {
  GameProgress._();
  static final GameProgress instance = GameProgress._();

  SharedPreferences? _prefs;
  String _scope = '';
  int stars = 0;
  int rounds = 0;
  int perfectRounds = 0;
  int found = 0;

  /// Kỷ lục chuỗi ngày học liên tiếp (máy chủ tính; chỉ có khi bé đã đồng bộ).
  int streakBest = 0;
  final Set<String> badges = {};

  String _k(String base) => '$_scope$base';

  /// Tiền tố khoá lưu của ngăn đang dùng ('' = khách).
  String get scope => _scope;

  /// Chuyển sang ngăn lưu của một hồ sơ bé (hoặc về khách khi [profileId] là null) và nạp lại dữ liệu.
  Future<void> useProfile(String? profileId) {
    _scope = profileId == null || profileId.isEmpty ? '' : 'p.$profileId.';
    return init();
  }

  Future<void> init() async {
    stars = rounds = perfectRounds = found = streakBest = 0;
    badges.clear();
    try {
      final p = _prefs = await SharedPreferences.getInstance();
      stars = p.getInt(_k(_kStars)) ?? 0;
      rounds = p.getInt(_k(_kRounds)) ?? 0;
      perfectRounds = p.getInt(_k(_kPerfect)) ?? 0;
      found = p.getInt(_k(_kFound)) ?? 0;
      streakBest = p.getInt(_k(_kStreak)) ?? 0;
      badges.addAll(p.getStringList(_k(_kBadges)) ?? const []);
    } catch (e) {
      debugPrint('GameProgress init failed: $e');
    }
    notifyListeners();
  }

  /// Chỉ dùng trong test.
  @visibleForTesting
  void resetForTest() {
    _prefs = null;
    _scope = '';
    stars = rounds = perfectRounds = found = streakBest = 0;
    badges.clear();
  }

  /// Xoá sao, số ván và huy hiệu (bố mẹ chọn "Xoá tiến độ").
  Future<void> reset() async {
    stars = rounds = perfectRounds = found = streakBest = 0;
    badges.clear();
    notifyListeners();
    await _save();
  }

  bool hasBadge(String id) => badges.contains(id);

  int _metric(String name) => switch (name) {
    'stars' => stars,
    'rounds' => rounds,
    'perfect' => perfectRounds,
    'found' => found,
    'learned' => ProgressService.instance.learnedCount,
    'streak' => streakBest,
    _ => 0,
  };

  /// Máy chủ đẩy trạng thái về (đã cộng sẵn phần chưa gửi của máy này). Huy hiệu lấy theo máy chủ rồi tính lại theo
  /// số liệu mới, nên xoá tiến độ từ xa cũng xoá huy hiệu, còn huy hiệu vừa đạt khi offline thì vẫn giữ.
  Future<void> applyServer({
    required int stars,
    required int rounds,
    required int perfect,
    required int found,
    required int bestStreak,
    required Iterable<String> badgeIds,
  }) async {
    this.stars = stars;
    this.rounds = rounds;
    perfectRounds = perfect;
    this.found = found;
    streakBest = bestStreak;
    badges
      ..clear()
      ..addAll(badgeIds);
    checkBadges(); // huy hiệu đạt nhờ phần chưa gửi: giữ, không hiện hộp thoại
    notifyListeners();
    await _save();
  }

  /// Mở khoá các huy hiệu đã đủ điều kiện; trả về những huy hiệu mới.
  List<GameBadge> checkBadges() {
    final unlocked = <GameBadge>[];
    for (final b in BadgeRepository.instance.badges) {
      if (!badges.contains(b.id) && _metric(b.metric) >= b.threshold) {
        badges.add(b.id);
        unlocked.add(b);
      }
    }
    if (unlocked.isNotEmpty) _save();
    return unlocked;
  }

  /// Ghi nhận một ván "Nghe & chọn hình" đã xong.
  Future<List<GameBadge>> recordRound({
    required int starsEarned,
    required bool perfect,
  }) async {
    stars += starsEarned;
    rounds++;
    if (perfect) perfectRounds++;
    return _commit();
  }

  /// Ghi nhận bé đã tìm được một đồ vật thật.
  Future<List<GameBadge>> recordFound({int starsEarned = 2}) async {
    stars += starsEarned;
    found++;
    return _commit();
  }

  Future<List<GameBadge>> _commit() async {
    final unlocked = checkBadges();
    notifyListeners();
    await _save();
    return unlocked;
  }

  Future<void> _save() async {
    try {
      final p = _prefs;
      if (p == null) return;
      await p.setInt(_k(_kStars), stars);
      await p.setInt(_k(_kRounds), rounds);
      await p.setInt(_k(_kPerfect), perfectRounds);
      await p.setInt(_k(_kFound), found);
      await p.setInt(_k(_kStreak), streakBest);
      await p.setStringList(_k(_kBadges), badges.toList());
    } catch (e) {
      debugPrint('GameProgress save failed: $e');
    }
  }
}

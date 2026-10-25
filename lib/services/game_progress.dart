import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/game_badge.dart';
import 'progress_service.dart';

const String _kStars = 'game_stars';
const String _kRounds = 'game_rounds';
const String _kPerfect = 'game_perfect';
const String _kFound = 'game_found';
const String _kBadges = 'game_badges';

/// Sao, số ván và huy hiệu của hai game; lưu trên máy bằng shared_preferences.
/// Chỉ cộng thêm, không bao giờ trừ sao khi bé trả lời sai.
class GameProgress extends ChangeNotifier {
  GameProgress._();
  static final GameProgress instance = GameProgress._();

  SharedPreferences? _prefs;
  int stars = 0;
  int rounds = 0;
  int perfectRounds = 0;
  int found = 0;
  final Set<String> badges = {};

  Future<void> init() async {
    try {
      final p = _prefs = await SharedPreferences.getInstance();
      stars = p.getInt(_kStars) ?? 0;
      rounds = p.getInt(_kRounds) ?? 0;
      perfectRounds = p.getInt(_kPerfect) ?? 0;
      found = p.getInt(_kFound) ?? 0;
      badges
        ..clear()
        ..addAll(p.getStringList(_kBadges) ?? const []);
    } catch (e) {
      debugPrint('GameProgress init failed: $e');
    }
    notifyListeners();
  }

  /// Chỉ dùng trong test.
  @visibleForTesting
  void resetForTest() {
    _prefs = null;
    stars = rounds = perfectRounds = found = 0;
    badges.clear();
  }

  /// Xoá sao, số ván và huy hiệu (bố mẹ chọn "Xoá tiến độ").
  Future<void> reset() async {
    stars = rounds = perfectRounds = found = 0;
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
    _ => 0,
  };

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
      await p.setInt(_kStars, stars);
      await p.setInt(_kRounds, rounds);
      await p.setInt(_kPerfect, perfectRounds);
      await p.setInt(_kFound, found);
      await p.setStringList(_kBadges, badges.toList());
    } catch (e) {
      debugPrint('GameProgress save failed: $e');
    }
  }
}

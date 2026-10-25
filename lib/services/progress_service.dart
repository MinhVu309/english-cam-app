import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kLearnedKey = 'learned_words';

/// Lưu các từ bé đã học (chỉ trên máy, không gửi đi đâu).
class ProgressService extends ChangeNotifier {
  ProgressService._();
  static final ProgressService instance = ProgressService._();

  final Set<String> _learned = {};
  SharedPreferences? _prefs;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _learned
        ..clear()
        ..addAll(_prefs!.getStringList(_kLearnedKey) ?? const []);
    } catch (e) {
      // Không đọc được thì vẫn chạy được, chỉ là không nhớ tiến độ.
      debugPrint('Progress init failed: $e');
    }
    notifyListeners();
  }

  int get learnedCount => _learned.length;
  bool isLearned(String id) => _learned.contains(id);

  Future<void> setLearned(String id, bool value) async {
    final changed = value ? _learned.add(id) : _learned.remove(id);
    if (!changed) return;
    notifyListeners();
    try {
      await _prefs?.setStringList(_kLearnedKey, _learned.toList());
    } catch (e) {
      debugPrint('Progress save failed: $e');
    }
  }

  /// Xoá toàn bộ từ đã học.
  Future<void> clear() async {
    _learned.clear();
    notifyListeners();
    try {
      await _prefs?.remove(_kLearnedKey);
    } catch (e) {
      debugPrint('Progress clear failed: $e');
    }
  }

  Future<void> toggle(String id) => setLearned(id, !isLearned(id));
}

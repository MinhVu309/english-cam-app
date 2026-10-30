import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kLearnedKey = 'learned_words';

/// Lưu các từ bé đã học trên máy. Khi một hồ sơ bé đang dùng máy (đã đăng nhập), mỗi hồ sơ có một ngăn lưu riêng
/// ([useProfile]) và `SyncService` đồng bộ ngăn đó với máy chủ; chế độ khách dùng ngăn gốc và không gửi đi đâu.
class ProgressService extends ChangeNotifier {
  ProgressService._();
  static final ProgressService instance = ProgressService._();

  final Set<String> _learned = {};
  SharedPreferences? _prefs;
  String _scope = '';

  /// Được gọi mỗi khi bé/bố mẹ đánh dấu hoặc bỏ đánh dấu "đã học" (không gọi khi máy chủ đẩy trạng thái về).
  void Function(String wordId, bool learned)? onLearnedChanged;

  String get _key => '$_scope$_kLearnedKey';

  /// Tiền tố khoá lưu của ngăn đang dùng ('' = khách).
  String get scope => _scope;

  /// Chuyển sang ngăn lưu của một hồ sơ bé (hoặc về khách khi [profileId] là null) và nạp lại dữ liệu.
  Future<void> useProfile(String? profileId) {
    _scope = profileId == null || profileId.isEmpty ? '' : 'p.$profileId.';
    return init();
  }

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _learned
        ..clear()
        ..addAll(_prefs!.getStringList(_key) ?? const []);
    } catch (e) {
      // Không đọc được thì vẫn chạy được, chỉ là không nhớ tiến độ.
      debugPrint('Progress init failed: $e');
    }
    notifyListeners();
  }

  int get learnedCount => _learned.length;

  /// Bản sao tập từ đã học (cho đồng bộ và test).
  Set<String> get learned => Set.unmodifiable(_learned);
  bool isLearned(String id) => _learned.contains(id);

  Future<void> setLearned(String id, bool value) async {
    final changed = value ? _learned.add(id) : _learned.remove(id);
    if (!changed) return;
    notifyListeners();
    onLearnedChanged?.call(id, value);
    try {
      await _prefs?.setStringList(_key, _learned.toList());
    } catch (e) {
      debugPrint('Progress save failed: $e');
    }
  }

  /// Máy chủ đẩy trạng thái về: thay cả tập từ đã học (không tạo sự kiện đồng bộ mới).
  Future<void> replaceLearned(Set<String> ids) async {
    if (setEquals(_learned, ids)) return;
    _learned
      ..clear()
      ..addAll(ids);
    notifyListeners();
    try {
      await _prefs?.setStringList(_key, _learned.toList());
    } catch (e) {
      debugPrint('Progress replace failed: $e');
    }
  }

  /// Xoá toàn bộ từ đã học.
  Future<void> clear() async {
    _learned.clear();
    notifyListeners();
    try {
      await _prefs?.remove(_key);
    } catch (e) {
      debugPrint('Progress clear failed: $e');
    }
  }

  Future<void> toggle(String id) => setLearned(id, !isLearned(id));
}

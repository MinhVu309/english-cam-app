import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ảnh minh hoạ đóng gói sẵn trong app, tìm theo **mã từ / mã chủ đề**:
/// `assets/images/words/<id>.webp` và `assets/images/categories/<id>.webp`.
///
/// Dùng quy ước tên thay vì ghi đường dẫn vào `vocab.json` để ảnh vẫn hiện khi từ vựng đến từ gói cập nhật
/// (gói/backend có thể để `image: null`). Gói tự khai báo `image` thì ảnh của gói được ưu tiên. Từ chưa có ảnh
/// thì rơi về emoji rồi chữ cái đầu, như trước.
abstract final class BundledImages {
  static const String wordsDir = 'assets/images/words/';
  static const String categoriesDir = 'assets/images/categories/';
  static const String extension = '.webp';

  static Set<String> _words = {};
  static Set<String> _categories = {};

  /// Đọc danh sách asset đã đóng gói (một lần, ngay khi nạp từ vựng).
  static Future<void> load({AssetBundle? bundle}) async {
    try {
      final assets = (await AssetManifest.loadFromAssetBundle(
        bundle ?? rootBundle,
      )).listAssets();
      _words = _ids(assets, wordsDir);
      _categories = _ids(assets, categoriesDir);
    } catch (e) {
      debugPrint('BundledImages: không đọc được danh sách asset ($e)');
    }
  }

  static Set<String> _ids(Iterable<String> assets, String dir) => {
    for (final a in assets)
      if (a.startsWith(dir) && a.endsWith(extension))
        a.substring(dir.length, a.length - extension.length),
  };

  /// Đường dẫn ảnh đóng gói sẵn của từ [id], hoặc null nếu chưa có.
  static String? wordPath(String id) =>
      _words.contains(id) ? '$wordsDir$id$extension' : null;

  static String? categoryPath(String id) =>
      _categories.contains(id) ? '$categoriesDir$id$extension' : null;

  @visibleForTesting
  static Set<String> get wordIds => Set.unmodifiable(_words);

  @visibleForTesting
  static Set<String> get categoryIds => Set.unmodifiable(_categories);

  @visibleForTesting
  static void setForTest({
    Set<String> words = const {},
    Set<String> categories = const {},
  }) {
    _words = {...words};
    _categories = {...categories};
  }
}

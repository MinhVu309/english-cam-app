import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bundled_images.dart';
import 'pack/pack_manifest.dart';
import 'pack/pack_store.dart';
import 'vocab_word.dart';

const String kVocabAsset = 'assets/vocab/vocab.json';

/// Toàn bộ từ vựng nằm trong vocab.json, không hardcode trong code.
/// Ưu tiên vocab.json của gói đã tải (xem [PackStore]); hỏng hoặc chưa có thì dùng bản đóng gói sẵn.
class VocabRepository {
  VocabRepository._(this.categories, this.words)
    : _byLabel = {
        for (final w in words)
          if (w.label != null) w.label!: w,
      },
      _byId = {for (final w in words) w.id: w};

  /// Ném lỗi nếu JSON sai cấu trúc, trùng id/label, sai chủ đề, hoặc quá ít từ có hình
  /// cho game "Nghe & chọn hình".
  factory VocabRepository.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final repo = VocabRepository._(
      [
        for (final c in json['categories'] as List<dynamic>)
          VocabCategory.fromJson(c as Map<String, dynamic>),
      ],
      [
        for (final w in json['words'] as List<dynamic>)
          VocabWord.fromJson(w as Map<String, dynamic>),
      ],
    );
    repo._validate();
    return repo;
  }

  void _validate() {
    final categoryIds = {for (final c in categories) c.id};
    final ids = <String>{};
    final labels = <String>{};
    for (final w in words) {
      if (!ids.add(w.id)) throw FormatException('trùng id "${w.id}"');
      if (w.label != null && !labels.add(w.label!)) {
        throw FormatException('trùng label "${w.label}"');
      }
      if (!categoryIds.contains(w.category)) {
        throw FormatException(
          '"${w.id}": chủ đề "${w.category}" không tồn tại',
        );
      }
      for (final path in [w.audio, w.exampleAudio, w.image]) {
        if (path != null &&
            !PackStore.isBundled(path) &&
            !isSafePackPath(path)) {
          throw FormatException('"${w.id}": đường dẫn không an toàn "$path"');
        }
      }
    }
    if (words.where((w) => w.hasPicture).length < 4) {
      throw const FormatException('cần ít nhất 4 từ có hình minh hoạ');
    }
  }

  static VocabRepository? _instance;

  static VocabRepository get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('VocabRepository.load() chưa được gọi');
    }
    return i;
  }

  static Future<VocabRepository> load({AssetBundle? bundle}) async {
    await BundledImages.load(
      bundle: bundle,
    ); // trước khi phân tích JSON: ảnh theo mã từ dùng danh sách này
    final packed = PackStore.instance?.fileFor(kPackVocabFile);
    if (packed != null) {
      try {
        return _instance = VocabRepository.fromJsonString(
          await packed.readAsString(),
        );
      } catch (e) {
        debugPrint('Pack vocab unusable, using bundled: $e');
      }
    }
    final raw = await (bundle ?? rootBundle).loadString(kVocabAsset);
    return _instance = VocabRepository.fromJsonString(raw);
  }

  final List<VocabCategory> categories;
  final List<VocabWord> words;
  final Map<String, VocabWord> _byLabel;
  final Map<String, VocabWord> _byId;

  VocabWord? byLabel(String label) => _byLabel[label];
  VocabWord? byId(String id) => _byId[id];

  VocabCategory? category(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }
}

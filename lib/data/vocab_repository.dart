import 'dart:convert';

import 'package:flutter/services.dart';

import 'vocab_word.dart';

const String kVocabAsset = 'assets/vocab/vocab.json';

/// Toàn bộ từ vựng nằm trong vocab.json, không hardcode trong code.
class VocabRepository {
  VocabRepository._(this.categories, this.words)
    : _byLabel = {for (final w in words) w.label: w},
      _byId = {for (final w in words) w.id: w};

  factory VocabRepository.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return VocabRepository._(
      [
        for (final c in json['categories'] as List<dynamic>)
          VocabCategory.fromJson(c as Map<String, dynamic>),
      ],
      [
        for (final w in json['words'] as List<dynamic>)
          VocabWord.fromJson(w as Map<String, dynamic>),
      ],
    );
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

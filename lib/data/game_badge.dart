import 'dart:convert';

import 'package:flutter/services.dart';

const String kBadgesAsset = 'assets/game/badges.json';

/// Huy hiệu mở khoá khi một chỉ số đạt [threshold].
class GameBadge {
  const GameBadge({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.metric,
    required this.threshold,
  });

  factory GameBadge.fromJson(Map<String, dynamic> j) => GameBadge(
    id: j['id'] as String,
    name: j['name'] as String,
    description: j['description'] as String,
    emoji: j['emoji'] as String,
    metric: j['metric'] as String,
    threshold: j['threshold'] as int,
  );

  final String id;
  final String name;
  final String description;
  final String emoji;

  /// stars | rounds | perfect | found | learned
  final String metric;
  final int threshold;
}

class BadgeRepository {
  BadgeRepository(this.badges);

  factory BadgeRepository.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return BadgeRepository([
      for (final b in json['badges'] as List<dynamic>)
        GameBadge.fromJson(b as Map<String, dynamic>),
    ]);
  }

  static BadgeRepository? _instance;

  static BadgeRepository get instance {
    final i = _instance;
    if (i == null) throw StateError('BadgeRepository.load() chưa được gọi');
    return i;
  }

  static Future<BadgeRepository> load({AssetBundle? bundle}) async {
    final raw = await (bundle ?? rootBundle).loadString(kBadgesAsset);
    return _instance = BadgeRepository.fromJsonString(raw);
  }

  final List<GameBadge> badges;
}

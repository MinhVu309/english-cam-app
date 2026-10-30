import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// stars | rounds | perfect | found | learned | streak
  final String metric;
  final int threshold;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'emoji': emoji,
    'metric': metric,
    'threshold': threshold,
  };
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

  static const String _kCacheKey = 'badges.catalog';

  /// Ưu tiên danh sách huy hiệu máy chủ đã gửi lần trước (lưu trên máy), hỏng hoặc chưa có thì dùng bản đóng gói sẵn.
  static Future<BadgeRepository> load({AssetBundle? bundle}) async {
    try {
      final cached = (await SharedPreferences.getInstance()).getString(
        _kCacheKey,
      );
      if (cached != null) {
        return _instance = BadgeRepository.fromJsonString(cached);
      }
    } catch (e) {
      debugPrint('Badge cache unusable, using bundled: $e');
    }
    final raw = await (bundle ?? rootBundle).loadString(kBadgesAsset);
    return _instance = BadgeRepository.fromJsonString(raw);
  }

  /// Máy chủ gửi danh sách huy hiệu mới (Admin có thể thêm/sửa/xoá): dùng ngay và nhớ cho lần mở sau.
  static Future<void> replace(List<GameBadge> badges) async {
    if (badges.isEmpty) return;
    _instance = BadgeRepository(badges);
    try {
      await (await SharedPreferences.getInstance()).setString(
        _kCacheKey,
        jsonEncode({
          'badges': [for (final b in badges) b.toJson()],
        }),
      );
    } catch (e) {
      debugPrint('Badge cache save failed: $e');
    }
  }

  final List<GameBadge> badges;
}

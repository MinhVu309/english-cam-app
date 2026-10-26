import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'mascot.dart';

const String kMascotMessagesAsset = 'assets/mascot/messages.json';

/// Một câu Cam nhắn cho bé.
class MascotLine {
  const MascotLine(this.text, this.mood, this.when);

  final String text;
  final MascotMood mood;

  /// Điều kiện để câu này được chọn (any, no_learned, has_learned, has_stars).
  final String when;
}

/// Số liệu dùng để điền `{learned}`, `{stars}`, `{total}` vào câu nhắn.
class MascotContext {
  const MascotContext({this.learned = 0, this.stars = 0, this.total = 24});

  final int learned;
  final int stars;
  final int total;

  bool allows(String when) => switch (when) {
    'no_learned' => learned == 0,
    'has_learned' => learned > 0,
    'has_stars' => stars > 0,
    _ => true,
  };

  String fill(String template) => template
      .replaceAll('{learned}', '$learned')
      .replaceAll('{stars}', '$stars')
      .replaceAll('{total}', '$total');
}

/// Kho lời nhắn của Cam, nằm trong assets/mascot/messages.json.
class MascotMessages {
  MascotMessages(this._byContext);

  factory MascotMessages.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return MascotMessages({
      for (final e in json.entries)
        e.key: [
          for (final l in e.value as List<dynamic>)
            MascotLine(
              (l as Map<String, dynamic>)['text'] as String,
              MascotMood.values.firstWhere(
                (m) => m.name == l['mood'],
                orElse: () => MascotMood.happy,
              ),
              l['when'] as String? ?? 'any',
            ),
        ],
    });
  }

  static MascotMessages? _instance;

  /// Chưa nạp thì dùng kho rỗng: Cam im lặng chứ không làm app lỗi.
  static MascotMessages get instance => _instance ?? MascotMessages(const {});

  static Future<MascotMessages> load({AssetBundle? bundle}) async {
    final raw = await (bundle ?? rootBundle).loadString(kMascotMessagesAsset);
    return _instance = MascotMessages.fromJsonString(raw);
  }

  final Map<String, List<MascotLine>> _byContext;

  List<String> get contexts => _byContext.keys.toList();

  /// Chọn ngẫu nhiên một câu hợp [contextKey] và [info]; tránh lặp lại [avoid].
  /// Trả về null nếu không có câu nào phù hợp.
  MascotLine? pick(
    String contextKey,
    Random rng, {
    MascotContext info = const MascotContext(),
    String? avoid,
  }) {
    final all = _byContext[contextKey] ?? const [];
    var pool = [
      for (final l in all)
        if (info.allows(l.when)) l,
    ];
    if (pool.length > 1 && avoid != null) {
      pool = [
        for (final l in pool)
          if (info.fill(l.text) != avoid) l,
      ];
    }
    if (pool.isEmpty) return null;
    final line = pool[rng.nextInt(pool.length)];
    return MascotLine(info.fill(line.text), line.mood, line.when);
  }
}

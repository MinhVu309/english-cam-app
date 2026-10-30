import 'dart:math';

final Random _rng = Random.secure();

/// UUID v4 ngẫu nhiên (định danh góp ý/sự kiện do app sinh để gửi lại không bị trùng).
String newUuid([Random? random]) {
  final r = random ?? _rng;
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

import 'dart:math';

import '../../../data/vocab_word.dart';
import '../../../ml/classifier_service.dart';

/// Ngưỡng xác suất để coi là bé đã chụp đúng vật. Thấp hơn ngưỡng nhận diện
/// thường (0.7) vì sai ở đây chỉ làm bé vui nhầm, và bố mẹ vẫn có thể xác nhận tay.
const double kHuntThreshold = 0.5;

/// Đúng khi nhãn cao nhất chính là vật cần tìm và đủ chắc.
bool isHuntSuccess(ClassificationResult r, String targetLabel) =>
    r.best.label == targetLabel && r.best.probability >= kHuntThreshold;

/// Chọn vật cần tìm: chỉ lấy nhãn ổn định ([VocabWord.hunt]), tránh lặp [previous].
VocabWord pickHuntTarget(
  Iterable<VocabWord> words,
  Random rng, {
  String? previous,
}) {
  final pool = [
    for (final w in words)
      if (w.hunt) w,
  ];
  final choices = pool.length > 1
      ? [
          for (final w in pool)
            if (w.id != previous) w,
        ]
      : pool;
  return choices[rng.nextInt(choices.length)];
}

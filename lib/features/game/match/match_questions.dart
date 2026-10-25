import 'dart:math';

import '../../../data/vocab_word.dart';

/// Một câu hỏi "Nghe & chọn hình": đọc [target], bé chọn hình đúng trong [options].
class MatchQuestion {
  const MatchQuestion(this.target, this.options);

  final VocabWord target;
  final List<VocabWord> options;
}

const int kMatchQuestions = 8;
const int kMatchOptions = 4;

/// Chỉ dùng các từ có hình minh hoạ (ảnh hoặc emoji): không có hình thì bé không chọn được.
List<VocabWord> matchPool(Iterable<VocabWord> words) => [
  for (final w in words)
    if (w.hasPicture) w,
];

/// Tạo [count] câu hỏi, mỗi từ làm đáp án đúng tối đa một lần (nếu đủ từ),
/// các đáp án nhiễu khác nhau và khác đáp án đúng, vị trí đáp án được xáo trộn.
List<MatchQuestion> buildMatchQuestions(
  List<VocabWord> pool,
  Random rng, {
  int count = kMatchQuestions,
  int optionCount = kMatchOptions,
}) {
  assert(pool.length >= optionCount);
  final targets = [...pool]..shuffle(rng);
  final questions = <MatchQuestion>[];
  for (var i = 0; i < count; i++) {
    final target = targets[i % targets.length];
    final distractors = [
      for (final w in pool)
        if (w.id != target.id) w,
    ]..shuffle(rng);
    final options = [...distractors.take(optionCount - 1), target]
      ..shuffle(rng);
    questions.add(MatchQuestion(target, options));
  }
  return questions;
}

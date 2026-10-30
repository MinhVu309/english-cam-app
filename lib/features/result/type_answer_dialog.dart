import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/text_fold.dart';
import '../../data/vocab_repository.dart';
import '../../data/vocab_word.dart';

/// Từ người dùng gõ khi chọn "Khác…". [word] có giá trị nếu khớp một từ trong từ vựng (gõ đúng hoặc bấm gợi ý).
class TypedAnswer {
  const TypedAnswer(this.text, this.word);

  final String text;
  final VocabWord? word;
}

/// Tìm từ trong từ vựng khớp với chữ vừa gõ, không phân biệt hoa thường và dấu ("cai ban" ra "cái bàn").
List<VocabWord> suggestWords(String typed, {int limit = 6}) {
  final q = foldText(typed);
  if (q.isEmpty) return const [];
  final words = VocabRepository.instance.words;
  final starts = <VocabWord>[];
  final contains = <VocabWord>[];
  for (final w in words) {
    final en = foldText(w.en);
    final vi = foldText(w.vi);
    if (en.startsWith(q) || vi.startsWith(q)) {
      starts.add(w);
    } else if (en.contains(q) || vi.contains(q)) {
      contains.add(w);
    }
  }
  return [...starts, ...contains].take(limit).toList();
}

/// Từ đúng chính xác (so theo chữ không dấu) với [typed], nếu có.
VocabWord? exactWord(String typed) {
  final q = foldText(typed);
  if (q.isEmpty) return null;
  for (final w in VocabRepository.instance.words) {
    final same =
        foldText(w.en) == q ||
        foldText(w.vi) == q ||
        w.id == q.replaceAll(' ', '_');
    if (same) return w;
  }
  return null;
}

/// Hộp thoại "Đó là gì nhỉ?": gõ tên đúng của vật, có gợi ý từ từ vựng. Trả null nếu huỷ.
Future<TypedAnswer?> showTypeAnswerDialog(BuildContext context) =>
    showDialog<TypedAnswer>(
      context: context,
      builder: (_) => const _TypeAnswerDialog(),
    );

class _TypeAnswerDialog extends StatefulWidget {
  const _TypeAnswerDialog();

  @override
  State<_TypeAnswerDialog> createState() => _TypeAnswerDialogState();
}

class _TypeAnswerDialogState extends State<_TypeAnswerDialog> {
  final _controller = TextEditingController();
  VocabWord? _picked;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _text => _controller.text.trim();

  void _submit() {
    if (_text.isEmpty) return;
    // Bấm gợi ý rồi sửa chữ thì không còn là từ đó nữa.
    final picked = _picked != null && foldText(_text) == foldText(_picked!.en)
        ? _picked
        : null;
    Navigator.of(context).pop(TypedAnswer(_text, picked ?? exactWord(_text)));
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = suggestWords(_text);
    return AlertDialog(
      title: const Text('Đó là gì nhỉ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gõ tên đúng của vật này (tiếng Anh hoặc tiếng Việt). Bạn giúp Cam học thêm đó!',
              style: TextStyle(fontSize: 18, color: Palette.inkSoft),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('type-answer'),
              controller: _controller,
              autofocus: true,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                hintText: 'vd. cái bàn, table',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onChanged: (_) => setState(() => _picked = null),
              onSubmitted: (_) => _submit(),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final w in suggestions)
                    ActionChip(
                      key: Key('suggest-${w.id}'),
                      label: Text(
                        '${w.en} · ${w.vi}',
                        style: const TextStyle(fontSize: 18),
                      ),
                      onPressed: () {
                        _controller.text = w.en;
                        setState(() => _picked = w);
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          key: const Key('type-answer-send'),
          onPressed: _text.isEmpty ? null : _submit,
          child: const Text('Gửi'),
        ),
      ],
    );
  }
}

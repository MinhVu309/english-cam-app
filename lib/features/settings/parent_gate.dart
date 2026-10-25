import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/palette.dart';

/// Phép nhân hai số từ 6 đến 9: đủ khó để bé nhỏ không tự trả lời được.
class GateQuestion {
  const GateQuestion(this.a, this.b);

  final int a;
  final int b;

  int get answer => a * b;
  String get text => '$a × $b';
}

GateQuestion generateGateQuestion(Random rng) =>
    GateQuestion(6 + rng.nextInt(4), 6 + rng.nextInt(4)); // 6..9 × 6..9

/// Cổng phụ huynh: phải trả lời đúng phép nhân mới vào được Cài đặt.
/// Trả về true nếu đã qua cổng.
Future<bool> showParentGate(BuildContext context, {Random? random}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _ParentGateDialog(random: random ?? Random()),
  );
  return ok ?? false;
}

class _ParentGateDialog extends StatefulWidget {
  const _ParentGateDialog({required this.random});

  final Random random;

  @override
  State<_ParentGateDialog> createState() => _ParentGateDialogState();
}

class _ParentGateDialogState extends State<_ParentGateDialog> {
  final _input = TextEditingController();
  late GateQuestion _question = generateGateQuestion(widget.random);
  bool _wrong = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    if (int.tryParse(_input.text.trim()) == _question.answer) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _wrong = true;
      _question = generateGateQuestion(widget.random);
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dành cho bố mẹ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trả lời phép tính để vào Cài đặt:'),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '${_question.text} = ?',
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              hintText: 'Đáp án',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_wrong)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Chưa đúng, thử phép tính mới nhé.',
                style: TextStyle(fontSize: 18, color: Palette.orange),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Huỷ'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Mở')),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/palette.dart';

/// Bong bóng lời thoại có đuôi nhọn chỉ xuống/sang Cam.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    super.key,
    required this.text,
    this.tailOnRight = true,
    this.maxWidth = 250,
  });

  final String text;

  /// Đuôi bong bóng nằm bên phải (Cam ở góc phải) hay bên trái.
  final bool tailOnRight;
  final double maxWidth;

  static const double _tail = 12;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: CustomPaint(
        painter: _BubblePainter(tailOnRight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12 + _tail),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: Palette.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter(this.tailOnRight);

  final bool tailOnRight;

  @override
  void paint(Canvas canvas, Size size) {
    const tail = SpeechBubble._tail;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - tail),
      const Radius.circular(22),
    );
    final tx = tailOnRight ? size.width - 40 : 40.0;
    final path = Path()
      ..addRRect(body)
      ..moveTo(tx - 10, size.height - tail - 1)
      ..quadraticBezierTo(
        tx,
        size.height - tail + 2,
        tx + (tailOnRight ? 8 : -8),
        size.height,
      )
      ..quadraticBezierTo(
        tx + 8,
        size.height - tail + 4,
        tx + 12,
        size.height - tail - 1,
      )
      ..close();
    canvas.drawShadow(path, const Color(0xFF8B5A2B), 6, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Palette.peel.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.tailOnRight != tailOnRight;
}

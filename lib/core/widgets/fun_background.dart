import 'package:flutter/material.dart';

import '../palette.dart';

/// Nền kem có vài đốm màu nhạt trang trí, phủ sau mọi màn hình.
class FunBackground extends StatelessWidget {
  const FunBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFAF2), Palette.cream, Color(0xFFFFEBD2)],
        ),
      ),
      child: CustomPaint(painter: _BlobPainter(), child: child),
    );
  }
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter();

  @override
  void paint(Canvas canvas, Size size) {
    void blob(double fx, double fy, double r, Color c) {
      canvas.drawCircle(
        Offset(size.width * fx, size.height * fy),
        r,
        Paint()..color = c,
      );
    }

    blob(0.92, 0.06, 90, Palette.orange.withValues(alpha: 0.07));
    blob(0.02, 0.30, 64, Palette.teal.withValues(alpha: 0.07));
    blob(1.0, 0.58, 120, Palette.purple.withValues(alpha: 0.06));
    blob(0.06, 0.88, 84, Palette.star.withValues(alpha: 0.12));
    blob(0.80, 0.95, 54, Palette.orange.withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(_BlobPainter old) => false;
}

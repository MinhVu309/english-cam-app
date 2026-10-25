import 'package:flutter/material.dart';

/// Cạnh khung ngắm = tỉ lệ này × cạnh ngắn của vùng xem trước.
const double kFrameFraction = 0.72;

/// Khung ngắm vuông ở giữa, theo toạ độ chuẩn hoá (0–1) trên vùng [size].
Rect frameRectNormalized(Size size) {
  final side = size.shortestSide * kFrameFraction;
  final w = side / size.width;
  final h = side / size.height;
  return Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
}

/// Làm tối phần ngoài khung và vẽ 4 góc để bé đặt vật vào trong.
class FrameOverlay extends StatelessWidget {
  const FrameOverlay({super.key, required this.rect, this.color});

  /// Toạ độ chuẩn hoá (0–1).
  final Rect rect;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FramePainter(rect, color ?? const Color(0xFFFF8A3D)),
        size: Size.infinite,
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.rect, this.color);

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(24));

    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rr),
    );
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.45));

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final len = r.shortestSide * 0.18;
    const rad = 24.0;
    final p = Path();
    // Bốn góc bo tròn.
    void corner(Offset c, double dx, double dy) {
      p
        ..moveTo(c.dx, c.dy + dy * len)
        ..lineTo(c.dx, c.dy + dy * rad)
        ..arcToPoint(
          Offset(c.dx + dx * rad, c.dy),
          radius: const Radius.circular(rad),
          clockwise: dx * dy > 0,
        )
        ..lineTo(c.dx + dx * len, c.dy);
    }

    corner(r.topLeft, 1, 1);
    corner(r.topRight, -1, 1);
    corner(r.bottomRight, -1, -1);
    corner(r.bottomLeft, 1, -1);
    canvas.drawPath(p, stroke);
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.rect != rect || old.color != color;
}

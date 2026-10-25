import 'package:flutter/material.dart';

/// Vẽ khung vuông bo góc quanh vật (viền trắng + cam để nổi trên mọi nền).
class DetectionBoxPainter extends CustomPainter {
  DetectionBoxPainter(this.rect, {this.progress = 1});

  /// Toạ độ chuẩn hoá (0–1) trên vùng vẽ.
  final Rect rect;

  /// 0 → 1: khung thu từ to về đúng vị trí và hiện dần.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final grow = (1 - progress) * 0.08;
    final r = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    ).inflate(grow * size.shortestSide);
    final rr = RRect.fromRectAndRadius(
      r,
      Radius.circular(r.shortestSide * 0.08),
    );
    final alpha = progress.clamp(0.0, 1.0);

    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = Colors.white.withValues(alpha: 0.9 * alpha),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xFFFF8A3D).withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(DetectionBoxPainter old) =>
      old.rect != rect || old.progress != progress;
}

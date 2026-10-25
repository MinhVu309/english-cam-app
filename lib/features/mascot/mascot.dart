import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/palette.dart';

/// Biểu cảm của Cam.
enum MascotMood {
  /// Vui vẻ, mặc định.
  happy,

  /// Hào hứng: miệng cười to, có tia sáng (khi bé làm đúng / xong ván).
  cheer,

  /// Đang suy nghĩ (khi chưa chắc / không có kết quả).
  thinking,

  /// Ồ! ngạc nhiên nhẹ (khi sai hoặc có lỗi) — vẫn thân thiện, không buồn.
  oops,
}

/// "Cam": nhân vật tự vẽ của app, một quả cam tròn có cái lá trên đầu
/// (cam cũng là "orange" trong tiếng Anh). Không dựa trên nhân vật có bản quyền.
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    this.mood = MascotMood.happy,
    this.size = 120,
    this.animate = true,
  });

  final MascotMood mood;
  final double size;

  /// Nhún nhẹ và chớp mắt. Tự tắt khi hệ thống bật "giảm chuyển động".
  final bool animate;

  /// Tắt hoạt hình toàn cục (dùng trong test để `pumpAndSettle` kết thúc được).
  static bool animationsEnabled = true;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  bool _shouldAnimate(BuildContext context) =>
      widget.animate &&
      Mascot.animationsEnabled &&
      !MediaQuery.of(context).disableAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shouldAnimate(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: MascotPainter(widget.mood, _controller.value),
          ),
        ),
      ),
    );
  }
}

/// [t] chạy 0 → 1 mỗi 4 giây: dùng cho nhún và chớp mắt.
class MascotPainter extends CustomPainter {
  MascotPainter(this.mood, this.t);

  final MascotMood mood;
  final double t;

  static const _ink = Color(0xFF4A2A14);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final bob = math.sin(t * 2 * math.pi) * 0.012 * s;
    final c = Offset(s * 0.5, s * 0.58 + bob);
    final r = s * 0.36;

    // Bóng dưới đất.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx, s * 0.95),
        width: r * 1.5,
        height: s * 0.05,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.10),
    );

    // Thân.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.5),
          colors: [Color(0xFFFFB866), Palette.peel, Color(0xFFF57C00)],
          stops: [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx - r * 0.45, c.dy - r * 0.5),
        width: r * 0.35,
        height: r * 0.2,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );

    _leaf(canvas, c, r, s);
    _face(canvas, c, r, s);
    if (mood == MascotMood.cheer) _sparkles(canvas, c, r, s);
    if (mood == MascotMood.oops) _sweat(canvas, c, r, s);
  }

  void _leaf(Canvas canvas, Offset c, double r, double s) {
    final base = Offset(c.dx, c.dy - r + s * 0.01);
    final tip = Offset(base.dx, base.dy - s * 0.07);
    canvas.drawLine(
      base,
      tip,
      Paint()
        ..color = const Color(0xFF6D4C41)
        ..strokeWidth = s * 0.02
        ..strokeCap = StrokeCap.round,
    );
    final leaf = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(
        tip.dx + s * 0.13,
        tip.dy - s * 0.12,
        tip.dx + s * 0.2,
        tip.dy + s * 0.01,
      )
      ..quadraticBezierTo(tip.dx + s * 0.09, tip.dy + s * 0.05, tip.dx, tip.dy)
      ..close();
    canvas.drawPath(leaf, Paint()..color = Palette.leaf);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..quadraticBezierTo(
          tip.dx + s * 0.09,
          tip.dy - s * 0.04,
          tip.dx + s * 0.17,
          tip.dy,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.008
        ..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  void _face(Canvas canvas, Offset c, double r, double s) {
    final eyeY = c.dy - r * 0.1;
    final dx = r * 0.36;
    final big = mood == MascotMood.oops || mood == MascotMood.cheer;
    final eyeR = s * (big ? 0.062 : 0.055);

    // Chớp mắt: đóng nhanh quanh t = 0.92 (trừ khi đang hào hứng).
    final blinkPhase = ((t - 0.92).abs() / 0.025).clamp(0.0, 1.0);
    final blink = mood == MascotMood.cheer ? 1.0 : blinkPhase;

    for (final side in [-1.0, 1.0]) {
      final ex = c.dx + side * dx;
      if (mood == MascotMood.cheer) {
        // Mắt cười ^ ^
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(ex, eyeY + eyeR * 0.3),
            width: eyeR * 2.2,
            height: eyeR * 2.0,
          ),
          math.pi * 1.1,
          math.pi * 0.8,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.022
            ..strokeCap = StrokeCap.round
            ..color = _ink,
        );
        continue;
      }
      final eye = Rect.fromCenter(
        center: Offset(ex, eyeY),
        width: eyeR * 2,
        height: eyeR * 2.2 * blink.clamp(0.1, 1.0),
      );
      canvas.drawOval(eye, Paint()..color = Colors.white);
      // Đồng tử: nhìn lên-phải khi suy nghĩ.
      final look = mood == MascotMood.thinking
          ? Offset(eyeR * 0.3, -eyeR * 0.3)
          : Offset.zero;
      canvas.save();
      canvas.clipPath(Path()..addOval(eye));
      canvas.drawCircle(
        Offset(ex, eyeY) + look,
        eyeR * 0.62,
        Paint()..color = _ink,
      );
      canvas.drawCircle(
        Offset(ex + eyeR * 0.2, eyeY - eyeR * 0.25) + look,
        eyeR * 0.2,
        Paint()..color = Colors.white,
      );
      canvas.restore();
    }

    // Lông mày nhướn khi suy nghĩ.
    if (mood == MascotMood.thinking) {
      canvas.drawLine(
        Offset(c.dx + dx - eyeR, eyeY - eyeR * 1.7),
        Offset(c.dx + dx + eyeR, eyeY - eyeR * 2.1),
        Paint()
          ..color = _ink
          ..strokeWidth = s * 0.017
          ..strokeCap = StrokeCap.round,
      );
    }

    // Má hồng.
    for (final side in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.dx + side * r * 0.62, c.dy + r * 0.2),
          width: s * 0.085,
          height: s * 0.05,
        ),
        Paint()..color = const Color(0xFFFF6F61).withValues(alpha: 0.45),
      );
    }

    _mouth(canvas, Offset(c.dx, c.dy + r * 0.28), s);
  }

  void _mouth(Canvas canvas, Offset m, double s) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.02
      ..strokeCap = StrokeCap.round
      ..color = _ink;
    switch (mood) {
      case MascotMood.happy:
        canvas.drawArc(
          Rect.fromCenter(center: m, width: s * 0.17, height: s * 0.11),
          math.pi * 0.12,
          math.pi * 0.76,
          false,
          line,
        );
      case MascotMood.cheer:
        final rect = Rect.fromCenter(
          center: m,
          width: s * 0.22,
          height: s * 0.2,
        );
        final mouth = Path()
          ..addArc(rect, 0, math.pi)
          ..close();
        canvas.drawPath(mouth, Paint()..color = _ink);
        canvas.save();
        canvas.clipPath(mouth);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(m.dx, m.dy + s * 0.095),
            width: s * 0.13,
            height: s * 0.09,
          ),
          Paint()..color = const Color(0xFFFF7A8A),
        );
        canvas.restore();
      case MascotMood.thinking:
        canvas.drawCircle(
          Offset(m.dx + s * 0.02, m.dy + s * 0.01),
          s * 0.022,
          line,
        );
      case MascotMood.oops:
        canvas.drawOval(
          Rect.fromCenter(center: m, width: s * 0.06, height: s * 0.075),
          Paint()..color = _ink,
        );
    }
  }

  void _sparkles(Canvas canvas, Offset c, double r, double s) {
    final p = Paint()..color = Palette.star;
    void star(Offset o, double size) {
      final path = Path();
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4 - math.pi / 2;
        final rad = i.isEven ? size : size * 0.38;
        final pt = o + Offset(math.cos(a) * rad, math.sin(a) * rad);
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path..close(), p);
    }

    final pulse = 0.85 + 0.15 * math.sin(t * 4 * math.pi);
    star(Offset(c.dx - r * 1.15, c.dy - r * 0.5), s * 0.07 * pulse);
    star(Offset(c.dx + r * 1.1, c.dy - r * 0.15), s * 0.055 * pulse);
    star(Offset(c.dx - r * 0.95, c.dy + r * 0.55), s * 0.04 * pulse);
  }

  void _sweat(Canvas canvas, Offset c, double r, double s) {
    final o = Offset(c.dx + r * 0.95, c.dy - r * 0.5);
    final drop = Path()
      ..moveTo(o.dx, o.dy - s * 0.05)
      ..quadraticBezierTo(o.dx + s * 0.04, o.dy, o.dx, o.dy + s * 0.03)
      ..quadraticBezierTo(o.dx - s * 0.04, o.dy, o.dx, o.dy - s * 0.05);
    canvas.drawPath(drop, Paint()..color = const Color(0xFF64B5F6));
  }

  @override
  bool shouldRepaint(MascotPainter old) => old.mood != mood || old.t != t;
}

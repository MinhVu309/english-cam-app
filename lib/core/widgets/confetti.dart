import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/mascot/mascot.dart';
import '../palette.dart';

/// Pháo giấy rơi một lần khi bé thắng. Tự bỏ qua nếu hệ thống giảm chuyển động.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.count = 46, this.seed = 1});

  final int count;
  final int seed;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final List<_Piece> _pieces = _makePieces();

  static const _colors = [
    Palette.orange,
    Palette.teal,
    Palette.purple,
    Palette.star,
    Color(0xFFEF5DA8),
    Palette.leaf,
  ];

  List<_Piece> _makePieces() {
    final rng = math.Random(widget.seed);
    return [
      for (var i = 0; i < widget.count; i++)
        _Piece(
          x: rng.nextDouble(),
          delay: rng.nextDouble() * 0.35,
          speed: 0.6 + rng.nextDouble() * 0.5,
          sway: (rng.nextDouble() - 0.5) * 0.25,
          size: 8 + rng.nextDouble() * 8,
          spin: rng.nextDouble() * 6,
          color: _colors[rng.nextInt(_colors.length)],
          round: rng.nextBool(),
        ),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final off =
        !Mascot.animationsEnabled || MediaQuery.of(context).disableAnimations;
    if (!off && !_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(_pieces, _controller.value),
          ),
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.x,
    required this.delay,
    required this.speed,
    required this.sway,
    required this.size,
    required this.spin,
    required this.color,
    required this.round,
  });

  final double x, delay, speed, sway, size, spin;
  final Color color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final y = -20 + (size.height + 40) * local * p.speed;
      final x = size.width * (p.x + p.sway * math.sin(local * 9));
      final alpha = local > 0.8 ? (1 - local) / 0.2 : 1.0;
      final paint = Paint()..color = p.color.withValues(alpha: alpha);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin + local * 8);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.55,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

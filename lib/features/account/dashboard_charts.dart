import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/palette.dart';

/// Hình học các cột của biểu đồ cột trong khung [plot]: cột cao theo tỉ lệ với giá trị lớn nhất.
/// Giá trị 0 vẫn có một vạch mảnh để thấy ngày đó "không có gì" chứ không phải thiếu dữ liệu.
/// Tách riêng khỏi phần vẽ để test được.
List<Rect> barRects(
  List<double> values,
  Size plot, {
  double gap = 6,
  double stub = 2,
  double minVisible = 4,
}) {
  if (values.isEmpty) return const [];
  final n = values.length;
  final max = values.fold<double>(0, math.max);
  // Nhiều cột thì khoảng cách co lại (tối đa 25% bề rộng) để các cột luôn nằm gọn trong khung.
  final g = n <= 1 ? 0.0 : math.min(gap, plot.width * 0.25 / (n - 1));
  final width = (plot.width - g * (n - 1)) / n;
  return [
    for (var i = 0; i < n; i++)
      () {
        final h = values[i] <= 0 || max <= 0
            ? stub
            : math.max(minVisible, values[i] / max * plot.height);
        return Rect.fromLTWH(i * (width + g), plot.height - h, width, h);
      }(),
  ];
}

/// Cột nào được ghi nhãn: tối đa 8 cột thì ghi hết; nhiều hơn thì ghi thưa, neo từ cột cuối (hôm nay) lùi dần.
List<int> labelIndexes(int n) {
  if (n <= 0) return const [];
  final step = n <= 8 ? 1 : (n / 6).ceil();
  return [for (var i = n - 1; i >= 0; i -= step) i].reversed.toList();
}

/// Biểu đồ cột đơn giản, vẽ bằng CustomPaint (không cần thêm package biểu đồ).
/// [labels] cùng độ dài [values]; khi nhiều cột chỉ hiện nhãn thưa ra (và luôn hiện nhãn cột cuối).
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    required this.semanticLabel,
    this.height = 190,
  }) : assert(values.length == labels.length);

  final List<double> values;
  final List<String> labels;
  final Color color;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _BarPainter(values, labels, color)),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.values, this.labels, this.color);

  final List<double> values;
  final List<String> labels;
  final Color color;

  static const double _labelBand = 30;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Size(size.width, size.height - _labelBand);
    final rects = barRects(values, plot);
    final paint = Paint()..color = color;
    final faint = Paint()..color = color.withValues(alpha: 0.25);
    for (var i = 0; i < rects.length; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rects[i], const Radius.circular(6)),
        values[i] > 0 ? paint : faint,
      );
    }
    canvas.drawLine(
      Offset(0, plot.height + 1),
      Offset(size.width, plot.height + 1),
      Paint()
        ..color = Palette.inkSoft.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );

    for (final i in labelIndexes(labels.length)) {
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(
            fontSize: 18,
            color: Palette.inkSoft,
            fontFamily: 'Nunito',
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final x = (rects[i].center.dx - tp.width / 2)
          .clamp(0.0, math.max(0.0, size.width - tp.width))
          .toDouble();
      tp.paint(canvas, Offset(x, plot.height + 6));
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values || old.labels != labels || old.color != color;
}

/// Vòng tiến độ (ví dụ 12/60 từ đã học) với nội dung ở giữa.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.child,
    this.size = 96,
    this.color = Palette.teal,
    this.semanticLabel,
  });

  /// 0..1
  final double value;
  final Widget child;
  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(value.clamp(0.0, 1.0), color),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color);

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.18);
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);
    if (value <= 0) return;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      track
        ..color = color
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}

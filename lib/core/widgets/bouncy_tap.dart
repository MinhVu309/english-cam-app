import 'package:flutter/material.dart';

/// Thẻ bấm được có hiệu ứng nảy nhẹ khi nhấn, bóng đổ và gợn sóng; giữ nguyên
/// ngữ nghĩa nút cho trình đọc màn hình.
class BouncyTap extends StatefulWidget {
  const BouncyTap({
    super.key,
    required this.child,
    required this.onTap,
    this.color = Colors.white,
    this.gradient,
    this.borderRadius = 28,
    this.shadowColor,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final Gradient? gradient;
  final double borderRadius;

  /// Màu bóng đổ; mặc định là nâu nhạt.
  final Color? shadowColor;
  final String? semanticLabel;

  @override
  State<BouncyTap> createState() => _BouncyTapState();
}

class _BouncyTapState extends State<BouncyTap> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final shadow = widget.shadowColor ?? const Color(0xFF8B5A2B);
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.semanticLabel,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.gradient == null ? widget.color : null,
            gradient: widget.gradient,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: shadow.withValues(alpha: _down ? 0.10 : 0.22),
                blurRadius: _down ? 6 : 14,
                offset: Offset(0, _down ? 2 : 6),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onHighlightChanged: (v) => setState(() => _down = v),
              onTap: widget.onTap,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

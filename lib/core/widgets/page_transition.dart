import 'package:flutter/material.dart';

/// Chuyển màn: mờ dần + trượt nhẹ từ dưới lên + phóng to rất nhẹ.
class PopPageTransitionsBuilder extends PageTransitionsBuilder {
  const PopPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/jim_tokens.dart';

class JimSurface extends StatelessWidget {
  const JimSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(JimSpacing.lg),
    this.backgroundColor,
    this.borderColor,
    this.radius = JimRadius.md,
    this.inset = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double radius;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? JimColors.plaque,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? JimColors.insetLine),
        boxShadow: inset ? const [] : JimElevation.card,
      ),
      child: child,
    );
  }
}

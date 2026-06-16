import 'package:flutter/material.dart';

import '../../core/theme/jim_tokens.dart';

enum JimSurfaceTone {
  plain,
  soft,
  accent,
  warning,
}

class JimSurface extends StatelessWidget {
  const JimSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(JimSpacing.lg),
    this.backgroundColor,
    this.borderColor,
    this.radius = JimRadius.card,
    this.inset = false,
    this.tone = JimSurfaceTone.plain,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double radius;
  final bool inset;
  final JimSurfaceTone tone;

  @override
  Widget build(BuildContext context) {
    final resolvedBackground = backgroundColor ??
        switch (tone) {
          JimSurfaceTone.plain => JimColors.plaque,
          JimSurfaceTone.soft => JimColors.galleryWhite,
          JimSurfaceTone.accent => JimColors.accentSoft.withValues(alpha: .42),
          JimSurfaceTone.warning => JimColors.terracotta.withValues(alpha: .08),
        };
    final resolvedBorder = borderColor ??
        switch (tone) {
          JimSurfaceTone.warning => JimColors.terracotta.withValues(alpha: .22),
          JimSurfaceTone.accent => JimColors.accentLine,
          _ => JimColors.insetLine,
        };

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: resolvedBorder),
        boxShadow: inset ? const [] : JimElevation.soft,
      ),
      child: child,
    );
  }
}

class JimInteractiveSurface extends StatelessWidget {
  const JimInteractiveSurface({
    super.key,
    required this.child,
    required this.onTap,
    this.padding = const EdgeInsets.all(JimSpacing.lg),
    this.tone = JimSurfaceTone.plain,
    this.radius = JimRadius.card,
  });

  final Widget child;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final JimSurfaceTone tone;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: JimSurface(
          padding: padding,
          radius: radius,
          tone: tone,
          child: child,
        ),
      ),
    );
  }
}

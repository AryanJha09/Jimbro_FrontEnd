import 'package:flutter/material.dart';

import '../../core/theme/jim_tokens.dart';
import 'jim_button.dart';
import 'jim_surface.dart';
import 'section_header.dart';

class JimPageScaffold extends StatelessWidget {
  const JimPageScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.children,
    this.subtitle,
    this.headerTrailing,
    this.scrollKey,
    this.bottomPadding = 120,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget? headerTrailing;
  final List<Widget> children;
  final Key? scrollKey;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  JimColors.shell,
                  JimColors.galleryWhite,
                  JimColors.eggshell,
                ],
              ),
            ),
          ),
        ),
        const Positioned.fill(child: JimLightTexture()),
        SafeArea(
          child: ListView(
            key: scrollKey,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              JimSpacing.ml,
              JimSpacing.lg,
              JimSpacing.ml,
              bottomPadding,
            ),
            children: [
              SectionHeader(
                eyebrow: eyebrow,
                title: title,
                subtitle: subtitle,
                trailing: headerTrailing,
              ),
              const SizedBox(height: JimSpacing.ml),
              ...children,
            ],
          ),
        ),
      ],
    );
  }
}

class JimCtaPanel extends StatelessWidget {
  const JimCtaPanel({
    super.key,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimaryPressed,
    this.icon = Icons.auto_awesome_rounded,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimaryPressed;
  final IconData icon;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return JimSurface(
      tone: JimSurfaceTone.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: JimColors.accentStrong),
          const SizedBox(height: JimSpacing.sm),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: JimSpacing.xs),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: JimColors.inkSoft,
              height: 1.45,
            ),
          ),
          const SizedBox(height: JimSpacing.md),
          JimPrimaryButton(
            label: primaryLabel,
            onPressed: onPrimaryPressed,
            icon: Icons.arrow_forward_rounded,
            expand: true,
          ),
          if (secondaryLabel != null && onSecondaryPressed != null) ...[
            const SizedBox(height: JimSpacing.xs),
            JimSecondaryButton(
              label: secondaryLabel!,
              onPressed: onSecondaryPressed!,
              expand: true,
            ),
          ],
        ],
      ),
    );
  }
}

class JimStateCard extends StatelessWidget {
  const JimStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.tone = JimSurfaceTone.soft,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final JimSurfaceTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return JimSurface(
      tone: tone,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tone == JimSurfaceTone.warning
                  ? JimColors.terracotta.withValues(alpha: .12)
                  : JimColors.accentSoft,
              shape: BoxShape.circle,
              border: Border.all(
                color: tone == JimSurfaceTone.warning
                    ? JimColors.terracotta.withValues(alpha: .24)
                    : JimColors.accentLine,
              ),
            ),
            child: Icon(
              icon,
              color: tone == JimSurfaceTone.warning
                  ? JimColors.terracotta
                  : JimColors.accentStrong,
              size: 28,
            ),
          ),
          const SizedBox(height: JimSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: JimSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: JimColors.inkSoft,
              height: 1.45,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: JimSpacing.md),
            JimPrimaryButton(
              label: actionLabel!,
              onPressed: onAction!,
              expand: true,
            ),
          ],
        ],
      ),
    );
  }
}

class JimEmptyState extends StatelessWidget {
  const JimEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.add_circle_outline_rounded,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return JimStateCard(
      icon: icon,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class JimLoadingState extends StatelessWidget {
  const JimLoadingState({
    super.key,
    this.message = 'Loading...',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return JimSurface(
      tone: JimSurfaceTone.soft,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.hasBoundedHeight && constraints.maxHeight < 190;
          final indicatorSize = compact ? 32.0 : 52.0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: indicatorSize,
                height: indicatorSize,
                padding: EdgeInsets.all(compact ? 8 : 13),
                decoration: const BoxDecoration(
                  color: JimColors.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(strokeWidth: 2.6),
              ),
              SizedBox(height: compact ? JimSpacing.xxs : JimSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: JimColors.inkSoft,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class JimErrorState extends StatelessWidget {
  const JimErrorState({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return JimStateCard(
      icon: Icons.cloud_off_rounded,
      title: title,
      message: message,
      actionLabel: onRetry == null ? null : 'Retry',
      onAction: onRetry,
      tone: JimSurfaceTone.warning,
    );
  }
}

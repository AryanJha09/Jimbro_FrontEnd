import 'package:flutter/material.dart';

import '../../core/theme/jim_tokens.dart';
import 'jim_button.dart';
import 'jim_surface.dart';

class BackendLoadingView extends StatelessWidget {
  const BackendLoadingView({
    super.key,
    this.message = 'Loading your JimBro state...',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [JimColors.shell, JimColors.galleryWhite, JimColors.eggshell],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: JimSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: JimSpacing.md),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BackendErrorView extends StatelessWidget {
  const BackendErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [JimColors.shell, JimColors.galleryWhite, JimColors.eggshell],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(JimSpacing.lg),
            child: JimSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: JimColors.terracotta,
                    size: 42,
                  ),
                  const SizedBox(height: JimSpacing.md),
                  Text(
                    'Could not load app state',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: JimSpacing.sm),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: JimColors.inkSoft,
                        ),
                  ),
                  const SizedBox(height: JimSpacing.md),
                  JimPrimaryButton(label: 'Retry', onPressed: onRetry),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/jim_tokens.dart';
import 'jim_page_scaffold.dart';

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
          child: Padding(
            padding: const EdgeInsets.all(JimSpacing.lg),
            child: JimLoadingState(
              message: message,
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
            child: JimErrorState(
              title: 'Could not load app state',
              message: '$error',
              onRetry: onRetry,
            ),
          ),
        ),
      ),
    );
  }
}

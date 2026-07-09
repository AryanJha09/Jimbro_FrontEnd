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
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(JimSpacing.lg),
              child: JimLoadingState(message: message),
            ),
          ),
        ),
      ],
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
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(JimSpacing.lg),
              child: JimErrorState(
                title: 'Could not load app state',
                message: _friendlyBackendMessage(error),
                onRetry: onRetry,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _friendlyBackendMessage(Object error) {
  final type = error.runtimeType.toString().toLowerCase();
  if (type.contains('auth') || type.contains('session')) {
    return 'Your session needs attention. Please sign in again, then retry.';
  }
  if (type.contains('timeout')) {
    return 'The service took too long to respond. Your saved data is safe.';
  }
  return 'JimBro could not reach the service right now. Your saved data is safe; please retry.';
}

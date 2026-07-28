import 'package:flutter/material.dart';

import '../../core/errors/app_error.dart';
import '../../core/theme/jim_tokens.dart';
import '../models/app_models.dart';
import 'jim_button.dart';
import 'jim_companion.dart';
import 'jim_page_scaffold.dart';
import 'jim_surface.dart';

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

class AuthenticatedRecoveryView extends StatefulWidget {
  const AuthenticatedRecoveryView({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onSignOut,
    this.fatal = false,
  });

  final Object error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSignOut;
  final bool fatal;

  @override
  State<AuthenticatedRecoveryView> createState() =>
      _AuthenticatedRecoveryViewState();
}

class _AuthenticatedRecoveryViewState extends State<AuthenticatedRecoveryView> {
  bool _retrying = false;
  bool _signingOut = false;
  String? _actionError;

  Future<void> _retry() async {
    if (_retrying || _signingOut) {
      return;
    }
    setState(() {
      _retrying = true;
      _actionError = null;
    });
    try {
      await widget.onRetry();
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = _friendlyBackendMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (_retrying || _signingOut) {
      return;
    }
    setState(() {
      _signingOut = true;
      _actionError = null;
    });
    try {
      await widget.onSignOut();
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = _friendlyBackendMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mapped = mapAppError(
      widget.error,
      fallbackMessage: 'Profile data could not be loaded.',
      method: 'GET',
      route: '/supabase/profile',
    );
    final reference = mapped.diagnostics.correlationId;
    final busy = _retrying || _signingOut;

    return DecoratedBox(
      key: const ValueKey('authenticated-recovery-view'),
      decoration: const BoxDecoration(
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
      child: Stack(
        children: [
          const Positioned.fill(child: JimLightTexture()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                JimSpacing.lg,
                JimSpacing.xl,
                JimSpacing.lg,
                JimSpacing.xl,
              ),
              children: [
                const Center(
                  child: JimCompanionAvatar(
                    stage: JimCompanionStage.softBase,
                    size: 122,
                    showLabel: true,
                  ),
                ),
                const SizedBox(height: JimSpacing.lg),
                Text(
                  widget.fatal
                      ? 'JimBro couldn’t load your profile'
                      : 'We couldn’t connect to JimBro',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: JimSpacing.sm),
                Text(
                  widget.fatal
                      ? 'You’re still signed in, but the profile response could not be used. Retry, or sign out to use another account.'
                      : 'You’re still signed in. Your profile data could not be loaded because the service is temporarily unavailable.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: JimColors.inkSoft,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: JimSpacing.lg),
                JimSurface(
                  tone: JimSurfaceTone.warning,
                  child: Column(
                    children: [
                      Icon(
                        widget.fatal
                            ? Icons.warning_amber_rounded
                            : Icons.cloud_off_rounded,
                        color: JimColors.terracotta,
                        size: 32,
                      ),
                      const SizedBox(height: JimSpacing.sm),
                      Text(
                        _actionError ?? mapped.userMessage,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: JimColors.inkSoft,
                        ),
                      ),
                      if (reference != null && reference.trim().isNotEmpty) ...[
                        const SizedBox(height: JimSpacing.xs),
                        Text(
                          'Reference: ${reference.trim()}',
                          key: const ValueKey('recovery-reference-code'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: JimColors.inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: JimSpacing.lg),
                JimPrimaryButton(
                  key: const ValueKey('recovery-retry-button'),
                  label: _retrying ? 'Retrying…' : 'Retry',
                  icon: Icons.refresh_rounded,
                  expand: true,
                  onPressed: busy ? () {} : _retry,
                ),
                const SizedBox(height: JimSpacing.sm),
                JimTextButton(
                  key: const ValueKey('recovery-sign-out-button'),
                  label: _signingOut ? 'Signing out…' : 'Sign out',
                  icon: Icons.logout_rounded,
                  onPressed: busy ? () {} : _signOut,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _friendlyBackendMessage(Object error) {
  return presentAppError(
    error,
    fallbackMessage:
        'JimBro could not reach the service right now. Your saved data is safe; please retry.',
  );
}

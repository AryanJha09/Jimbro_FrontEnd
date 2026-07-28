import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/components/jim_companion.dart';
import '../../shared/components/backend_state_view.dart';
import '../../shared/models/app_models.dart';
import '../../features/auth/presentation/auth_page.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../theme/jim_tokens.dart';
import 'app_state.dart';

class AppFlow extends ConsumerStatefulWidget {
  const AppFlow({super.key});

  @override
  ConsumerState<AppFlow> createState() => _AppFlowState();
}

class _AppFlowState extends ConsumerState<AppFlow>
    with TickerProviderStateMixin {
  Timer? _bootTimer;
  late final AnimationController _plateSpinController;
  late final AnimationController _settleController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  double _settleStart = 0;
  double _settleTarget = 0;
  bool _bootResolved = false;
  bool _showApp = false;
  AppBootstrapStatus? _lastLoggedRouteStatus;
  String? _lastLoggedRoute;

  @override
  void initState() {
    super.initState();
    _plateSpinController = AnimationController(
      vsync: this,
      duration: JimMotion.loaderSpin,
    )..repeat();
    _settleController = AnimationController(
      vsync: this,
      duration: JimMotion.loaderSettle,
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: JimMotion.screenFade,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOutCubic,
    );

    _resolveBoot();
  }

  void _resolveBoot() {
    _bootTimer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted) {
        return;
      }
      _bootResolved = true;
      unawaited(_settlePlateAndReveal());
    });
  }

  Future<void> _settlePlateAndReveal() async {
    _settleStart = _plateSpinController.value * 2 * math.pi;
    _plateSpinController.stop();
    _settleTarget = (_settleStart / (2 * math.pi)).ceilToDouble() * 2 * math.pi;
    await _settleController.forward(from: 0);
    if (!mounted) {
      return;
    }
    setState(() {
      _showApp = true;
    });
    await _fadeController.forward(from: 0);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _bootTimer?.cancel();
    _plateSpinController.dispose();
    _settleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appDraftProvider);
    final bootstrap = ref.watch(appBootstrapProvider);
    final forceShowOnboarding =
        kDebugMode && ref.watch(forceShowOnboardingProvider);
    final destination = switch (bootstrap.status) {
      AppBootstrapStatus.authenticating =>
        const BackendLoadingView(message: 'Restoring your session...'),
      AppBootstrapStatus.authenticatedProvisioning =>
        const BackendLoadingView(message: 'Preparing your profile...'),
      AppBootstrapStatus.onboardingRequired => const OnboardingPage(),
      AppBootstrapStatus.ready when forceShowOnboarding =>
        const OnboardingPage(),
      AppBootstrapStatus.ready => const HomeShell(),
      AppBootstrapStatus.recoverableError when bootstrap.session != null =>
        AuthenticatedRecoveryView(
          error: bootstrap.error ?? StateError('Profile service unavailable.'),
          onRetry: () =>
              ref.read(appDraftProvider.notifier).retryAccountProvisioning(),
          onSignOut: () => ref.read(appDraftProvider.notifier).signOut(),
        ),
      AppBootstrapStatus.fatalError when bootstrap.session != null =>
        AuthenticatedRecoveryView(
          error: bootstrap.error ?? StateError('Profile response is invalid.'),
          fatal: true,
          onRetry: () =>
              ref.read(appDraftProvider.notifier).retryAccountProvisioning(),
          onSignOut: () => ref.read(appDraftProvider.notifier).signOut(),
        ),
      AppBootstrapStatus.fatalError => BackendErrorView(
          error: bootstrap.error ?? StateError('App startup failed.'),
          onRetry: () => ref.invalidate(appDraftProvider),
        ),
      AppBootstrapStatus.unauthenticated ||
      AppBootstrapStatus.expired ||
      AppBootstrapStatus.recoverableError =>
        const AuthPage(),
    };
    if (kDebugMode) {
      final route = switch (bootstrap.status) {
        AppBootstrapStatus.onboardingRequired => 'onboarding',
        AppBootstrapStatus.ready when forceShowOnboarding => 'onboarding',
        AppBootstrapStatus.ready => 'home',
        AppBootstrapStatus.unauthenticated ||
        AppBootstrapStatus.expired =>
          'auth',
        AppBootstrapStatus.recoverableError =>
          bootstrap.session == null ? 'auth' : 'authenticated-recovery',
        AppBootstrapStatus.authenticating ||
        AppBootstrapStatus.authenticatedProvisioning =>
          'loading',
        AppBootstrapStatus.fatalError =>
          bootstrap.session == null ? 'error' : 'authenticated-profile-error',
      };
      if (_lastLoggedRouteStatus != bootstrap.status ||
          _lastLoggedRoute != route) {
        _lastLoggedRouteStatus = bootstrap.status;
        _lastLoggedRoute = route;
        debugPrint(
          'AppFlow route decision: status=${bootstrap.status.name} '
          'route=$route.',
        );
      }
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_showApp)
            FadeTransition(
              opacity: _fadeAnimation,
              child: destination,
            ),
          if (!_showApp || _fadeAnimation.value < 1)
            AnimatedBuilder(
              animation: Listenable.merge([
                _plateSpinController,
                _settleController,
                _fadeController,
              ]),
              builder: (context, child) {
                final activeAngle = _bootResolved
                    ? Tween<double>(
                        begin: _settleStart,
                        end: _settleTarget,
                      ).transform(
                        Curves.easeOutCubic.transform(_settleController.value),
                      )
                    : _plateSpinController.value * 2 * math.pi;

                return IgnorePointer(
                  ignoring: true,
                  child: Opacity(
                    opacity: 1 - _fadeAnimation.value,
                    child: SplashStage(angle: activeAngle),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class SplashStage extends StatelessWidget {
  const SplashStage({
    super.key,
    required this.angle,
  });

  final double angle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
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
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: JimLightTexture()),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                Hero(
                  tag: 'jim-companion',
                  child: Transform.rotate(
                    angle: angle,
                    child: const JimCompanionAvatar(
                      stage: JimCompanionStage.softBase,
                      size: 164,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'JIMBRO',
                  style: theme.textTheme.displaySmall?.copyWith(
                    letterSpacing: 4.8,
                    color: JimColors.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  'Warming up your companion',
                  style: theme.textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.2,
                    color: JimColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

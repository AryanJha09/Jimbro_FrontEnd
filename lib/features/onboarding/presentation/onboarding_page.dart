import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/repositories/app_repositories.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/jim_companion.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/models/app_models.dart';
import '../../../shared/models/onboarding_models.dart';
import '../application/onboarding_controller.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class OnboardingPreviewPage extends StatefulWidget {
  const OnboardingPreviewPage({super.key});

  static const routeName = '/debug/onboarding-preview';

  @override
  State<OnboardingPreviewPage> createState() => _OnboardingPreviewPageState();
}

class _OnboardingPreviewPageState extends State<OnboardingPreviewPage> {
  late final _InMemoryOnboardingPersistenceStore _store;

  @override
  void initState() {
    super.initState();
    _store = _InMemoryOnboardingPersistenceStore();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }
    return ProviderScope(
      overrides: [
        onboardingPersistenceStoreProvider.overrideWith((ref) async => _store),
      ],
      child: const _OnboardingPreviewFlow(),
    );
  }
}

class _OnboardingPreviewFlow extends ConsumerStatefulWidget {
  const _OnboardingPreviewFlow();

  @override
  ConsumerState<_OnboardingPreviewFlow> createState() =>
      _OnboardingPreviewFlowState();
}

class _OnboardingPreviewFlowState
    extends ConsumerState<_OnboardingPreviewFlow> {
  bool _isFinishing = false;

  @override
  Widget build(BuildContext context) {
    final onboardingAsync = ref.watch(onboardingControllerProvider);
    return onboardingAsync.when(
      loading: () => const BackendLoadingView(
        message: 'Starting onboarding preview...',
      ),
      error: (error, stackTrace) => BackendErrorView(
        error: error,
        onRetry: () => ref.invalidate(onboardingControllerProvider),
      ),
      data: (onboarding) => Scaffold(
        body: _OnboardingScaffold(
          onboarding: onboarding,
          isFinishing: _isFinishing,
          onBack: _handleBack,
          onContinue: () => _handleContinue(onboarding),
          onFinish: () => _handleFinish(onboarding),
        ),
      ),
    );
  }

  Future<void> _handleBack() async {
    final onboarding = ref.read(onboardingControllerProvider).valueOrNull;
    final step = OnboardingStepId.fromWireValue(
      onboarding?.currentStepId ?? OnboardingStepId.welcome.wireValue,
    );
    if (step == OnboardingStepId.welcome) {
      await Navigator.of(context).maybePop();
      return;
    }
    await ref.read(onboardingControllerProvider.notifier).goBack();
  }

  Future<void> _handleContinue(OnboardingStateModel onboarding) async {
    await _continueOnboarding(ref, onboarding);
  }

  Future<void> _handleFinish(OnboardingStateModel onboarding) async {
    final controller = ref.read(onboardingControllerProvider.notifier);
    final validation = controller.validateForCompletion(onboarding);
    if (!validation.isValid) {
      await controller.goToStep(
        OnboardingStepId.fromWireValue(onboarding.currentStepId),
      );
      return;
    }

    setState(() => _isFinishing = true);
    await controller.complete();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).maybePop();
  }
}

class _InMemoryOnboardingPersistenceStore
    implements OnboardingPersistenceStore {
  final _records = <String, OnboardingPersistenceModel>{};

  @override
  Future<void> clear(String userId) async {
    _records.remove(userId);
  }

  @override
  Future<OnboardingPersistenceModel?> load(String userId) async {
    return _records[userId];
  }

  @override
  Future<void> save(OnboardingPersistenceModel model) async {
    _records[model.userId] = model;
  }
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  bool _isFinishing = false;

  @override
  Widget build(BuildContext context) {
    final draftAsync = ref.watch(appDraftProvider);
    final onboardingAsync = ref.watch(onboardingControllerProvider);

    if (draftAsync.isLoading && draftAsync.valueOrNull == null) {
      return const BackendLoadingView(
          message: 'Preparing your coaching plan...');
    }
    if (draftAsync.hasError && draftAsync.valueOrNull == null) {
      return BackendErrorView(
        error: draftAsync.error!,
        onRetry: () => ref.invalidate(appDraftProvider),
      );
    }

    return onboardingAsync.when(
      loading: () => const BackendLoadingView(
        message: 'Setting up your coaching session...',
      ),
      error: (error, stackTrace) => BackendErrorView(
        error: error,
        onRetry: () => ref.invalidate(onboardingControllerProvider),
      ),
      data: (onboarding) {
        final draft = draftAsync.valueOrNull;
        if (draft == null) {
          return const BackendLoadingView(message: 'Loading your profile...');
        }
        return _OnboardingScaffold(
          onboarding: onboarding,
          isFinishing: _isFinishing,
          onBack: _handleBack,
          onContinue: () => _handleContinue(onboarding),
          onFinish: () => _handleFinish(draft, onboarding),
        );
      },
    );
  }

  Future<void> _handleBack() async {
    await ref.read(onboardingControllerProvider.notifier).goBack();
  }

  Future<void> _handleContinue(OnboardingStateModel onboarding) async {
    await _continueOnboarding(ref, onboarding);
  }

  Future<void> _handleFinish(
    AppDraftState draft,
    OnboardingStateModel onboarding,
  ) async {
    final controller = ref.read(onboardingControllerProvider.notifier);
    final validation = controller.validateForCompletion(onboarding);
    if (!validation.isValid) {
      await controller.goToStep(OnboardingStepId.fromWireValue(
        onboarding.currentStepId,
      ));
      return;
    }

    setState(() => _isFinishing = true);
    try {
      final isDevRestart = kDebugMode && ref.read(forceShowOnboardingProvider);
      if (isDevRestart) {
        await controller.complete();
        ref.read(forceShowOnboardingProvider.notifier).state = false;
        ref.read(hasCompletedOnboardingProvider.notifier).state = true;
        return;
      }

      final answers = onboarding.answers;
      final profile = draft.profile.copyWith(
        name: _resolvedProfileName(draft),
        goal: _goalTitle(answers.fitnessGoal),
        coachingPreference: _coachingFocus(answers),
        userLevel: _toUserLevel(answers.experienceLevel),
        age: answers.age ?? draft.profile.age,
        heightCm: answers.heightCm ?? draft.profile.heightCm,
        weightKg: answers.weightKg ?? draft.profile.weightKg,
        sex: _sexTitle(answers.sex),
        availableTimeMinutes:
            answers.availableTimeMin ?? draft.profile.availableTimeMinutes,
        trainingPreference: _trainingPreferenceTitle(
          answers.trainingPreference,
        ),
        activityLevel: _activityTitle(answers.activityLevel),
        dietaryPreference: _dietaryPreferenceTitle(
          answers.dietaryPreference,
        ),
        goalTimeframe: _frequencyToTimeframe(
          onboarding.inference.recommendedFrequency,
        ),
        prefersVoiceLogging: false,
      );
      final syncResult =
          await ref.read(appDraftProvider.notifier).completeOnboardingProfile(
                profile: profile,
                answers: answers,
              );
      await controller.complete();
      if (kDebugMode) {
        ref.read(forceShowOnboardingProvider.notifier).state = false;
      }
      ref.read(hasCompletedOnboardingProvider.notifier).state = true;
      final warning = syncResult?.warning;
      if (warning != null && warning.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(warning)),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is AtlasOnboardingCredentialException
          ? error.message
          : 'I could not save the plan yet. Your setup is still here.';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Your answers are safe'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isFinishing = false);
      }
    }
  }

  String _resolvedProfileName(AppDraftState draft) {
    final existing = draft.profile.name.trim();
    if (existing.isNotEmpty && existing != 'JimBro User') {
      return existing;
    }
    final sessionName = draft.session?.displayName.trim();
    if (sessionName != null && sessionName.isNotEmpty) {
      return sessionName;
    }
    return 'JimBro User';
  }
}

Future<void> _continueOnboarding(
  WidgetRef ref,
  OnboardingStateModel onboarding,
) async {
  final controller = ref.read(onboardingControllerProvider.notifier);
  final step = OnboardingStepId.fromWireValue(onboarding.currentStepId);
  if (step == OnboardingStepId.age && onboarding.answers.age == null) {
    await controller.answerAge(_DefaultNumbers.age);
  }
  if (step == OnboardingStepId.height && onboarding.answers.heightCm == null) {
    await controller.answerHeightCm(_DefaultNumbers.heightCm.toDouble());
  }
  if (step == OnboardingStepId.weight && onboarding.answers.weightKg == null) {
    await controller.answerWeightKg(_DefaultNumbers.weightKg.toDouble());
  }
  if (step == OnboardingStepId.weight) {
    final latest = ref.read(onboardingControllerProvider).valueOrNull;
    final inference = _buildInference(latest?.answers ?? onboarding.answers);
    await controller.updateInference(
      recommendedFrequency: inference.recommendedFrequency,
      adherenceScore: inference.adherenceScore,
    );
  }
  await controller.continueFromCurrentStep();
}

class _OnboardingScaffold extends StatelessWidget {
  const _OnboardingScaffold({
    required this.onboarding,
    required this.isFinishing,
    required this.onBack,
    required this.onContinue,
    required this.onFinish,
  });

  final OnboardingStateModel onboarding;
  final bool isFinishing;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final step = OnboardingStepId.fromWireValue(onboarding.currentStepId);
    final spec = _screenSpecFor(step, onboarding.answers, onboarding.inference);
    final canContinue = _canContinue(step, onboarding);
    final progress = (_stepIndex(step) + 1) / OnboardingStepId.values.length;
    final isSummary = step == OnboardingStepId.coachSummary;

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
                _ProgressHeader(
                  progress: progress,
                  canGoBack: step != OnboardingStepId.welcome,
                  onBack: onBack,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final offset = Tween<Offset>(
                        begin: const Offset(.04, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: offset, child: child),
                      );
                    },
                    child: _OnboardingScreen(
                      key: ValueKey(step.wireValue),
                      spec: spec,
                      onboarding: onboarding,
                    ),
                  ),
                ),
                _BottomCta(
                  label: isSummary ? 'Start my plan' : spec.ctaLabel,
                  enabled: isSummary ? !isFinishing : canContinue,
                  isLoading: isFinishing,
                  onPressed: isSummary ? onFinish : onContinue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.progress,
    required this.canGoBack,
    required this.onBack,
  });

  final double progress;
  final bool canGoBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 20, 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: canGoBack
                ? IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : null,
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(JimRadius.pill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                color: JimColors.accentStrong,
                backgroundColor: JimColors.accentSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingScreen extends StatelessWidget {
  const _OnboardingScreen({
    super.key,
    required this.spec,
    required this.onboarding,
  });

  final _ScreenSpec spec;
  final OnboardingStateModel onboarding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        Center(
          child: JimCompanionAvatar(
            stage: spec.stage,
            size: spec.isInsight ? 104 : 92,
            showLabel: false,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          spec.intro,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: JimColors.inkSoft,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          spec.question,
          style: theme.textTheme.displaySmall?.copyWith(height: 1.08),
        ),
        const SizedBox(height: 12),
        Text(
          spec.supporting,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: JimColors.inkMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        spec.buildBody(context, onboarding),
        if (onboarding.errorMessage != null) ...[
          const SizedBox(height: 16),
          _InlineError(message: onboarding.errorMessage!),
        ],
      ],
    );
  }
}

class _BottomCta extends StatelessWidget {
  const _BottomCta({
    required this.label,
    required this.enabled,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          onPressed: enabled && !isLoading ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: JimColors.plaque,
            disabledBackgroundColor: JimColors.ivory,
            foregroundColor: JimColors.ink,
            disabledForegroundColor: JimColors.inkMuted,
            side: const BorderSide(color: JimColors.insetLine),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(JimRadius.pill),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: isLoading
                ? const SizedBox(
                    key: ValueKey('loading'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(key: const ValueKey('label'), label),
          ),
        ),
      ),
    );
  }
}

class _ChoiceList<T> extends ConsumerWidget {
  const _ChoiceList({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<_ChoiceOption<T>> options;
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: options
          .map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SelectionCard(
                key: ValueKey('onboarding-option-${option.title}'),
                icon: option.icon,
                title: option.title,
                description: option.description,
                selected: option.value == selected,
                onTap: () => onSelected(option.value),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedScale(
      scale: selected ? 1.012 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(JimRadius.md),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selected ? JimColors.accentSoft : JimColors.plaque,
              borderRadius: BorderRadius.circular(JimRadius.md),
              border: Border.all(
                color: selected ? JimColors.accentStrong : JimColors.insetLine,
                width: selected ? 1.4 : 1,
              ),
              boxShadow: selected ? JimElevation.card : const [],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected ? JimColors.plaque : JimColors.galleryWhite,
                    borderRadius: BorderRadius.circular(JimRadius.sm),
                  ),
                  child: Icon(icon, color: JimColors.accentStrong),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: JimColors.inkSoft,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: JimColors.accentStrong,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberPickerCard extends ConsumerWidget {
  const _NumberPickerCard({
    required this.title,
    required this.description,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final String description;
  final int value;
  final String unit;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return JimSurface(
      radius: JimRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: JimColors.inkSoft),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _RoundIconButton(
                icon: Icons.remove_rounded,
                onTap: value > min ? () => onChanged(value - 1) : null,
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(JimRadius.lg),
                  onTap: () async {
                    final picked = await _showNumberWheel(
                      context,
                      value: value,
                      min: min,
                      max: max,
                      unit: unit,
                    );
                    if (picked != null) {
                      onChanged(picked);
                    }
                  },
                  child: Column(
                    children: [
                      Text(
                        '$value',
                        style: Theme.of(context)
                            .textTheme
                            .displayMedium
                            ?.copyWith(color: JimColors.ink),
                      ),
                      Text(unit, style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ),
                ),
              ),
              _RoundIconButton(
                icon: Icons.add_rounded,
                onTap: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: JimColors.accentSoft,
      borderRadius: BorderRadius.circular(JimRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JimRadius.pill),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: JimColors.accentStrong),
        ),
      ),
    );
  }
}

class _CoachInsightCard extends StatelessWidget {
  const _CoachInsightCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return JimSurface(
      radius: JimRadius.lg,
      backgroundColor: JimColors.plaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: JimColors.accentSoft,
                  borderRadius: BorderRadius.circular(JimRadius.sm),
                ),
                child: const Icon(
                  Icons.psychology_alt_outlined,
                  color: JimColors.accentStrong,
                ),
              ),
              const SizedBox(width: 12),
              Text('Jim noticed',
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: JimColors.inkSoft,
                  height: 1.55,
                ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.answers,
    required this.inference,
  });

  final OnboardingAnswersDto answers;
  final OnboardingInferenceResultDto inference;

  @override
  Widget build(BuildContext context) {
    final computed = _buildInference(answers);
    final frequency =
        inference.recommendedFrequency ?? computed.recommendedFrequency;
    final adherence = inference.adherenceScore ?? computed.adherenceScore;
    final summary = _personalizedCoachSummary(answers, frequency);
    final recommendation = _coachingRecommendation(answers, frequency);
    final explanation = _summaryExplanation(answers, frequency, adherence);
    final reinforcement = _positiveReinforcement(answers, adherence);
    return JimSurface(
      radius: JimRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: JimColors.ink,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryChip(
                label: 'Goal',
                value: _goalTitle(answers.fitnessGoal),
              ),
              _SummaryChip(
                label: 'Motivation',
                value: _motivationChip(answers.motivation),
              ),
              _SummaryChip(
                label: 'Experience',
                value: _experienceChip(answers.experienceLevel),
              ),
              _SummaryChip(
                label: 'Training style',
                value: _trainingPreferenceTitle(answers.trainingPreference),
              ),
              _SummaryChip(
                label: 'Time',
                value: _availableTimeTitle(answers.availableTimeMin),
              ),
              _SummaryChip(
                label: 'Frequency',
                value: frequency,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _CoachReflectionBlock(
            icon: Icons.lightbulb_outline_rounded,
            title: 'My recommendation',
            value: recommendation,
          ),
          const SizedBox(height: 12),
          _CoachReflectionBlock(
            icon: Icons.route_outlined,
            title: 'Why this fits',
            value: explanation,
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: JimMotion.gentle,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: JimColors.accentSoft,
              borderRadius: BorderRadius.circular(JimRadius.md),
              border: Border.all(color: JimColors.accentLine),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: JimColors.accentStrong,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    reinforcement,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: JimColors.inkSoft,
                          height: 1.45,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: JimColors.galleryWhite,
        borderRadius: BorderRadius.circular(JimRadius.pill),
        border: Border.all(color: JimColors.insetLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: JimColors.inkMuted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: JimColors.ink,
                ),
          ),
        ],
      ),
    );
  }
}

class _CoachReflectionBlock extends StatelessWidget {
  const _CoachReflectionBlock({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: JimColors.plaque,
        borderRadius: BorderRadius.circular(JimRadius.md),
        border: Border.all(color: JimColors.insetLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: JimColors.accentSoft,
              borderRadius: BorderRadius.circular(JimRadius.sm),
            ),
            child: Icon(icon, color: JimColors.accentStrong, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: JimColors.inkSoft,
                    height: 1.42,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F0),
        borderRadius: BorderRadius.circular(JimRadius.sm),
        border: Border.all(color: const Color(0xFFFFCCC7)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: JimColors.terracotta,
              height: 1.35,
            ),
      ),
    );
  }
}

class _ScreenSpec {
  const _ScreenSpec({
    required this.intro,
    required this.question,
    required this.supporting,
    required this.ctaLabel,
    required this.stage,
    required this.buildBody,
    this.isInsight = false,
  });

  final String intro;
  final String question;
  final String supporting;
  final String ctaLabel;
  final JimCompanionStage stage;
  final bool isInsight;
  final Widget Function(BuildContext, OnboardingStateModel) buildBody;
}

class _ChoiceOption<T> {
  const _ChoiceOption({
    required this.value,
    required this.title,
    required this.description,
    required this.icon,
  });

  final T value;
  final String title;
  final String description;
  final IconData icon;
}

class _DefaultNumbers {
  static const age = 28;
  static const heightCm = 172;
  static const weightKg = 74;
}

_ScreenSpec _screenSpecFor(
  OnboardingStepId step,
  OnboardingAnswersDto answers,
  OnboardingInferenceResultDto inference,
) {
  return switch (step) {
    OnboardingStepId.welcome => _ScreenSpec(
        intro:
            'JimBro is here to help you build a routine that fits your real life.',
        question: 'Ready to set up your first coaching plan?',
        supporting:
            'This takes about a minute. I’ll ask only what I need to shape your workouts, food guidance, and first steps.',
        ctaLabel: 'Start setup',
        stage: JimCompanionStage.softBase,
        buildBody: (context, state) => const _CoachInsightCard(
          message:
              'We’ll keep this focused. You answer one thing at a time, and I’ll turn it into a starting plan you can actually use.',
        ),
      ),
    OnboardingStepId.goal => _ScreenSpec(
        intro:
            'A clear goal helps me coach you toward the right kind of progress.',
        question: 'What do you want to work toward first?',
        supporting:
            'Pick the outcome that matters most right now. You can change it later.',
        ctaLabel: 'Continue',
        stage: JimCompanionStage.softBase,
        buildBody: (context, state) => _ChoiceList<OnboardingFitnessGoal>(
          selected: state.answers.fitnessGoal,
          onSelected: (value) =>
              context.readOnboarding().answerFitnessGoal(value),
          options: const [
            _ChoiceOption(
              value: OnboardingFitnessGoal.buildMuscle,
              title: 'Build muscle',
              description: 'Add size and shape over time.',
              icon: Icons.fitness_center_rounded,
            ),
            _ChoiceOption(
              value: OnboardingFitnessGoal.getStronger,
              title: 'Get stronger',
              description: 'Focus on lifting more with steady progress.',
              icon: Icons.trending_up_rounded,
            ),
            _ChoiceOption(
              value: OnboardingFitnessGoal.loseWeight,
              title: 'Lose weight',
              description: 'Build habits that support a leaner body.',
              icon: Icons.flag_outlined,
            ),
            _ChoiceOption(
              value: OnboardingFitnessGoal.feelFitter,
              title: 'Feel fitter',
              description: 'Improve energy, movement, and confidence.',
              icon: Icons.bolt_rounded,
            ),
            _ChoiceOption(
              value: OnboardingFitnessGoal.stayConsistent,
              title: 'Stay consistent',
              description: 'Make showing up feel easier.',
              icon: Icons.event_available_rounded,
            ),
          ],
        ),
      ),
    OnboardingStepId.motivation => _ScreenSpec(
        intro:
            'Your reason matters. It helps me coach you in a way that actually lands.',
        question: 'What is driving you right now?',
        supporting: 'Choose the one that feels closest.',
        ctaLabel: 'Continue',
        stage: JimCompanionStage.softBase,
        buildBody: (context, state) => _ChoiceList<OnboardingMotivation>(
          selected: state.answers.motivation,
          onSelected: (value) =>
              context.readOnboarding().answerMotivation(value),
          options: const [
            _ChoiceOption(
              value: OnboardingMotivation.feelBetter,
              title: 'I want to feel better in my body',
              description: 'We’ll focus on confidence and steady wins.',
              icon: Icons.self_improvement_rounded,
            ),
            _ChoiceOption(
              value: OnboardingMotivation.moreEnergy,
              title: 'I want more energy',
              description: 'We’ll build around routines that support your day.',
              icon: Icons.wb_sunny_outlined,
            ),
            _ChoiceOption(
              value: OnboardingMotivation.lookDifferent,
              title: 'I want to look different',
              description:
                  'We’ll connect training and food to visible progress.',
              icon: Icons.visibility_outlined,
            ),
            _ChoiceOption(
              value: OnboardingMotivation.moreDiscipline,
              title: 'I want more discipline',
              description: 'We’ll make consistency easier to repeat.',
              icon: Icons.check_circle_outline_rounded,
            ),
            _ChoiceOption(
              value: OnboardingMotivation.eventOrMilestone,
              title: 'I have a milestone coming up',
              description: 'We’ll keep the plan focused and time-aware.',
              icon: Icons.emoji_events_outlined,
            ),
          ],
        ),
      ),
    OnboardingStepId.experience => _ScreenSpec(
        intro: 'I’ll meet you where you are. No judgment, no pretending.',
        question: 'What feels most true about your training right now?',
        supporting: 'This helps me choose the right starting pace.',
        ctaLabel: 'Continue',
        stage: JimCompanionStage.activeBase,
        buildBody: (context, state) => _ChoiceList<OnboardingExperienceLevel>(
          selected: state.answers.experienceLevel,
          onSelected: (value) =>
              context.readOnboarding().answerExperienceLevel(value),
          options: const [
            _ChoiceOption(
              value: OnboardingExperienceLevel.justStarting,
              title: 'I’m just starting',
              description: 'We’ll keep the first steps simple and clear.',
              icon: Icons.spa_outlined,
            ),
            _ChoiceOption(
              value: OnboardingExperienceLevel.inconsistent,
              title: 'I’ve trained before, but not consistently',
              description: 'We’ll rebuild momentum without overloading you.',
              icon: Icons.restart_alt_rounded,
            ),
            _ChoiceOption(
              value: OnboardingExperienceLevel.regular,
              title: 'I train pretty regularly',
              description: 'We’ll make your routine more focused.',
              icon: Icons.calendar_month_outlined,
            ),
            _ChoiceOption(
              value: OnboardingExperienceLevel.established,
              title: 'I already have a routine',
              description:
                  'We’ll improve what you’re doing, not replace everything.',
              icon: Icons.workspace_premium_outlined,
            ),
          ],
        ),
      ),
    OnboardingStepId.goalInsight => _ScreenSpec(
        intro: 'Here’s what I’m hearing so far.',
        question: 'This gives us a useful starting point.',
        supporting:
            'I’m connecting your goal, reason, and current rhythm before asking about your week.',
        ctaLabel: 'Continue',
        stage: JimCompanionStage.activeBase,
        isInsight: true,
        buildBody: (context, state) => _CoachInsightCard(
          message: _buildGoalInsight(state.answers),
        ),
      ),
    OnboardingStepId.activityLevel => _ScreenSpec(
        intro: 'Your daily movement affects how demanding a plan feels.',
        question: 'How active is a normal day for you?',
        supporting:
            'Think about work, walking, commuting, chores, and general movement.',
        ctaLabel: 'Continue',
        stage: JimCompanionStage.activeBase,
        buildBody: (context, state) => _ChoiceList<OnboardingActivityLevel>(
          selected: state.answers.activityLevel,
          onSelected: (value) =>
              context.readOnboarding().answerActivityLevel(value),
          options: const [
            _ChoiceOption(
              value: OnboardingActivityLevel.mostlySitting,
              title: 'Mostly sitting',
              description: 'Most of my day is seated or low movement.',
              icon: Icons.chair_outlined,
            ),
            _ChoiceOption(
              value: OnboardingActivityLevel.lightlyActive,
              title: 'Lightly active',
              description: 'I walk or move a little most days.',
              icon: Icons.directions_walk_rounded,
            ),
            _ChoiceOption(
              value: OnboardingActivityLevel.moderatelyActive,
              title: 'Moderately active',
              description: 'I’m on my feet often or move regularly.',
              icon: Icons.directions_run_rounded,
            ),
            _ChoiceOption(
              value: OnboardingActivityLevel.veryActive,
              title: 'Very active',
              description: 'My day already includes a lot of movement.',
              icon: Icons.local_fire_department_outlined,
            ),
            _ChoiceOption(
              value: OnboardingActivityLevel.changesALot,
              title: 'It changes a lot',
              description: 'My schedule is inconsistent week to week.',
              icon: Icons.sync_alt_rounded,
            ),
          ],
        ),
      ),
    OnboardingStepId.availableTime => _ScreenSpec(
        intro: 'A plan works better when it respects your calendar.',
        question: 'How much time can you usually give a workout?',
        supporting: 'Choose what feels realistic, not ideal.',
        ctaLabel: 'Continue',
        stage: JimCompanionStage.activeBase,
        buildBody: (context, state) => _ChoiceList<int>(
          selected: state.answers.availableTimeMin,
          onSelected: (value) =>
              context.readOnboarding().answerAvailableTimeMin(value),
          options: const [
            _ChoiceOption(
              value: 20,
              title: '20 minutes',
              description: 'Short, focused sessions.',
              icon: Icons.timer_outlined,
            ),
            _ChoiceOption(
              value: 30,
              title: '30 minutes',
              description:
                  'Simple enough to repeat, long enough to feel useful.',
              icon: Icons.schedule_rounded,
            ),
            _ChoiceOption(
              value: 45,
              title: '45 minutes',
              description: 'A balanced session with room to build.',
              icon: Icons.more_time_rounded,
            ),
            _ChoiceOption(
              value: 60,
              title: '60 minutes',
              description: 'More space for a complete workout.',
              icon: Icons.timelapse_rounded,
            ),
          ],
        ),
      ),
    OnboardingStepId.trainingPreference => _ScreenSpec(
        intro: 'The best workout is one you’ll actually come back to.',
        question: 'What kind of training sounds most appealing?',
        supporting: 'I’ll use this to shape your first plan.',
        ctaLabel: 'Continue',
        stage: JimCompanionStage.activeBase,
        buildBody: (context, state) =>
            _ChoiceList<OnboardingTrainingPreference>(
          selected: state.answers.trainingPreference,
          onSelected: (value) =>
              context.readOnboarding().answerTrainingPreference(value),
          options: const [
            _ChoiceOption(
              value: OnboardingTrainingPreference.gym,
              title: 'Gym workouts',
              description: 'Use machines, weights, or gym equipment.',
              icon: Icons.fitness_center_rounded,
            ),
            _ChoiceOption(
              value: OnboardingTrainingPreference.home,
              title: 'Home workouts',
              description: 'Train with limited space or simple equipment.',
              icon: Icons.home_outlined,
            ),
            _ChoiceOption(
              value: OnboardingTrainingPreference.bodyweight,
              title: 'Bodyweight workouts',
              description: 'Use your own body and keep setup minimal.',
              icon: Icons.accessibility_new_rounded,
            ),
            _ChoiceOption(
              value: OnboardingTrainingPreference.mixed,
              title: 'A mix of everything',
              description: 'Keep the plan flexible.',
              icon: Icons.all_inclusive_rounded,
            ),
            _ChoiceOption(
              value: OnboardingTrainingPreference.unsure,
              title: 'I’m not sure yet',
              description: 'I’ll start simple and help you learn what fits.',
              icon: Icons.explore_outlined,
            ),
          ],
        ),
      ),
    OnboardingStepId.lifestyleInsight => _ScreenSpec(
        intro: 'Now we can make this fit your week.',
        question: 'You have a realistic path forward.',
        supporting:
            'I’m using your routine, time, and training preference to keep the plan repeatable.',
        ctaLabel: 'Continue',
        stage: JimCompanionStage.armored1,
        isInsight: true,
        buildBody: (context, state) => _CoachInsightCard(
          message: _buildLifestyleInsight(state.answers),
        ),
      ),
    OnboardingStepId.dietaryPreference => _ScreenSpec(
        intro: 'Food guidance should fit the way you actually eat.',
        question: 'How would you like JimBro to support your food habits?',
        supporting:
            'This is not about perfection. It helps me choose the right level of guidance.',
        ctaLabel: 'Continue',
        stage: JimCompanionStage.armored1,
        buildBody: (context, state) => _ChoiceList<OnboardingDietaryPreference>(
          selected: state.answers.dietaryPreference,
          onSelected: (value) =>
              context.readOnboarding().answerDietaryPreference(value),
          options: const [
            _ChoiceOption(
              value: OnboardingDietaryPreference.simple,
              title: 'Keep it simple',
              description: 'Focus on awareness and small improvements.',
              icon: Icons.lightbulb_outline_rounded,
            ),
            _ChoiceOption(
              value: OnboardingDietaryPreference.protein,
              title: 'Help me eat more protein',
              description: 'Make meals more supportive for training.',
              icon: Icons.restaurant_rounded,
            ),
            _ChoiceOption(
              value: OnboardingDietaryPreference.calories,
              title: 'Help me manage calories',
              description: 'Give clearer targets and daily feedback.',
              icon: Icons.insights_rounded,
            ),
            _ChoiceOption(
              value: OnboardingDietaryPreference.mealPlanning,
              title: 'Help me plan meals',
              description: 'Make food decisions easier ahead of time.',
              icon: Icons.menu_book_outlined,
            ),
            _ChoiceOption(
              value: OnboardingDietaryPreference.notNow,
              title: 'Not now',
              description: 'Start with training first.',
              icon: Icons.pause_circle_outline_rounded,
            ),
          ],
        ),
      ),
    OnboardingStepId.age => _numberSpec(
        intro: 'Your age helps me make better estimates for your plan.',
        question: 'How old are you?',
        supporting: 'I’ll use this only to personalize targets and pacing.',
        title: 'Age',
        description: 'Use your age in years.',
        value: answers.age ?? _DefaultNumbers.age,
        unit: 'years',
        min: 13,
        max: 100,
        onChanged: (context, value) =>
            context.readOnboarding().answerAge(value),
      ),
    OnboardingStepId.sex => _ScreenSpec(
        intro:
            'Some estimates work better when I understand your body context.',
        question: 'Which option should I use for your plan?',
        supporting:
            'This helps with basic calculations. Choose what you’re comfortable sharing.',
        ctaLabel: 'Continue',
        stage: JimCompanionStage.armored1,
        buildBody: (context, state) => _ChoiceList<OnboardingSex>(
          selected: state.answers.sex,
          onSelected: (value) => context.readOnboarding().answerSex(value),
          options: const [
            _ChoiceOption(
              value: OnboardingSex.female,
              title: 'Female',
              description: 'Use female-based estimates.',
              icon: Icons.female_rounded,
            ),
            _ChoiceOption(
              value: OnboardingSex.male,
              title: 'Male',
              description: 'Use male-based estimates.',
              icon: Icons.male_rounded,
            ),
            _ChoiceOption(
              value: OnboardingSex.preferNotToSay,
              title: 'Prefer not to say',
              description: 'I’ll use a neutral starting estimate.',
              icon: Icons.person_outline_rounded,
            ),
          ],
        ),
      ),
    OnboardingStepId.height => _numberSpec(
        intro:
            'Height helps me personalize your nutrition and progress estimates.',
        question: 'What is your height?',
        supporting: 'An estimate is fine. You can update it later.',
        title: 'Height',
        description: 'Use centimeters.',
        value: answers.heightCm?.round() ?? _DefaultNumbers.heightCm,
        unit: 'cm',
        min: 90,
        max: 250,
        onChanged: (context, value) =>
            context.readOnboarding().answerHeightCm(value.toDouble()),
      ),
    OnboardingStepId.weight => _numberSpec(
        intro: 'Weight helps me make your targets more useful from day one.',
        question: 'What is your current weight?',
        supporting: 'This is just a starting point, not a judgment.',
        title: 'Weight',
        description: 'Use kilograms.',
        value: answers.weightKg?.round() ?? _DefaultNumbers.weightKg,
        unit: 'kg',
        min: 30,
        max: 300,
        onChanged: (context, value) =>
            context.readOnboarding().answerWeightKg(value.toDouble()),
      ),
    OnboardingStepId.coachSummary => _ScreenSpec(
        intro: 'Got it. Here’s how I’ll coach you to start.',
        question: 'This plan is built around what you shared.',
        supporting:
            'I’ll use your answers to shape your first workouts, food guidance, and daily nudges.',
        ctaLabel: 'Start my plan',
        stage: JimCompanionStage.armored2,
        buildBody: (context, state) => _SummaryCard(
          answers: state.answers,
          inference: state.inference,
        ),
      ),
  };
}

_ScreenSpec _numberSpec({
  required String intro,
  required String question,
  required String supporting,
  required String title,
  required String description,
  required int value,
  required String unit,
  required int min,
  required int max,
  required void Function(BuildContext, int) onChanged,
}) {
  return _ScreenSpec(
    intro: intro,
    question: question,
    supporting: supporting,
    ctaLabel: 'Continue',
    stage: JimCompanionStage.armored1,
    buildBody: (context, state) => _NumberPickerCard(
      title: title,
      description: description,
      value: value,
      unit: unit,
      min: min,
      max: max,
      onChanged: (next) => onChanged(context, next),
    ),
  );
}

extension _OnboardingContext on BuildContext {
  OnboardingController readOnboarding() {
    return ProviderScope.containerOf(this, listen: false)
        .read(onboardingControllerProvider.notifier);
  }
}

bool _canContinue(OnboardingStepId step, OnboardingStateModel onboarding) {
  if (step == OnboardingStepId.age ||
      step == OnboardingStepId.height ||
      step == OnboardingStepId.weight) {
    return true;
  }
  if (step == OnboardingStepId.coachSummary) {
    return onboarding.hasRequiredInferenceInputs;
  }
  return switch (step) {
    OnboardingStepId.welcome => true,
    OnboardingStepId.goal => onboarding.answers.fitnessGoal != null,
    OnboardingStepId.motivation => onboarding.answers.motivation != null,
    OnboardingStepId.experience => onboarding.answers.experienceLevel != null,
    OnboardingStepId.goalInsight => onboarding.answers.fitnessGoal != null &&
        onboarding.answers.motivation != null &&
        onboarding.answers.experienceLevel != null,
    OnboardingStepId.activityLevel => onboarding.answers.activityLevel != null,
    OnboardingStepId.availableTime =>
      onboarding.answers.availableTimeMin != null,
    OnboardingStepId.trainingPreference =>
      onboarding.answers.trainingPreference != null,
    OnboardingStepId.lifestyleInsight =>
      onboarding.answers.activityLevel != null &&
          onboarding.answers.availableTimeMin != null &&
          onboarding.answers.trainingPreference != null,
    OnboardingStepId.dietaryPreference =>
      onboarding.answers.dietaryPreference != null,
    OnboardingStepId.sex => onboarding.answers.sex != null,
    OnboardingStepId.age ||
    OnboardingStepId.height ||
    OnboardingStepId.weight ||
    OnboardingStepId.coachSummary =>
      true,
  };
}

int _stepIndex(OnboardingStepId step) => OnboardingStepId.values.indexOf(step);

Future<int?> _showNumberWheel(
  BuildContext context, {
  required int value,
  required int min,
  required int max,
  required String unit,
}) {
  var selected = value.clamp(min, max).toInt();
  final controller = FixedExtentScrollController(initialItem: selected - min);
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: JimColors.plaque,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(JimRadius.lg)),
    ),
    builder: (context) {
      return SafeArea(
        top: false,
        child: SizedBox(
          height: 320,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text('Choose $unit',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(selected),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListWheelScrollView.useDelegate(
                  controller: controller,
                  itemExtent: 48,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (index) => selected = min + index,
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: max - min + 1,
                    builder: (context, index) {
                      final number = min + index;
                      return Center(
                        child: Text(
                          '$number $unit',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _buildGoalInsight(OnboardingAnswersDto answers) {
  return 'Based on what you’ve told me, ${_goalObservation(answers.fitnessGoal)} '
      '${_motivationObservation(answers.motivation)} Since ${_experienceObservation(answers.experienceLevel)}, '
      'I’ll start by ${_experienceResponse(answers.experienceLevel)}';
}

String _buildLifestyleInsight(OnboardingAnswersDto answers) {
  return 'Based on your week, ${_activityObservation(answers.activityLevel)} '
      'With ${_timeObservation(answers.availableTimeMin)} and ${_trainingObservation(answers.trainingPreference)}, '
      'I’ll shape your first plan around ${_realisticResponse(answers)}';
}

_InferenceResult _buildInference(OnboardingAnswersDto answers) {
  final frequency = _recommendedFrequency(answers);
  final score = _adherenceScore(answers);
  return _InferenceResult(
    recommendedFrequency: frequency,
    adherenceScore: score,
  );
}

String _recommendedFrequency(OnboardingAnswersDto answers) {
  final experience = answers.experienceLevel;
  final time = answers.availableTimeMin ?? 30;
  final activity = answers.activityLevel;
  final goal = answers.fitnessGoal;

  var low = switch (experience) {
    OnboardingExperienceLevel.justStarting => 2,
    OnboardingExperienceLevel.inconsistent => 3,
    OnboardingExperienceLevel.regular => 4,
    OnboardingExperienceLevel.established => 4,
    null => 2,
  };
  var high = switch (experience) {
    OnboardingExperienceLevel.justStarting => 2,
    OnboardingExperienceLevel.inconsistent => 3,
    OnboardingExperienceLevel.regular => 4,
    OnboardingExperienceLevel.established => 5,
    null => 3,
  };

  if (time <= 20) {
    high = high.clamp(2, 3);
  }
  if (time == 30) {
    high = high.clamp(2, 4);
  }
  if (activity == OnboardingActivityLevel.changesALot ||
      goal == OnboardingFitnessGoal.stayConsistent) {
    low = low.clamp(2, 3);
    high = high.clamp(2, 3);
  }
  if (goal == OnboardingFitnessGoal.feelFitter &&
      activity == OnboardingActivityLevel.mostlySitting) {
    low = 2;
    high = 3;
  }
  if (low == high) {
    return '$low days/week';
  }
  return '$low-$high days/week';
}

int _adherenceScore(OnboardingAnswersDto answers) {
  var score = switch (answers.availableTimeMin) {
    20 => 78,
    30 => 82,
    45 => 76,
    60 => 68,
    _ => 72,
  };
  score += switch (answers.experienceLevel) {
    OnboardingExperienceLevel.justStarting => -4,
    OnboardingExperienceLevel.inconsistent => -2,
    OnboardingExperienceLevel.regular => 6,
    OnboardingExperienceLevel.established => 8,
    null => 0,
  };
  score += switch (answers.activityLevel) {
    OnboardingActivityLevel.mostlySitting => -2,
    OnboardingActivityLevel.lightlyActive => 2,
    OnboardingActivityLevel.moderatelyActive => 4,
    OnboardingActivityLevel.veryActive => 2,
    OnboardingActivityLevel.changesALot => -6,
    null => 0,
  };
  score += switch (answers.trainingPreference) {
    OnboardingTrainingPreference.gym => 3,
    OnboardingTrainingPreference.home => 3,
    OnboardingTrainingPreference.bodyweight => 4,
    OnboardingTrainingPreference.mixed => 1,
    OnboardingTrainingPreference.unsure => -3,
    null => 0,
  };
  score += switch (answers.motivation) {
    OnboardingMotivation.feelBetter => 2,
    OnboardingMotivation.moreEnergy => 2,
    OnboardingMotivation.lookDifferent => -1,
    OnboardingMotivation.moreDiscipline => -2,
    OnboardingMotivation.eventOrMilestone => 1,
    null => 0,
  };
  return score.clamp(40, 95).toInt();
}

String _coachingFocus(OnboardingAnswersDto answers) {
  final base = switch (answers.fitnessGoal) {
    OnboardingFitnessGoal.buildMuscle =>
      'Build a repeatable training routine with simple food support.',
    OnboardingFitnessGoal.getStronger =>
      'Practice key movements and track steady progress.',
    OnboardingFitnessGoal.loseWeight =>
      'Build food awareness while keeping training realistic.',
    OnboardingFitnessGoal.feelFitter =>
      'Improve energy, confidence, and weekly movement.',
    OnboardingFitnessGoal.stayConsistent => 'Make showing up easier.',
    null => 'Build a routine that feels realistic.',
  };
  final food = switch (answers.dietaryPreference) {
    OnboardingDietaryPreference.protein =>
      ' We’ll keep protein as a simple food anchor.',
    OnboardingDietaryPreference.calories =>
      ' We’ll add calorie awareness without making it feel heavy.',
    OnboardingDietaryPreference.mealPlanning =>
      ' We’ll make meal decisions easier ahead of time.',
    OnboardingDietaryPreference.notNow =>
      ' We’ll keep food guidance quiet until you want it.',
    _ => '',
  };
  return '$base$food';
}

String _primaryRecommendation(
  OnboardingAnswersDto answers,
  String frequency,
) {
  if (answers.activityLevel == OnboardingActivityLevel.changesALot) {
    return 'Use $frequency with one short backup session for messy weeks.';
  }
  if (answers.trainingPreference == OnboardingTrainingPreference.unsure) {
    return 'Start with simple sessions until you learn what feels best.';
  }
  return switch (answers.fitnessGoal) {
    OnboardingFitnessGoal.stayConsistent =>
      'Start with $frequency. The first win is showing up.',
    OnboardingFitnessGoal.loseWeight =>
      'Start with $frequency and one simple food check-in.',
    OnboardingFitnessGoal.buildMuscle =>
      'Start with $frequency and keep meals supportive, not complicated.',
    OnboardingFitnessGoal.getStronger =>
      'Start with $frequency and track a few repeatable lifts.',
    OnboardingFitnessGoal.feelFitter =>
      'Start with $frequency and keep the sessions energizing.',
    null => 'Start with $frequency and keep it simple.',
  };
}

String _personalizedCoachSummary(
  OnboardingAnswersDto answers,
  String frequency,
) {
  return 'Based on what you shared, you want to ${_goalSentence(answers.fitnessGoal)} because ${_motivationSummary(answers.motivation)}. '
      'You’re starting from ${_experiencePhrase(answers.experienceLevel)}, and ${_trainingPreferencePhrase(answers.trainingPreference)} fits best with the time you have. '
      'So I’d start you at $frequency, then build from there once the routine feels steady.';
}

String _coachingRecommendation(
  OnboardingAnswersDto answers,
  String frequency,
) {
  final training = _trainingPreferencePhrase(answers.trainingPreference);
  final food = switch (answers.dietaryPreference) {
    OnboardingDietaryPreference.simple =>
      'I’ll keep food guidance simple and focused on small useful choices.',
    OnboardingDietaryPreference.protein =>
      'I’ll use protein as your first food anchor because it supports training without making every meal complicated.',
    OnboardingDietaryPreference.calories =>
      'I’ll help you understand calories clearly, but we’ll start with awareness before pressure.',
    OnboardingDietaryPreference.mealPlanning =>
      'I’ll help you plan ahead so food decisions feel easier during the week.',
    OnboardingDietaryPreference.notNow =>
      'I’ll keep food support quiet for now and focus first on training consistency.',
    null =>
      'I’ll keep food guidance light until you choose how much support you want.',
  };
  return 'Start with $frequency using $training. ${_primaryRecommendation(answers, frequency)} $food';
}

String _summaryExplanation(
  OnboardingAnswersDto answers,
  String frequency,
  int adherence,
) {
  final time = _availableTimeTitle(answers.availableTimeMin).toLowerCase();
  final experience = _experiencePhrase(answers.experienceLevel);
  final activity = _activitySummaryPhrase(answers.activityLevel);
  return 'I’m choosing $frequency because you have $time, you’re starting from $experience, and $activity. '
      'That gives you enough structure to make progress without turning week one into a test. '
      'The plan looks ${_adherenceLabel(adherence).toLowerCase()}, which is exactly what we want at the start.';
}

String _positiveReinforcement(
  OnboardingAnswersDto answers,
  int adherence,
) {
  final motivation = switch (answers.motivation) {
    OnboardingMotivation.feelBetter =>
      'You do not need a perfect plan to start feeling better. You need a plan that keeps inviting you back.',
    OnboardingMotivation.moreEnergy =>
      'This is a strong start because it respects your energy instead of spending it all at once.',
    OnboardingMotivation.lookDifferent =>
      'Visible progress comes from repeatable weeks. This gives you a first week you can actually repeat.',
    OnboardingMotivation.moreDiscipline =>
      'Discipline starts with small promises kept. This plan gives you a clear promise to keep.',
    OnboardingMotivation.eventOrMilestone =>
      'You have a clear reason to begin. We’ll use that focus without making the plan feel frantic.',
    null =>
      'This is a useful starting point because it is clear, realistic, and easy to adjust.',
  };
  return '$motivation Your starting confidence is ${_adherenceLabel(adherence).toLowerCase()}, and we’ll earn more by stacking small wins.';
}

String _goalObservation(OnboardingFitnessGoal? goal) {
  return switch (goal) {
    OnboardingFitnessGoal.buildMuscle =>
      'you want to build more shape and strength over time.',
    OnboardingFitnessGoal.getStronger =>
      'you want to feel stronger and more capable.',
    OnboardingFitnessGoal.loseWeight =>
      'you want progress that feels visible and sustainable.',
    OnboardingFitnessGoal.feelFitter =>
      'you want more energy, confidence, and ease in your body.',
    OnboardingFitnessGoal.stayConsistent =>
      'you want a routine you can actually keep coming back to.',
    null => 'you want a plan that feels useful from the start.',
  };
}

String _motivationObservation(OnboardingMotivation? motivation) {
  return switch (motivation) {
    OnboardingMotivation.feelBetter =>
      'That tells me this is about feeling better day to day, not chasing a perfect plan.',
    OnboardingMotivation.moreEnergy =>
      'That tells me your plan should support your energy, not drain it.',
    OnboardingMotivation.lookDifferent =>
      'That tells me visible progress matters, so we’ll connect your actions to clear feedback.',
    OnboardingMotivation.moreDiscipline =>
      'That tells me you want structure that helps you keep promises to yourself.',
    OnboardingMotivation.eventOrMilestone =>
      'That tells me there’s something specific you want to feel ready for.',
    null => 'That tells me the plan should stay focused and personal.',
  };
}

String _experienceObservation(OnboardingExperienceLevel? experience) {
  return switch (experience) {
    OnboardingExperienceLevel.justStarting => 'you’re just starting',
    OnboardingExperienceLevel.inconsistent =>
      'you’ve trained before but consistency has been hard',
    OnboardingExperienceLevel.regular => 'you already have some rhythm',
    OnboardingExperienceLevel.established => 'you already know how to show up',
    null => 'we are still finding your starting point',
  };
}

String _experienceResponse(OnboardingExperienceLevel? experience) {
  return switch (experience) {
    OnboardingExperienceLevel.justStarting =>
      'making the first steps clear, small, and easy to repeat.',
    OnboardingExperienceLevel.inconsistent =>
      'helping you rebuild momentum without making the plan feel heavy.',
    OnboardingExperienceLevel.regular =>
      'giving your routine more direction and better feedback.',
    OnboardingExperienceLevel.established =>
      'sharpening what you already do so your effort has a clearer purpose.',
    null => 'keeping the first plan simple and easy to adjust.',
  };
}

String _activityObservation(OnboardingActivityLevel? activity) {
  return switch (activity) {
    OnboardingActivityLevel.mostlySitting =>
      'most of your day sounds fairly still, so the plan should ease you into movement.',
    OnboardingActivityLevel.lightlyActive =>
      'you already have a little movement in your day, which gives us a useful base.',
    OnboardingActivityLevel.moderatelyActive =>
      'you already move regularly, so the plan can build on that without overcomplicating it.',
    OnboardingActivityLevel.veryActive =>
      'your day already asks a lot from you, so the plan should respect your energy.',
    OnboardingActivityLevel.changesALot =>
      'your weeks change a lot, so the plan needs room to bend.',
    null => 'your week needs a plan that can adapt.',
  };
}

String _timeObservation(int? minutes) {
  return switch (minutes) {
    20 => '20 minutes at a time',
    30 => '30 minutes at a time',
    45 => '45 minutes at a time',
    60 => 'about an hour at a time',
    _ => 'a realistic training window',
  };
}

String _trainingObservation(OnboardingTrainingPreference? preference) {
  return switch (preference) {
    OnboardingTrainingPreference.gym => 'a gym setting',
    OnboardingTrainingPreference.home => 'home workouts',
    OnboardingTrainingPreference.bodyweight => 'simple bodyweight sessions',
    OnboardingTrainingPreference.mixed => 'a mix of training styles',
    OnboardingTrainingPreference.unsure =>
      'some room to figure out what you enjoy',
    null => 'a simple starting point',
  };
}

String _realisticResponse(OnboardingAnswersDto answers) {
  if (answers.activityLevel == OnboardingActivityLevel.changesALot) {
    return 'backup options for busy days, so one messy week does not break the routine.';
  }
  if (answers.trainingPreference == OnboardingTrainingPreference.unsure) {
    return 'a simple starting point that helps you learn what fits.';
  }
  return switch (answers.availableTimeMin) {
    20 => 'short sessions that feel focused, not rushed.',
    30 =>
      'sessions that are simple enough to repeat and long enough to feel useful.',
    45 => 'balanced sessions with enough room to make steady progress.',
    60 =>
      'complete sessions that still leave enough energy for the rest of your day.',
    _ => 'a flexible weekly rhythm instead of a rigid schedule.',
  };
}

String _goalTitle(OnboardingFitnessGoal? goal) {
  return switch (goal) {
    OnboardingFitnessGoal.buildMuscle => 'Build muscle',
    OnboardingFitnessGoal.getStronger => 'Get stronger',
    OnboardingFitnessGoal.loseWeight => 'Lose weight',
    OnboardingFitnessGoal.feelFitter => 'Feel fitter',
    OnboardingFitnessGoal.stayConsistent => 'Stay consistent',
    null => 'Build a routine',
  };
}

String _goalSentence(OnboardingFitnessGoal? goal) {
  return switch (goal) {
    OnboardingFitnessGoal.buildMuscle => 'build muscle',
    OnboardingFitnessGoal.getStronger => 'get stronger',
    OnboardingFitnessGoal.loseWeight => 'lose weight',
    OnboardingFitnessGoal.feelFitter => 'feel fitter',
    OnboardingFitnessGoal.stayConsistent => 'stay consistent',
    null => 'build a routine',
  };
}

String _motivationSummary(OnboardingMotivation? motivation) {
  return switch (motivation) {
    OnboardingMotivation.feelBetter => 'you want to feel better day to day',
    OnboardingMotivation.moreEnergy => 'you want more energy',
    OnboardingMotivation.lookDifferent => 'visible progress matters to you',
    OnboardingMotivation.moreDiscipline =>
      'you want structure you can keep coming back to',
    OnboardingMotivation.eventOrMilestone =>
      'you have something specific you want to feel ready for',
    null => 'you want a plan that feels personal',
  };
}

String _motivationChip(OnboardingMotivation? motivation) {
  return switch (motivation) {
    OnboardingMotivation.feelBetter => 'Feel better',
    OnboardingMotivation.moreEnergy => 'More energy',
    OnboardingMotivation.lookDifferent => 'Visible progress',
    OnboardingMotivation.moreDiscipline => 'More structure',
    OnboardingMotivation.eventOrMilestone => 'Milestone',
    null => 'Personal reason',
  };
}

String _experienceChip(OnboardingExperienceLevel? experience) {
  return switch (experience) {
    OnboardingExperienceLevel.justStarting => 'Just starting',
    OnboardingExperienceLevel.inconsistent => 'Rebuilding',
    OnboardingExperienceLevel.regular => 'Regular',
    OnboardingExperienceLevel.established => 'Established',
    null => 'Starting point',
  };
}

String _experiencePhrase(OnboardingExperienceLevel? experience) {
  return switch (experience) {
    OnboardingExperienceLevel.justStarting => 'a fresh starting point',
    OnboardingExperienceLevel.inconsistent =>
      'a place where momentum matters more than intensity',
    OnboardingExperienceLevel.regular =>
      'a base that is ready for more direction',
    OnboardingExperienceLevel.established =>
      'an existing routine that can be sharpened',
    null => 'a starting point we can adjust as we learn',
  };
}

String _activityTitle(OnboardingActivityLevel? activity) {
  return switch (activity) {
    OnboardingActivityLevel.mostlySitting => 'Mostly sitting',
    OnboardingActivityLevel.lightlyActive => 'Lightly active',
    OnboardingActivityLevel.moderatelyActive => 'Moderately active',
    OnboardingActivityLevel.veryActive => 'Very active',
    OnboardingActivityLevel.changesALot => 'Changes a lot',
    null => '',
  };
}

String _dietaryPreferenceTitle(OnboardingDietaryPreference? preference) {
  return switch (preference) {
    OnboardingDietaryPreference.simple => 'Keep food simple',
    OnboardingDietaryPreference.protein => 'Help me eat more protein',
    OnboardingDietaryPreference.calories => 'Help me manage calories',
    OnboardingDietaryPreference.mealPlanning => 'Help me plan meals',
    OnboardingDietaryPreference.notNow => 'Not right now',
    null => '',
  };
}

String _activitySummaryPhrase(OnboardingActivityLevel? activity) {
  return switch (activity) {
    OnboardingActivityLevel.mostlySitting =>
      'your day needs a gentle entry point',
    OnboardingActivityLevel.lightlyActive =>
      'you already have a little movement to build on',
    OnboardingActivityLevel.moderatelyActive =>
      'you already move enough that structure matters more than doing more',
    OnboardingActivityLevel.veryActive =>
      'your plan needs to respect the energy your day already uses',
    OnboardingActivityLevel.changesALot =>
      'your schedule needs flexible backup options',
    null => 'your week needs a plan that can adapt',
  };
}

String _trainingPreferenceTitle(OnboardingTrainingPreference? preference) {
  return switch (preference) {
    OnboardingTrainingPreference.gym => 'Gym',
    OnboardingTrainingPreference.home => 'Home',
    OnboardingTrainingPreference.bodyweight => 'Bodyweight',
    OnboardingTrainingPreference.mixed => 'Mixed',
    OnboardingTrainingPreference.unsure => 'Still exploring',
    null => 'Flexible',
  };
}

String _trainingPreferencePhrase(OnboardingTrainingPreference? preference) {
  return switch (preference) {
    OnboardingTrainingPreference.gym => 'gym workouts',
    OnboardingTrainingPreference.home => 'home workouts',
    OnboardingTrainingPreference.bodyweight => 'simple bodyweight sessions',
    OnboardingTrainingPreference.mixed => 'a flexible mix of training styles',
    OnboardingTrainingPreference.unsure =>
      'a simple starter style while you learn what you enjoy',
    null => 'a simple training setup',
  };
}

String _availableTimeTitle(int? minutes) {
  return switch (minutes) {
    20 => '20 min',
    30 => '30 min',
    45 => '45 min',
    60 => '60 min',
    null => 'Flexible',
    _ => '$minutes min',
  };
}

String _sexTitle(OnboardingSex? sex) {
  return switch (sex) {
    OnboardingSex.female => 'Female',
    OnboardingSex.male => 'Male',
    OnboardingSex.preferNotToSay => 'Prefer not to say',
    null => '',
  };
}

UserLevel _toUserLevel(OnboardingExperienceLevel? experience) {
  return switch (experience) {
    OnboardingExperienceLevel.justStarting => UserLevel.beginner,
    OnboardingExperienceLevel.inconsistent => UserLevel.beginner,
    OnboardingExperienceLevel.regular => UserLevel.intermediate,
    OnboardingExperienceLevel.established => UserLevel.advanced,
    null => UserLevel.beginner,
  };
}

String _frequencyToTimeframe(String? frequency) {
  if (frequency == null || frequency.isEmpty) {
    return 'Flexible start';
  }
  return 'Start with $frequency';
}

String _adherenceLabel(int score) {
  if (score >= 85) {
    return 'Very repeatable';
  }
  if (score >= 70) {
    return 'Realistic';
  }
  if (score >= 55) {
    return 'Supportive';
  }
  return 'Simple';
}

class _InferenceResult {
  const _InferenceResult({
    required this.recommendedFrequency,
    required this.adherenceScore,
  });

  final String recommendedFrequency;
  final int adherenceScore;
}

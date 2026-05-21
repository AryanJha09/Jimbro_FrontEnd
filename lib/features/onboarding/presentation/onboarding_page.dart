import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/jim_button.dart';
import '../../../shared/components/jim_companion.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/models/app_models.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int currentStep = 0;

  static const _steps = [
    (
      title: 'Set your starting point',
      copy:
          'Tell Jim what kind of training you want, how experienced you are, and what should matter most in your day-to-day guidance.',
    ),
    (
      title: 'Choose how Jim coaches',
      copy:
          'Keep the feedback calm, clear, and useful. You can adjust the depth of explanations now and refine it later in Profile.',
    ),
    (
      title: 'Grow together',
      copy:
          'Jim starts soft and supportive. As your streak builds, the companion unlocks stronger armor and a more battle-ready look right alongside you.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final draftAsync = ref.watch(appDraftProvider);
    final draft = draftAsync.valueOrNull;
    if (draftAsync.isLoading && draft == null) {
      return const BackendLoadingView(message: 'Loading onboarding...');
    }
    if (draftAsync.hasError && draft == null) {
      return BackendErrorView(
        error: draftAsync.error!,
        onRetry: () => ref.invalidate(appDraftProvider),
      );
    }
    if (draft == null) {
      return const BackendLoadingView(message: 'Preparing onboarding...');
    }
    final controller = ref.read(appDraftProvider.notifier);
    final theme = Theme.of(context);
    final step = _steps[currentStep];
    final stagePreview = switch (currentStep) {
      0 => JimCompanionStage.softBase,
      1 => JimCompanionStage.activeBase,
      _ => JimCompanionStage.armored1,
    };

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
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(JimSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Row(
                children: List.generate(
                  _steps.length,
                  (index) => Expanded(
                    child: AnimatedContainer(
                      duration: JimMotion.gentle,
                      margin: EdgeInsets.only(
                        right: index == _steps.length - 1 ? 0 : 8,
                      ),
                      height: 4,
                      decoration: BoxDecoration(
                        color: index <= currentStep
                            ? JimColors.accentStrong
                            : JimColors.accentSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: JimCompanionAvatar(
                  stage: stagePreview,
                  size: 122,
                  showLabel: true,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                'ONBOARDING',
                style: theme.textTheme.labelLarge?.copyWith(
                  letterSpacing: 1.5,
                  color: JimColors.inkMuted,
                ),
              ),
              const SizedBox(height: 12),
              Text(step.title, style: theme.textTheme.displaySmall),
              const SizedBox(height: 16),
              Text(
                step.copy,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: JimColors.inkSoft,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              JimSurface(
                radius: 34,
                child: switch (currentStep) {
                  0 => _TrainingSetup(
                      profile: draft.profile,
                      onGoalChanged: (goal) => controller.updateProfile(
                        draft.profile.copyWith(goal: goal),
                      ),
                      onLevelChanged: (level) => controller.updateProfile(
                        draft.profile.copyWith(userLevel: level),
                      ),
                    ),
                  1 => _CoachingSetup(
                      profile: draft.profile,
                      onPreferenceChanged: (preference) =>
                          controller.updateProfile(
                        draft.profile.copyWith(
                          coachingPreference: preference,
                        ),
                      ),
                      onVoiceLoggingChanged: (value) =>
                          controller.updateProfile(
                        draft.profile.copyWith(prefersVoiceLogging: value),
                      ),
                    ),
                  _ => _EvolutionPreview(consistency: draft.consistency),
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (currentStep > 0)
                    Expanded(
                      child: JimSecondaryButton(
                        label: 'Back',
                        onPressed: () => setState(() => currentStep -= 1),
                      ),
                    ),
                  if (currentStep > 0) const SizedBox(width: 12),
                  Expanded(
                    child: JimPrimaryButton(
                      label: currentStep == _steps.length - 1
                          ? 'Enter JimBro'
                          : 'Continue',
                      onPressed: () {
                        if (currentStep == _steps.length - 1) {
                          ref
                              .read(hasCompletedOnboardingProvider.notifier)
                              .state = true;
                        } else {
                          setState(() => currentStep += 1);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingSetup extends StatelessWidget {
  const _TrainingSetup({
    required this.profile,
    required this.onGoalChanged,
    required this.onLevelChanged,
  });

  final UserProfile profile;
  final ValueChanged<String> onGoalChanged;
  final ValueChanged<UserLevel> onLevelChanged;

  static const _goalOptions = [
    'Lean muscle gain',
    'Strength first',
    'Body recomposition',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Training direction',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: profile.goal,
          items: _goalOptions
              .map((goal) => DropdownMenuItem(value: goal, child: Text(goal)))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onGoalChanged(value);
            }
          },
          decoration: const InputDecoration(
            labelText: 'Goal',
            prefixIcon: Icon(Icons.flag_outlined),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<UserLevel>(
          initialValue: profile.userLevel,
          items: UserLevel.values
              .map(
                (level) => DropdownMenuItem(
                  value: level,
                  child: Text(level.name),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onLevelChanged(value);
            }
          },
          decoration: const InputDecoration(
            labelText: 'Experience level',
            prefixIcon: Icon(Icons.stacked_line_chart_rounded),
          ),
        ),
      ],
    );
  }
}

class _CoachingSetup extends StatelessWidget {
  const _CoachingSetup({
    required this.profile,
    required this.onPreferenceChanged,
    required this.onVoiceLoggingChanged,
  });

  final UserProfile profile;
  final ValueChanged<String> onPreferenceChanged;
  final ValueChanged<bool> onVoiceLoggingChanged;

  static const _coachingOptions = [
    'Contextual + concise',
    'Science-first explanations',
    'Performance-first summaries',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Coaching shape',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: profile.coachingPreference,
          items: _coachingOptions
              .map(
                (option) => DropdownMenuItem(
                  value: option,
                  child: Text(option),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onPreferenceChanged(value);
            }
          },
          decoration: const InputDecoration(
            labelText: 'Feedback style',
            prefixIcon: Icon(Icons.psychology_alt_outlined),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: profile.prefersVoiceLogging,
          onChanged: onVoiceLoggingChanged,
          title: const Text('Prioritize voice logging'),
          subtitle: const Text(
            'Keep voice entry visible as a primary capture option.',
          ),
        ),
      ],
    );
  }
}

class _EvolutionPreview extends StatelessWidget {
  const _EvolutionPreview({
    required this.consistency,
  });

  final ConsistencyState consistency;

  @override
  Widget build(BuildContext context) {
    final stages = JimCompanionStage.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Evolution preview',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: stages
              .map(
                (stage) => JimSurface(
                  padding: const EdgeInsets.all(JimSpacing.md),
                  backgroundColor: stage == consistency.companionStage
                      ? JimColors.accentSoft
                      : JimColors.galleryWhite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      JimCompanionAvatar(stage: stage, size: 76),
                      const SizedBox(height: 8),
                      Text(stage.name),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/notifications/workout_notification_service.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../atlas/presentation/atlas_chat_page.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/jim_button.dart';
import '../../../shared/components/jim_companion.dart';
import '../../../shared/components/jim_page_scaffold.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/models/app_models.dart';
import '../../../shared/models/atlas_insight.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftAsync = ref.watch(appDraftProvider);

    return draftAsync.when(
      loading: () => const BackendLoadingView(message: 'Loading home...'),
      error: (error, stackTrace) => BackendErrorView(
        error: error,
        onRetry: () => ref.invalidate(appDraftProvider),
      ),
      data: (draft) => _HomePageContent(draft: draft),
    );
  }
}

class _HomePageContent extends ConsumerWidget {
  const _HomePageContent({
    required this.draft,
  });

  final AppDraftState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(atlasHomeInsightsProvider);
    final agentContext = draft.session?.provider == 'mock'
        ? AgentContextSnapshot.empty
        : ref.watch(agentContextProvider).valueOrNull;
    final displayDraft = _dashboardDraft(draft, agentContext);
    final todaySchedule = _todaySchedule(displayDraft);
    final hasWorkout = _hasWorkoutPlan(displayDraft);
    final primaryLabel = todaySchedule != null
        ? 'Start scheduled workout'
        : hasWorkout
            ? 'Start today\'s workout'
            : 'Create workout plan';

    void openTab(int index) {
      ref.read(currentTabProvider.notifier).state = index;
    }

    Future<void> startPrimary() async {
      if (todaySchedule != null) {
        await ref
            .read(appDraftProvider.notifier)
            .startScheduledWorkout(todaySchedule);
      }
      openTab(1);
    }

    return JimPageScaffold(
      eyebrow: 'HOME',
      title: _greetingFor(displayDraft.profile),
      subtitle: 'One clear next step for today.',
      children: [
        _HeroSection(
          focus: _todayFocus(displayDraft),
          primaryLabel: primaryLabel,
          onPrimaryPressed: () {
            startPrimary();
          },
        ),
        const SizedBox(height: JimSpacing.ml),
        _WorkoutPrompt(
          draft: displayDraft,
          hasWorkout: hasWorkout,
          todaySchedule: todaySchedule,
          onTap: () => openTab(1),
        ),
        const SizedBox(height: JimSpacing.md),
        _DashboardInsights(
          draft: displayDraft,
          agentContext: agentContext,
          onWorkoutTap: () => openTab(1),
          onNutritionTap: () => openTab(2),
        ),
        const SizedBox(height: JimSpacing.md),
        _NutritionSnapshot(
          summary: displayDraft.nutritionSummary,
          onLogFood: () => openTab(2),
        ),
        const SizedBox(height: JimSpacing.md),
        const _AtlasEntryPoint(),
        const SizedBox(height: JimSpacing.md),
        _InsightSnapshot(insightsAsync: insightsAsync),
      ],
    );
  }
}

class _AtlasEntryPoint extends StatelessWidget {
  const _AtlasEntryPoint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return JimInteractiveSurface(
      onTap: () => Navigator.of(context).pushNamed(AtlasChatPage.routeName),
      tone: JimSurfaceTone.accent,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: JimColors.plaque,
              borderRadius: BorderRadius.circular(JimRadius.md),
              border: Border.all(color: JimColors.accentLine),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: JimColors.accentStrong,
            ),
          ),
          const SizedBox(width: JimSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ask ATLAS', style: theme.textTheme.titleMedium),
                const SizedBox(height: JimSpacing.xxs),
                Text(
                  'Training and nutrition guidance in a coach-like chat.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: JimColors.inkSoft,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: JimSpacing.sm),
          const Icon(Icons.chevron_right_rounded, color: JimColors.inkMuted),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.focus,
    required this.primaryLabel,
    required this.onPrimaryPressed,
  });

  final String focus;
  final String primaryLabel;
  final VoidCallback onPrimaryPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return JimSurface(
      tone: JimSurfaceTone.accent,
      radius: JimRadius.hero,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const JimCompanionAvatar(
                stage: JimCompanionStage.softBase,
                size: 64,
              ),
              const SizedBox(width: JimSpacing.sm),
              Expanded(
                child: Text(
                  'Today\'s focus',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: JimColors.accentStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: JimSpacing.lg),
          Text(
            focus,
            style: theme.textTheme.headlineSmall?.copyWith(height: 1.12),
          ),
          const SizedBox(height: JimSpacing.lg),
          JimPrimaryButton(
            label: primaryLabel,
            icon: Icons.arrow_forward_rounded,
            onPressed: onPrimaryPressed,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _WorkoutPrompt extends StatelessWidget {
  const _WorkoutPrompt({
    required this.draft,
    required this.hasWorkout,
    required this.todaySchedule,
    required this.onTap,
  });

  final AppDraftState draft;
  final bool hasWorkout;
  final WorkoutScheduleEntry? todaySchedule;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workout = _bestWorkoutName(draft);
    final exerciseCount = _bestExerciseCount(draft);
    final title = todaySchedule != null
        ? 'Scheduled today'
        : hasWorkout
            ? 'Start today\'s workout'
            : 'Plan your first workout';
    final body = todaySchedule != null
        ? '${todaySchedule!.templateName} • ${todaySchedule!.timeLabel} • repeats weekly'
        : hasWorkout
            ? [
                workout.isEmpty ? 'Workout ready' : workout,
                if (exerciseCount > 0)
                  '$exerciseCount ${exerciseCount == 1 ? 'exercise' : 'exercises'}',
              ].join(' • ')
            : 'Create a simple template you can repeat this week.';

    return JimInteractiveSurface(
      onTap: onTap,
      child: Row(
        children: [
          _IconBox(
            icon: todaySchedule != null || hasWorkout
                ? Icons.play_arrow_rounded
                : Icons.add_task_rounded,
          ),
          const SizedBox(width: JimSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: JimSpacing.xxs),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: JimColors.inkSoft,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: JimSpacing.sm),
          const Icon(Icons.chevron_right_rounded, color: JimColors.inkMuted),
        ],
      ),
    );
  }
}

class _DashboardInsights extends StatelessWidget {
  const _DashboardInsights({
    required this.draft,
    required this.agentContext,
    required this.onWorkoutTap,
    required this.onNutritionTap,
  });

  final AppDraftState draft;
  final AgentContextSnapshot? agentContext;
  final VoidCallback onWorkoutTap;
  final VoidCallback onNutritionTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _dashboardMetrics(draft, agentContext);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricGrid(
          cards: [
            _MetricCardData(
              icon: Icons.event_available_rounded,
              label: 'Workouts this week',
              value: metrics.workoutsThisWeek.toString(),
              detail: metrics.hasCompletedWorkout
                  ? 'From saved workout logs'
                  : 'Log a finished session to start tracking.',
              onTap: onWorkoutTap,
            ),
            _MetricCardData(
              icon: Icons.local_fire_department_rounded,
              label: 'Training streak',
              value: '${draft.consistency.currentStreak}d',
              detail: draft.consistency.currentStreak > 0
                  ? 'Longest: ${draft.consistency.longestStreak} days'
                  : 'One logged action starts the streak.',
              onTap: onWorkoutTap,
            ),
            _MetricCardData(
              icon: Icons.trending_up_rounded,
              label: 'Recent volume',
              value: metrics.hasVolumeData
                  ? '${metrics.totalVolumeKg.toStringAsFixed(0)} kg'
                  : 'No data',
              detail: metrics.hasVolumeData
                  ? metrics.volumeDetail
                  : 'Add reps and weight during a workout.',
              onTap: onWorkoutTap,
            ),
            _MetricCardData(
              icon: Icons.schedule_rounded,
              label: 'Next workout',
              value: metrics.nextWorkoutValue,
              detail: metrics.nextWorkoutDetail,
              onTap: onWorkoutTap,
            ),
          ],
        ),
        const SizedBox(height: JimSpacing.md),
        _WorkoutVolumePanel(
          metrics: metrics,
          onWorkoutTap: onWorkoutTap,
        ),
        const SizedBox(height: JimSpacing.md),
        _NutritionAdherencePanel(
          draft: draft,
          metrics: metrics,
          onNutritionTap: onNutritionTap,
        ),
        const SizedBox(height: JimSpacing.md),
        _CoachingInsightText(metrics: metrics),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.cards,
  });

  final List<_MetricCardData> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = JimSpacing.sm;
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(
                width: width,
                child: _MetricCard(card: card),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCardData {
  const _MetricCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final VoidCallback onTap;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.card,
  });

  final _MetricCardData card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return JimInteractiveSurface(
      onTap: card.onTap,
      padding: const EdgeInsets.all(JimSpacing.md),
      child: SizedBox(
        height: 154 + ((textScale - 1).clamp(0, 1).toDouble() * 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(card.icon, color: JimColors.accentStrong, size: 22),
            const SizedBox(height: JimSpacing.sm),
            Text(
              card.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: JimColors.inkSoft,
              ),
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                card.value,
                maxLines: 1,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: JimSpacing.xs),
            Text(
              card.detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: JimColors.inkMuted,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutVolumePanel extends StatelessWidget {
  const _WorkoutVolumePanel({
    required this.metrics,
    required this.onWorkoutTap,
  });

  final _DashboardMetrics metrics;
  final VoidCallback onWorkoutTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return JimSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBox(icon: Icons.bar_chart_rounded),
              const SizedBox(width: JimSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Workout progression',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: JimSpacing.xxs),
                    Text(
                      metrics.hasVolumeData
                          ? metrics.volumePanelDescription
                          : 'Finish a workout with reps and weight to see progression.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: JimColors.inkSoft,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: JimSpacing.md),
          if (metrics.hasVolumeData)
            _VolumeBars(exercises: metrics.exerciseVolumes)
          else
            _InlineEmptyState(
              title: 'No volume trend yet',
              message:
                  'Start from a template, enter set weights, then finish the workout.',
              actionLabel: 'Log workout',
              onAction: onWorkoutTap,
            ),
        ],
      ),
    );
  }
}

class _VolumeBars extends StatelessWidget {
  const _VolumeBars({
    required this.exercises,
  });

  final List<_ExerciseVolume> exercises;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = exercises.take(4).toList(growable: false);
    final maxVolume = visible.fold<double>(
      0,
      (maxValue, item) => item.volumeKg > maxValue ? item.volumeKg : maxValue,
    );

    return Column(
      children: [
        for (final exercise in visible) ...[
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  exercise.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: JimSpacing.sm),
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(JimRadius.pill),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: maxVolume <= 0
                        ? 0
                        : (exercise.volumeKg / maxVolume).clamp(0, 1),
                    backgroundColor: JimColors.accentSoft,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      JimColors.accentStrong,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: JimSpacing.sm),
              SizedBox(
                width: 64,
                child: Text(
                  '${exercise.volumeKg.toStringAsFixed(0)} kg',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: JimColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          if (exercise != visible.last) const SizedBox(height: JimSpacing.sm),
        ],
      ],
    );
  }
}

class _NutritionAdherencePanel extends StatelessWidget {
  const _NutritionAdherencePanel({
    required this.draft,
    required this.metrics,
    required this.onNutritionTap,
  });

  final AppDraftState draft;
  final _DashboardMetrics metrics;
  final VoidCallback onNutritionTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = draft.nutritionSummary;
    final hasTargets = summary.targetCalories > 0 || summary.proteinTarget > 0;
    final hasFood = summary.consumedCalories > 0 ||
        summary.proteinConsumed > 0 ||
        summary.carbsConsumed > 0 ||
        summary.fatConsumed > 0;

    return JimSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBox(icon: Icons.fact_check_outlined),
              const SizedBox(width: JimSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nutrition adherence',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: JimSpacing.xxs),
                    Text(
                      metrics.nutritionAdherenceDetail,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: JimColors.inkSoft,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: JimSpacing.md),
          if (hasTargets || hasFood) ...[
            _ProgressLine(
              label: 'Calories today',
              value: summary.targetCalories > 0
                  ? '${summary.consumedCalories.toStringAsFixed(0)} / ${summary.targetCalories.toStringAsFixed(0)} kcal'
                  : '${summary.consumedCalories.toStringAsFixed(0)} kcal logged',
              progress: _safeProgress(
                summary.consumedCalories,
                summary.targetCalories,
              ),
            ),
            const SizedBox(height: JimSpacing.sm),
            _ProgressLine(
              label: 'Protein today',
              value: summary.proteinTarget > 0
                  ? '${summary.proteinConsumed.toStringAsFixed(0)} / ${summary.proteinTarget.toStringAsFixed(0)} g'
                  : '${summary.proteinConsumed.toStringAsFixed(0)} g logged',
              progress: _safeProgress(
                summary.proteinConsumed,
                summary.proteinTarget,
              ),
            ),
          ] else
            _InlineEmptyState(
              title: 'No nutrition signal yet',
              message:
                  'Log one meal or finish profile setup to unlock calorie and protein targets.',
              actionLabel: 'Log food',
              onAction: onNutritionTap,
            ),
        ],
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: JimSpacing.xs),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: JimColors.inkSoft,
            height: 1.35,
          ),
        ),
        const SizedBox(height: JimSpacing.md),
        JimSecondaryButton(
          label: actionLabel,
          icon: Icons.arrow_forward_rounded,
          onPressed: onAction,
          expand: true,
        ),
      ],
    );
  }
}

class _CoachingInsightText extends StatelessWidget {
  const _CoachingInsightText({
    required this.metrics,
  });

  final _DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return JimSurface(
      tone: JimSurfaceTone.soft,
      padding: const EdgeInsets.all(JimSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.psychology_alt_outlined,
            color: JimColors.accentStrong,
          ),
          const SizedBox(width: JimSpacing.sm),
          Expanded(
            child: Text(
              metrics.coachingText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: JimColors.inkSoft,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NutritionSnapshot extends StatelessWidget {
  const _NutritionSnapshot({
    required this.summary,
    required this.onLogFood,
  });

  final DailyNutritionSummary summary;
  final VoidCallback onLogFood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCalories =
        summary.targetCalories > 0 || summary.consumedCalories > 0;
    final hasProtein = summary.proteinTarget > 0 || summary.proteinConsumed > 0;
    final hasHydration = summary.hydrationTargetLiters > 0 ||
        summary.hydrationConsumedLiters > 0;

    return JimSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBox(icon: Icons.ramen_dining_outlined),
              const SizedBox(width: JimSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nutrition snapshot',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: JimSpacing.xxs),
                    Text(
                      hasCalories || hasProtein || hasHydration
                          ? 'Keep the day visible without overthinking it.'
                          : 'No food logged yet. Start with one meal.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: JimColors.inkSoft,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: JimSpacing.md),
          if (hasCalories)
            _ProgressLine(
              label: 'Calories',
              value:
                  '${summary.consumedCalories.toStringAsFixed(0)} / ${summary.targetCalories.toStringAsFixed(0)} kcal',
              progress: _safeProgress(
                summary.consumedCalories,
                summary.targetCalories,
              ),
            ),
          if (hasCalories && hasProtein) const SizedBox(height: JimSpacing.sm),
          if (hasProtein)
            _ProgressLine(
              label: 'Protein',
              value:
                  '${summary.proteinConsumed.toStringAsFixed(0)} / ${summary.proteinTarget.toStringAsFixed(0)} g',
              progress: _safeProgress(
                summary.proteinConsumed,
                summary.proteinTarget,
              ),
            ),
          if ((hasCalories || hasProtein) && hasHydration)
            const SizedBox(height: JimSpacing.sm),
          if (hasHydration)
            _ProgressLine(
              label: 'Hydration',
              value:
                  '${summary.hydrationConsumedLiters.toStringAsFixed(1)} / ${summary.hydrationTargetLiters.toStringAsFixed(1)} L',
              progress: _safeProgress(
                summary.hydrationConsumedLiters,
                summary.hydrationTargetLiters,
              ),
            ),
          const SizedBox(height: JimSpacing.md),
          JimSecondaryButton(
            label: 'Log food',
            icon: Icons.add_rounded,
            onPressed: onLogFood,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _InsightSnapshot extends StatelessWidget {
  const _InsightSnapshot({
    required this.insightsAsync,
  });

  final AsyncValue<List<AtlasInsight>> insightsAsync;

  @override
  Widget build(BuildContext context) {
    return insightsAsync.when(
      loading: () =>
          const JimLoadingState(message: 'Checking today\'s signal...'),
      error: (error, stackTrace) => const _InsightCard(
        title: 'Start with one logged action',
        body:
            'Once you log a workout or meal, Jim can turn the pattern into a useful next step.',
      ),
      data: (insights) {
        final insight = insights.isEmpty ? null : insights.first;
        return _InsightCard(
          title: insight?.title ?? 'Start with one logged action',
          body: insight?.mainText ??
              'Log a workout or meal today so Jim can make the next recommendation more personal.',
        );
      },
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return JimSurface(
      tone: JimSurfaceTone.soft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _IconBox(icon: Icons.lightbulb_outline_rounded),
          const SizedBox(width: JimSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: JimSpacing.xs),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: JimColors.inkSoft,
                    height: 1.45,
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

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.value,
    required this.progress,
  });

  final String label;
  final String value;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useStackedLabels = MediaQuery.textScalerOf(context).scale(1) > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (useStackedLabels)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: JimSpacing.xxs),
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: JimColors.inkSoft,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: JimColors.inkSoft,
                ),
              ),
            ],
          ),
        const SizedBox(height: JimSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(JimRadius.pill),
          child: LinearProgressIndicator(
            minHeight: 9,
            value: progress.clamp(0, 1),
            backgroundColor: JimColors.accentSoft,
            valueColor: const AlwaysStoppedAnimation<Color>(
              JimColors.accentStrong,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({
    required this.icon,
  });

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: JimColors.accentSoft,
        borderRadius: BorderRadius.circular(JimRadius.md),
        border: Border.all(color: JimColors.accentLine),
      ),
      child: Icon(icon, color: JimColors.accentStrong),
    );
  }
}

AppDraftState _dashboardDraft(
  AppDraftState draft,
  AgentContextSnapshot? context,
) {
  if (context == null || !context.hasLiveData) {
    return draft;
  }
  final metrics = context.atlasMetrics ?? draft.metrics;
  final backendSummary = context.todaysNutrition;
  final baseSummary = backendSummary ?? draft.nutritionSummary;
  final nutritionSummary = baseSummary.copyWith(
    targetCalories: metrics.targetCalories > 0
        ? metrics.targetCalories
        : baseSummary.targetCalories,
    proteinTarget:
        metrics.proteinG > 0 ? metrics.proteinG : baseSummary.proteinTarget,
    carbsTarget: metrics.carbsG > 0 ? metrics.carbsG : baseSummary.carbsTarget,
    fatTarget: metrics.fatG > 0 ? metrics.fatG : baseSummary.fatTarget,
    hydrationTargetLiters: metrics.hydrationL > 0
        ? metrics.hydrationL
        : baseSummary.hydrationTargetLiters,
  );
  final activeTemplate =
      !_hasWorkoutPlan(draft) && context.activeTemplate != null
          ? context.activeTemplate!
          : draft.template;
  final latestWorkout = context.recentWorkouts.isEmpty
      ? draft.workoutLog
      : _latestWorkout(context.recentWorkouts);

  return draft.copyWith(
    profile: draft.profile,
    metrics: metrics,
    template: activeTemplate,
    workoutLog: latestWorkout,
    nutritionSummary: nutritionSummary,
  );
}

WorkoutLogDraft _latestWorkout(List<WorkoutLogDraft> workouts) {
  final sorted = workouts.toList(growable: false)
    ..sort((a, b) {
      final aDate = _parseDate(a.endedAtLabel) ??
          _parseDate(a.startedAtLabel) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = _parseDate(b.endedAtLabel) ??
          _parseDate(b.startedAtLabel) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
  return sorted.first;
}

String _greetingFor(UserProfile profile) {
  final name = profile.name.trim();
  if (name.isEmpty || name == 'JimBro User') {
    return 'Hey there';
  }
  return 'Hey $name';
}

String _todayFocus(AppDraftState draft) {
  final scheduled = _todaySchedule(draft);
  if (scheduled != null) {
    return '${weekdayName(scheduled.weekday)} is set for ${scheduled.templateName}. Start around ${scheduled.timeLabel} when you are ready.';
  }
  if (_hasWorkoutPlan(draft)) {
    final exerciseCount = _bestExerciseCount(draft);
    final workoutName = _bestWorkoutName(draft);
    final planName = workoutName.isEmpty ? 'your workout' : workoutName;
    final exerciseText = exerciseCount > 0
        ? ' Log $exerciseCount ${exerciseCount == 1 ? 'exercise' : 'exercises'} with clean reps.'
        : '';
    return 'Start $planName today.$exerciseText';
  }
  if (draft.nutritionSummary.consumedCalories > 0 ||
      draft.nutritionSummary.proteinConsumed > 0) {
    return 'You have started logging food. Add a simple workout plan next.';
  }
  return 'Build one simple plan, then log the first meal or workout.';
}

bool _hasWorkoutPlan(AppDraftState draft) {
  return _bestExerciseCount(draft) > 0 || _bestWorkoutName(draft).isNotEmpty;
}

WorkoutScheduleEntry? _todaySchedule(AppDraftState draft) {
  final weekday = DateTime.now().weekday;
  for (final entry in draft.workoutSchedule) {
    if (entry.active && entry.repeatWeekly && entry.weekday == weekday) {
      return entry;
    }
  }
  return null;
}

String _bestWorkoutName(AppDraftState draft) {
  final logName = draft.workoutLog.name.trim();
  if (logName.isNotEmpty) {
    return logName;
  }
  return draft.template.name.trim();
}

int _bestExerciseCount(AppDraftState draft) {
  if (draft.workoutLog.exercises.isNotEmpty) {
    return draft.workoutLog.exercises.length;
  }
  return draft.template.exercises.length;
}

double _safeProgress(double consumed, double target) {
  if (target <= 0) {
    return consumed > 0 ? 1 : 0;
  }
  return consumed / target;
}

_DashboardMetrics _dashboardMetrics(
  AppDraftState draft,
  AgentContextSnapshot? context,
) {
  final recentWorkouts = context?.recentWorkouts ?? const <WorkoutLogDraft>[];
  final completedRecent =
      recentWorkouts.where(_isSavedWorkoutRecord).toList(growable: false);
  final latestLog = completedRecent.isEmpty
      ? draft.workoutLog
      : _latestWorkout(completedRecent);
  final hasCompletedWorkout =
      completedRecent.isNotEmpty || _isCompletedWorkoutLog(latestLog);
  final workoutsThisWeek = completedRecent.isNotEmpty
      ? completedRecent
          .where((log) => _dateIsThisWeek(_parseDate(log.endedAtLabel)))
          .length
      : hasCompletedWorkout &&
              _dateIsThisWeek(_parseDate(latestLog.endedAtLabel))
          ? 1
          : 0;
  final trends = context?.workoutTrends ?? WorkoutTrendSummary.empty;
  final latestExerciseVolumes = _exerciseVolumes(latestLog);
  final exerciseVolumes = trends.points.isNotEmpty
      ? trends.points
          .where((point) => point.volumeKg > 0)
          .map(
            (point) => _ExerciseVolume(
              name: point.label.trim().isEmpty ? 'Training' : point.label,
              volumeKg: point.volumeKg,
            ),
          )
          .toList(growable: false)
      : trends.totalVolumeKg > 0
          ? <_ExerciseVolume>[
              _ExerciseVolume(
                name: 'Last ${trends.rollingDays} days',
                volumeKg: trends.totalVolumeKg,
              ),
            ]
          : latestExerciseVolumes;
  final calculatedVolume = exerciseVolumes.fold<double>(
    0,
    (total, exercise) => total + exercise.volumeKg,
  );
  final totalVolumeKg =
      trends.totalVolumeKg > 0 ? trends.totalVolumeKg : calculatedVolume;
  final latestCompletedSets = latestLog.exercises.fold<int>(
    0,
    (total, exercise) =>
        total +
        exercise.sets.where((set) => set.reps > 0 || set.weightKg > 0).length,
  );
  final completedSets =
      trends.completedSets > 0 ? trends.completedSets : latestCompletedSets;
  final nextSchedule = _nextSchedule(draft.workoutSchedule);
  final summary = draft.nutritionSummary;
  final hasTargets = summary.targetCalories > 0 || summary.proteinTarget > 0;
  final hasFood = summary.consumedCalories > 0 ||
      summary.proteinConsumed > 0 ||
      summary.carbsConsumed > 0 ||
      summary.fatConsumed > 0;
  final caloriesOnTrack = summary.targetCalories > 0 &&
      summary.consumedCalories >= summary.targetCalories * 0.7 &&
      summary.consumedCalories <= summary.targetCalories * 1.15;
  final proteinOnTrack = summary.proteinTarget > 0 &&
      summary.proteinConsumed >= summary.proteinTarget * 0.75;
  final weeklyCheckins = draft.consistency.weeklyCheckins.clamp(0, 7);

  final nutritionAdherenceDetail = weeklyCheckins > 0
      ? '$weeklyCheckins of 7 logged days this week. Today uses food logs plus profile targets.'
      : hasTargets || hasFood
          ? 'Today has ${hasFood ? 'food logged' : 'targets ready'}; weekly food history is not available yet.'
          : 'Targets and logged meals will appear after profile setup or the first food log.';

  final coachingText = _coachingText(
    hasCompletedWorkout: hasCompletedWorkout,
    hasVolumeData: totalVolumeKg > 0,
    hasTargets: hasTargets,
    hasFood: hasFood,
    caloriesOnTrack: caloriesOnTrack,
    proteinOnTrack: proteinOnTrack,
    nextSchedule: nextSchedule,
  );

  return _DashboardMetrics(
    workoutsThisWeek: workoutsThisWeek,
    hasCompletedWorkout: hasCompletedWorkout,
    exerciseVolumes: exerciseVolumes,
    totalVolumeKg: totalVolumeKg,
    completedSets: completedSets,
    volumeDetail: trends.hasData
        ? '$completedSets completed sets across ${trends.rollingDays} days'
        : '$completedSets completed sets in latest workout',
    volumePanelDescription: trends.hasData
        ? 'Rolling ${trends.rollingDays}-day workout volume from saved logs.'
        : 'Latest completed workout volume by exercise.',
    nextWorkoutValue:
        nextSchedule == null ? 'Not set' : _shortTemplateName(nextSchedule),
    nextWorkoutDetail: nextSchedule == null
        ? 'Schedule a saved template.'
        : '${weekdayName(nextSchedule.weekday)} at ${nextSchedule.timeLabel}',
    nutritionAdherenceDetail: nutritionAdherenceDetail,
    coachingText: coachingText,
  );
}

String _coachingText({
  required bool hasCompletedWorkout,
  required bool hasVolumeData,
  required bool hasTargets,
  required bool hasFood,
  required bool caloriesOnTrack,
  required bool proteinOnTrack,
  required WorkoutScheduleEntry? nextSchedule,
}) {
  if (!hasCompletedWorkout && !hasFood) {
    return 'Start small: create one repeatable workout and log one meal. Jim will turn those first signals into better coaching.';
  }
  if (nextSchedule == null && hasCompletedWorkout) {
    return 'Good first workout signal. Put the next session on the weekly schedule so momentum has a place to land.';
  }
  if (hasVolumeData && hasTargets && caloriesOnTrack && proteinOnTrack) {
    return 'Training and nutrition are both visible today. Repeat this setup before adding complexity.';
  }
  if (hasTargets && !proteinOnTrack) {
    return 'Protein is the easiest nutrition lever today. Add one high-protein meal before chasing smaller details.';
  }
  if (!hasVolumeData && hasCompletedWorkout) {
    return 'Next workout, add reps and weight to each set. That unlocks real progression instead of guesswork.';
  }
  return 'You have enough signal for today. Keep the next action simple and log it when done.';
}

bool _isCompletedWorkoutLog(WorkoutLogDraft log) {
  return log.name.trim().isNotEmpty &&
      log.startedAtLabel.trim().isNotEmpty &&
      log.endedAtLabel.trim().isNotEmpty &&
      log.exercises.isNotEmpty;
}

bool _isSavedWorkoutRecord(WorkoutLogDraft log) {
  return log.name.trim().isNotEmpty && log.endedAtLabel.trim().isNotEmpty;
}

bool _dateIsThisWeek(DateTime? date) {
  if (date == null) {
    return false;
  }
  final now = DateTime.now();
  final weekStart = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - DateTime.monday));
  final nextWeekStart = weekStart.add(const Duration(days: 7));
  return !date.isBefore(weekStart) && date.isBefore(nextWeekStart);
}

DateTime? _parseDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return DateTime.tryParse(trimmed);
}

List<_ExerciseVolume> _exerciseVolumes(WorkoutLogDraft log) {
  if (!_isCompletedWorkoutLog(log)) {
    return const [];
  }
  return log.exercises
      .map((exercise) {
        final volume = exercise.sets.fold<double>(
          0,
          (total, set) => total + set.weightKg * set.reps,
        );
        return _ExerciseVolume(
          name: exercise.exerciseName.trim().isEmpty
              ? 'Unnamed exercise'
              : exercise.exerciseName.trim(),
          volumeKg: volume,
        );
      })
      .where((exercise) => exercise.volumeKg > 0)
      .toList(growable: false);
}

WorkoutScheduleEntry? _nextSchedule(List<WorkoutScheduleEntry> schedule) {
  final active = schedule
      .where((entry) => entry.active && entry.repeatWeekly)
      .toList(growable: false);
  if (active.isEmpty) {
    return null;
  }
  final today = DateTime.now().weekday;
  active.sort((a, b) {
    final aDistance = (a.weekday - today) % 7;
    final bDistance = (b.weekday - today) % 7;
    if (aDistance != bDistance) {
      return aDistance.compareTo(bDistance);
    }
    return a.timeLabel.compareTo(b.timeLabel);
  });
  return active.first;
}

String _shortTemplateName(WorkoutScheduleEntry entry) {
  final name = entry.templateName.trim();
  if (name.isEmpty) {
    return 'Workout';
  }
  return name.length <= 14 ? name : '${name.substring(0, 13)}...';
}

class _DashboardMetrics {
  const _DashboardMetrics({
    required this.workoutsThisWeek,
    required this.hasCompletedWorkout,
    required this.exerciseVolumes,
    required this.totalVolumeKg,
    required this.completedSets,
    required this.volumeDetail,
    required this.volumePanelDescription,
    required this.nextWorkoutValue,
    required this.nextWorkoutDetail,
    required this.nutritionAdherenceDetail,
    required this.coachingText,
  });

  final int workoutsThisWeek;
  final bool hasCompletedWorkout;
  final List<_ExerciseVolume> exerciseVolumes;
  final double totalVolumeKg;
  final int completedSets;
  final String volumeDetail;
  final String volumePanelDescription;
  final String nextWorkoutValue;
  final String nextWorkoutDetail;
  final String nutritionAdherenceDetail;
  final String coachingText;

  bool get hasVolumeData => exerciseVolumes.isNotEmpty && totalVolumeKg > 0;
}

class _ExerciseVolume {
  const _ExerciseVolume({
    required this.name,
    required this.volumeKg,
  });

  final String name;
  final double volumeKg;
}

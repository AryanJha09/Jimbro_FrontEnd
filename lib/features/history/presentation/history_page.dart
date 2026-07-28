import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/insight_card.dart';
import '../../../shared/components/jim_companion.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/components/section_header.dart';
import '../../../shared/models/app_models.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftAsync = ref.watch(appDraftProvider);
    return draftAsync.when(
      loading: () => const BackendLoadingView(message: 'Loading history...'),
      error: (error, stackTrace) => BackendErrorView(
        error: error,
        onRetry: () => ref.invalidate(appDraftProvider),
      ),
      data: (draft) => _HistoryContent(draft: draft),
    );
  }
}

class _HistoryContent extends ConsumerWidget {
  const _HistoryContent({
    required this.draft,
  });

  final AppDraftState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consistency = draft.consistency;
    final controller = ref.read(appDraftProvider.notifier);
    final insightAsync = ref.watch(historyInsightProvider);
    final recoveryAsync = ref.watch(recoveryInsightProvider);
    final theme = Theme.of(context);
    final hasScaledText = MediaQuery.textScalerOf(context).scale(1) > 1;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [JimColors.shell, JimColors.galleryWhite, JimColors.eggshell],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            const SectionHeader(
              eyebrow: 'PROGRESSION',
              title: 'Consistency drives evolution',
            ),
            const SizedBox(height: 12),
            _CurrentStreakPill(
              days: consistency.currentStreak,
              stageLabel: _stageLabel(consistency.companionStage),
              showControls: kDebugMode,
              onDecrement: () => controller.adjustConsistency(-1),
              onIncrement: () => controller.adjustConsistency(1),
            ),
            const SizedBox(height: 18),
            _WorkoutHistoryCard(workoutLog: draft.workoutLog),
            const SizedBox(height: 16),
            _ProgressionActions(
              onLogWorkout: () =>
                  ref.read(currentTabProvider.notifier).state = 1,
            ),
            const SizedBox(height: 16),
            JimSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Companion progress', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final companion = JimCompanionAvatar(
                        stage: consistency.companionStage,
                        size: 110,
                        showLabel: true,
                      );
                      final details = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current streak',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Longest run: ${consistency.longestStreak} days\nTotal logs: ${consistency.totalLogs}',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: JimColors.inkSoft,
                            ),
                          ),
                          if (kDebugMode) ...[
                            const SizedBox(height: 12),
                            if (hasScaledText)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  OutlinedButton(
                                    onPressed: () =>
                                        controller.adjustConsistency(-1),
                                    child: const Text('-1 day'),
                                  ),
                                  const SizedBox(height: JimSpacing.xs),
                                  FilledButton(
                                    onPressed: () =>
                                        controller.adjustConsistency(1),
                                    child: const Text('+1 day'),
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          controller.adjustConsistency(-1),
                                      child: const Text('-1 day'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () =>
                                          controller.adjustConsistency(1),
                                      child: const Text('+1 day'),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ],
                      );
                      if (hasScaledText && constraints.maxWidth < 400) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(child: companion),
                            const SizedBox(height: JimSpacing.md),
                            details,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          companion,
                          const SizedBox(width: 16),
                          Expanded(child: details),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: List.generate(
                      7,
                      (index) => Expanded(
                        child: Container(
                          height: index < consistency.weeklyCheckins ? 32 : 18,
                          margin: EdgeInsets.only(right: index == 6 ? 0 : 6),
                          decoration: BoxDecoration(
                            color: index < consistency.weeklyCheckins
                                ? JimColors.accentStrong
                                : JimColors.accentSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            insightAsync.when(
              loading: () => const JimSurface(
                child: Text('Loading trend insight...'),
              ),
              error: (error, stackTrace) => JimSurface(
                child: Text('Trend insight failed: $error'),
              ),
              data: (insight) => InsightCard(insight: insight),
            ),
            const SizedBox(height: 16),
            recoveryAsync.when(
              loading: () => const JimSurface(
                child: Text('Loading recovery insight...'),
              ),
              error: (error, stackTrace) => JimSurface(
                child: Text('Recovery insight failed: $error'),
              ),
              data: (recovery) => InsightCard(insight: recovery),
            ),
          ],
        ),
      ),
    );
  }
}

String _stageLabel(JimCompanionStage stage) {
  return switch (stage) {
    JimCompanionStage.softBase => 'Soft base',
    JimCompanionStage.activeBase => 'Active base',
    JimCompanionStage.armored1 => 'Armored I',
    JimCompanionStage.armored2 => 'Armored II',
    JimCompanionStage.jackedArmorFinal => 'Jacked final',
  };
}

class _CurrentStreakPill extends StatelessWidget {
  const _CurrentStreakPill({
    required this.days,
    required this.stageLabel,
    required this.showControls,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int days;
  final String stageLabel;
  final bool showControls;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: JimColors.accentSoft,
        borderRadius: BorderRadius.circular(JimRadius.pill),
        border: Border.all(color: JimColors.accentLine),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: JimSpacing.xs,
        children: [
          Text(
            '$days day streak',
            style: theme.textTheme.labelLarge?.copyWith(
              color: JimColors.accentStrong,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            stageLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: JimColors.inkSoft,
            ),
          ),
          if (showControls) ...[
            const SizedBox(width: 8),
            _TinyStreakButton(
              key: const ValueKey('decrement-streak-button'),
              icon: Icons.remove_rounded,
              onPressed: onDecrement,
            ),
            const SizedBox(width: 6),
            _TinyStreakButton(
              key: const ValueKey('increment-streak-button'),
              icon: Icons.add_rounded,
              onPressed: onIncrement,
            ),
          ],
        ],
      ),
    );
  }
}

class _TinyStreakButton extends StatelessWidget {
  const _TinyStreakButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: JimColors.plaque,
          foregroundColor: JimColors.accentStrong,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JimRadius.pill),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _WorkoutHistoryCard extends StatelessWidget {
  const _WorkoutHistoryCard({
    required this.workoutLog,
  });

  final WorkoutLogDraft workoutLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCompletedWorkout = _isCompletedWorkoutLog(workoutLog);
    final volumes = _exerciseVolumes(workoutLog);
    final totalVolume = volumes.fold<double>(
      0,
      (total, item) => total + item.volumeKg,
    );
    final completedSets = workoutLog.exercises.fold<int>(
      0,
      (total, exercise) =>
          total +
          exercise.sets.where((set) => set.reps > 0 || set.weightKg > 0).length,
    );

    if (!hasCompletedWorkout) {
      return JimSurface(
        tone: JimSurfaceTone.soft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.show_chart_rounded, color: JimColors.inkMuted),
            const SizedBox(width: JimSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Workout history will build here',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: JimSpacing.xs),
                  Text(
                    'Finish a workout with reps and weight to unlock truthful progression signals.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: JimColors.inkSoft,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return JimSurface(
      padding: EdgeInsets.zero,
      radius: JimRadius.lg,
      backgroundColor: JimColors.plaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(JimRadius.lg),
        child: Stack(
          children: [
            const Positioned.fill(child: JimLightTexture()),
            Padding(
              padding: const EdgeInsets.all(JimSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              workoutLog.name.trim().isEmpty
                                  ? 'Latest workout'
                                  : workoutLog.name.trim(),
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              volumes.isEmpty
                                  ? 'This workout is saved. Add set weight and reps next time to unlock volume trends.'
                                  : 'Latest completed workout, summarized from saved set data.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: JimColors.inkSoft,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: JimColors.accentSoft,
                          borderRadius: BorderRadius.circular(JimRadius.md),
                          border: Border.all(color: JimColors.accentLine),
                        ),
                        child: const Icon(
                          Icons.trending_up_rounded,
                          color: JimColors.accentStrong,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _HistoryMetricGrid(
                    children: [
                      _ProgressMetricCard(
                        label: 'Logged sets',
                        value: '$completedSets',
                        icon: Icons.check_circle_outline_rounded,
                      ),
                      _ProgressMetricCard(
                        label: 'Volume',
                        value: totalVolume > 0
                            ? '${totalVolume.toStringAsFixed(0)} kg'
                            : 'No weight',
                        icon: Icons.fitness_center_rounded,
                      ),
                      _ProgressMetricCard(
                        label: 'Exercises',
                        value: '${workoutLog.exercises.length}',
                        icon: Icons.format_list_bulleted_rounded,
                      ),
                      _ProgressMetricCard(
                        label: 'Finished',
                        value: _shortDate(workoutLog.endedAtLabel),
                        icon: Icons.event_available_rounded,
                      ),
                    ],
                  ),
                  if (volumes.isNotEmpty) ...[
                    const SizedBox(height: JimSpacing.md),
                    ...volumes.take(4).map(
                          (volume) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: JimSpacing.sm),
                            child: _VolumeLine(
                              name: volume.name,
                              volumeKg: volume.volumeKg,
                              maxVolumeKg: volumes.first.volumeKg,
                            ),
                          ),
                        ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryMetricGrid extends StatelessWidget {
  const _HistoryMetricGrid({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 420;
        if (isWide) {
          return Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                Expanded(child: children[i]),
                if (i != children.length - 1)
                  const SizedBox(width: JimSpacing.sm),
              ],
            ],
          );
        }

        return Column(
          children: [
            for (var i = 0; i < children.length; i += 2) ...[
              Row(
                children: [
                  Expanded(child: children[i]),
                  const SizedBox(width: JimSpacing.sm),
                  Expanded(
                    child: i + 1 < children.length
                        ? children[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              if (i + 2 < children.length)
                const SizedBox(height: JimSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _VolumeLine extends StatelessWidget {
  const _VolumeLine({
    required this.name,
    required this.volumeKg,
    required this.maxVolumeKg,
  });

  final String name;
  final double volumeKg;
  final double maxVolumeKg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            name,
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
              value:
                  maxVolumeKg <= 0 ? 0 : (volumeKg / maxVolumeKg).clamp(0, 1),
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
            '${volumeKg.toStringAsFixed(0)} kg',
            textAlign: TextAlign.end,
            style: theme.textTheme.labelMedium?.copyWith(
              color: JimColors.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryVolume {
  const _HistoryVolume({
    required this.name,
    required this.volumeKg,
  });

  final String name;
  final double volumeKg;
}

bool _isCompletedWorkoutLog(WorkoutLogDraft log) {
  return log.name.trim().isNotEmpty &&
      log.startedAtLabel.trim().isNotEmpty &&
      log.endedAtLabel.trim().isNotEmpty &&
      log.exercises.isNotEmpty;
}

List<_HistoryVolume> _exerciseVolumes(WorkoutLogDraft log) {
  if (!_isCompletedWorkoutLog(log)) {
    return const [];
  }
  final volumes = log.exercises
      .map((exercise) {
        final volume = exercise.sets.fold<double>(
          0,
          (total, set) => total + set.weightKg * set.reps,
        );
        return _HistoryVolume(
          name: exercise.exerciseName.trim().isEmpty
              ? 'Unnamed exercise'
              : exercise.exerciseName.trim(),
          volumeKg: volume,
        );
      })
      .where((item) => item.volumeKg > 0)
      .toList(growable: false);
  volumes.sort((left, right) => right.volumeKg.compareTo(left.volumeKg));
  return volumes;
}

String _shortDate(String isoValue) {
  final parsed = DateTime.tryParse(isoValue);
  if (parsed == null) {
    return 'Saved';
  }
  return '${parsed.month}/${parsed.day}';
}

class _ProgressMetricCard extends StatelessWidget {
  const _ProgressMetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 94),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JimColors.plaque.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(JimRadius.md),
        border: Border.all(color: JimColors.insetLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: JimColors.accentStrong, size: 20),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge,
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: JimColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressionActions extends StatelessWidget {
  const _ProgressionActions({
    required this.onLogWorkout,
  });

  final VoidCallback onLogWorkout;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onLogWorkout,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log Today’s Workout'),
      ),
    );
  }
}

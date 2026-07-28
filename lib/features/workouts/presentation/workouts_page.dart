import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/navigation/app_state.dart';
import '../../../core/notifications/workout_notification_service.dart';
import '../../../core/repositories/app_repositories.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/action_state.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/jim_button.dart';
import '../../../shared/components/jim_page_scaffold.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/models/app_models.dart';
import '../application/active_workout_controller.dart';

class WorkoutsPage extends ConsumerWidget {
  const WorkoutsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftAsync = ref.watch(appDraftProvider);
    return draftAsync.when(
      loading: () => const BackendLoadingView(message: 'Loading workouts...'),
      error: (error, stackTrace) => BackendErrorView(
        error: error,
        onRetry: () => ref.invalidate(appDraftProvider),
      ),
      data: (draft) => _WorkoutsContent(draft: draft),
    );
  }
}

class _WorkoutsContent extends ConsumerWidget {
  const _WorkoutsContent({
    required this.draft,
  });

  final AppDraftState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appDraftProvider.notifier);
    final theme = Theme.of(context);
    final template = draft.template;
    final activeAsync = ref.watch(activeWorkoutProvider);
    final activeSession = activeAsync.valueOrNull?.session;

    return JimPageScaffold(
      eyebrow: 'WORKOUTS',
      title: 'Workout templates',
      subtitle:
          'Create reusable plans, open them later, then start a workout from the template.',
      headerTrailing: IconButton(
        onPressed: () async {
          await controller.createTemplateDraft();
          if (context.mounted) {
            await Navigator.of(context).pushNamed(
              '/app/workouts/templates/new',
            );
          }
        },
        icon: const Icon(Icons.add_rounded),
        tooltip: 'Create Template',
      ),
      children: [
        _TemplateLibrary(
          templates: draft.templates,
          activeTemplateId: template.templateId,
          onCreate: () async {
            await controller.createTemplateDraft();
            if (context.mounted) {
              await Navigator.of(context).pushNamed(
                '/app/workouts/templates/new',
              );
            }
          },
          onOpen: (selected) async {
            await controller.openWorkoutTemplate(selected);
            if (context.mounted && selected.templateId != null) {
              await Navigator.of(context).pushNamed(
                '/app/workouts/templates/${selected.templateId}/edit',
              );
            }
          },
          onStart: (selected) async {
            final session = await ref
                .read(activeWorkoutProvider.notifier)
                .startOrResume(selected);
            if (context.mounted) {
              await Navigator.of(context).pushNamed(
                '/app/workouts/session/${session.sessionId}',
              );
            }
          },
          onDelete: (template) async {
            await _runWorkoutAction(
              context,
              () async => controller.deleteWorkoutTemplate(template),
              successMessage: 'Workout template deleted.',
            );
          },
        ),
        if (activeSession != null) ...[
          const SizedBox(height: JimSpacing.md),
          JimCtaPanel(
            title: activeSession.isFinishing
                ? 'Workout finish is pending'
                : 'Workout in progress',
            body:
                '${activeSession.name} is safely checkpointed. Resume it or explicitly discard it.',
            primaryLabel: 'Resume',
            onPrimaryPressed: () => Navigator.of(context).pushNamed(
              '/app/workouts/session/${activeSession.sessionId}',
            ),
            secondaryLabel: 'Discard',
            onSecondaryPressed: () => _confirmDiscardActiveWorkout(
              context,
              ref,
            ),
            icon: Icons.play_circle_outline_rounded,
          ),
        ],
        if (activeAsync.valueOrNull?.corruptedCheckpointRecovered == true) ...[
          const SizedBox(height: JimSpacing.sm),
          Text(
            'A damaged workout checkpoint was removed safely.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: JimColors.inkMuted,
            ),
          ),
        ],
        if (draft.templatesAreStale) ...[
          const SizedBox(height: JimSpacing.sm),
          Text(
            'Showing saved templates from this device while the server is unavailable.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: JimColors.inkMuted,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _WorkoutSchedulePanel(
          templates: draft.templates,
          schedule: draft.workoutSchedule,
          onSchedule: (template, weekday, timeLabel) async {
            final result = await controller.scheduleWorkoutTemplate(
              template,
              weekday: weekday,
              timeLabel: timeLabel,
            );
            return 'Stored on this device. ${result.notification.message}';
          },
          onClear: controller.deleteWorkoutSchedule,
        ),
        const SizedBox(height: 16),
        if (draft.workoutLog.endedAtLabel.trim().isNotEmpty &&
            (draft.workoutLog.workoutLogId != null ||
                draft.lastWorkoutMutation != null)) ...[
          _LastWorkoutSavedPanel(
            workoutLog: draft.workoutLog,
            mutation: draft.lastWorkoutMutation,
            onRetry: controller.retryWorkoutSync,
          ),
          const SizedBox(height: 16),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: JimTextButton(
            label: 'Workout history',
            icon: Icons.history_rounded,
            onPressed: () => Navigator.of(context).pushNamed(
              '/app/workouts/history',
            ),
          ),
        ),
      ],
    );
  }
}

class TemplateBuilderPage extends ConsumerWidget {
  const TemplateBuilderPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftAsync = ref.watch(appDraftProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Template builder')),
      body: draftAsync.when(
        loading: () => const BackendLoadingView(message: 'Loading template...'),
        error: (error, stackTrace) => BackendErrorView(
          error: error,
          onRetry: () => ref.invalidate(appDraftProvider),
        ),
        data: (draft) {
          final controller = ref.read(appDraftProvider.notifier);
          final template = draft.template;
          final theme = Theme.of(context);
          return JimPageScaffold(
            eyebrow: 'WORKOUT TEMPLATE',
            title: template.templateId == null
                ? 'Create template'
                : 'Edit template',
            subtitle:
                'Build a reusable plan. Live workout results are kept separate.',
            bottomPadding: JimSpacing.xl,
            children: [
              JimSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      key: const ValueKey('template-name-field'),
                      initialValue: template.name,
                      onChanged: (value) => controller.updateTemplate(
                        template.copyWith(name: value),
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Template name',
                        prefixIcon: Icon(Icons.edit_note_rounded),
                      ),
                    ),
                    const SizedBox(height: JimSpacing.md),
                    TextFormField(
                      initialValue: template.description,
                      minLines: 2,
                      maxLines: 3,
                      onChanged: (value) => controller.updateTemplate(
                        template.copyWith(description: value),
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Template description',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                    const SizedBox(height: JimSpacing.md),
                    Text(
                      '${template.exercises.length} exercises in this template.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: JimColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: JimSpacing.md),
                    JimPrimaryButton(
                      label: 'Add exercise',
                      icon: Icons.add_rounded,
                      expand: true,
                      onPressed: controller.addExercise,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: JimSpacing.md),
              if (template.exercises.isEmpty)
                JimEmptyState(
                  title: 'No movements yet',
                  message: 'Add the first exercise for this reusable plan.',
                  actionLabel: 'Add exercise',
                  onAction: controller.addExercise,
                  icon: Icons.fitness_center_rounded,
                )
              else
                ...template.exercises.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: JimSpacing.md),
                        child: _ExerciseEditor(
                          index: entry.key,
                          exercise: entry.value,
                          fieldKeyPrefix: 'template',
                          onChanged: (exercise) =>
                              controller.updateExercise(entry.key, exercise),
                          onSuggestionSelected: (suggestion) => controller
                              .applyExerciseSuggestion(entry.key, suggestion),
                          onSetChanged: (setIndex, setDraft) => controller
                              .updateSet(entry.key, setIndex, setDraft),
                          onAddSet: () => controller.addSet(entry.key),
                          onRemoveSet: (setIndex) =>
                              controller.removeSet(entry.key, setIndex),
                          onRemove: () => controller.removeExercise(entry.key),
                        ),
                      ),
                    ),
              JimGuardedPrimaryButton(
                label: 'Save Template',
                loadingLabel: 'Saving...',
                icon: Icons.save_rounded,
                onRun: controller.saveWorkoutTemplate,
                onSuccess: () {
                  _showWorkoutSuccess(context, 'Workout template saved.');
                  Navigator.of(context).pop();
                },
                onError: (error) => _showWorkoutFailure(context, error),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ActiveWorkoutPage extends ConsumerStatefulWidget {
  const ActiveWorkoutPage({
    super.key,
    required this.sessionId,
  });

  final String sessionId;

  @override
  ConsumerState<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends ConsumerState<ActiveWorkoutPage>
    with WidgetsBindingObserver {
  late final ActiveWorkoutController _activeController;

  @override
  void initState() {
    super.initState();
    _activeController = ref.read(activeWorkoutProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_activeController.checkpointNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeAsync = ref.watch(activeWorkoutProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_confirmLeaveActiveWorkout(context));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Active workout'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _confirmLeaveActiveWorkout(context),
          ),
        ),
        body: activeAsync.when(
          loading: () => const BackendLoadingView(
            message: 'Restoring workout...',
          ),
          error: (error, stackTrace) => BackendErrorView(
            error: error,
            onRetry: () => ref.invalidate(activeWorkoutProvider),
          ),
          data: (activeState) {
            final session = activeState.session;
            if (session == null || session.sessionId != widget.sessionId) {
              return JimPageScaffold(
                eyebrow: 'ACTIVE WORKOUT',
                title: 'Session unavailable',
                bottomPadding: JimSpacing.xl,
                children: [
                  JimEmptyState(
                    title: 'This session is no longer active.',
                    message: 'It may have been finished or discarded.',
                    actionLabel: 'Back to workouts',
                    onAction: () => Navigator.of(context).pop(),
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ],
              );
            }
            final controller = ref.read(activeWorkoutProvider.notifier);
            return JimPageScaffold(
              eyebrow: 'ACTIVE WORKOUT',
              title: session.name,
              subtitle:
                  'Started ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(session.startedAt))}',
              bottomPadding: JimSpacing.xl,
              children: [
                JimSurface(
                  tone: JimSurfaceTone.accent,
                  child: TextFormField(
                    initialValue: session.notes,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: controller.updateNotes,
                    decoration: const InputDecoration(
                      labelText: 'Session notes',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: JimSpacing.md),
                ...session.exercises.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: JimSpacing.md),
                        child: _ExerciseEditor(
                          index: entry.key,
                          exercise: entry.value,
                          fieldKeyPrefix: 'active',
                          onChanged: (exercise) =>
                              controller.updateExercise(entry.key, exercise),
                          onSuggestionSelected: (suggestion) =>
                              controller.updateExercise(
                            entry.key,
                            entry.value.copyWith(
                              exerciseId: suggestion.exerciseId,
                              exerciseName: suggestion.name,
                            ),
                          ),
                          onSetChanged: (setIndex, setDraft) => controller
                              .updateSet(entry.key, setIndex, setDraft),
                          onAddSet: () => controller.addSet(entry.key),
                          onRemoveSet: (setIndex) =>
                              controller.removeSet(entry.key, setIndex),
                          onRemove: null,
                        ),
                      ),
                    ),
                JimGuardedPrimaryButton(
                  key: const ValueKey('active-finish-action'),
                  label: 'Finish Workout',
                  loadingLabel: 'Finishing...',
                  icon: Icons.check_circle_rounded,
                  onRun: controller.finish,
                  onSuccess: () async {
                    final mutation = ref
                        .read(appDraftProvider)
                        .valueOrNull
                        ?.lastWorkoutMutation;
                    if (!context.mounted) {
                      return;
                    }
                    await Navigator.of(context).pushReplacementNamed(
                      '/app/workouts/session/${widget.sessionId}/end',
                      arguments: mutation,
                    );
                  },
                  onError: (error) => _showWorkoutFailure(context, error),
                ),
                const SizedBox(height: JimSpacing.sm),
                Center(
                  child: JimTextButton(
                    label: 'Discard workout',
                    icon: Icons.delete_outline_rounded,
                    onPressed: () => _confirmDiscardActiveWorkout(context, ref),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmLeaveActiveWorkout(BuildContext context) async {
    final leave = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Leave active workout?'),
            content: const Text(
              'Your session will stay active and can be resumed from Workouts.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Leave and resume later'),
              ),
            ],
          ),
        ) ??
        false;
    if (leave && context.mounted) {
      await ref.read(activeWorkoutProvider.notifier).checkpointNow();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

class WorkoutFinishSummaryPage extends ConsumerWidget {
  const WorkoutFinishSummaryPage({
    super.key,
    required this.sessionId,
    this.mutation,
  });

  final String sessionId;
  final WorkoutMutationResult? mutation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(appDraftProvider).valueOrNull?.lastWorkoutMutation;
    final result = mutation ?? latest;
    return Scaffold(
      appBar: AppBar(title: const Text('Workout summary')),
      body: JimPageScaffold(
        eyebrow: 'WORKOUT COMPLETE',
        title: result?.syncStatus == WorkoutSyncStatus.synced
            ? 'Workout saved'
            : 'Finish pending sync',
        subtitle: _workoutMutationMessage(result),
        bottomPadding: JimSpacing.xl,
        children: [
          JimCtaPanel(
            title: 'Session complete',
            body: result?.syncStatus == WorkoutSyncStatus.synced
                ? 'Your completed workout is now read-only history.'
                : 'The checkpoint remains on this device until the server confirms completion.',
            primaryLabel: 'View workout history',
            onPrimaryPressed: () => Navigator.of(context).pushReplacementNamed(
              '/app/workouts/history',
            ),
            icon: Icons.task_alt_rounded,
          ),
        ],
      ),
    );
  }
}

class WorkoutHistoryPage extends ConsumerWidget {
  const WorkoutHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(workoutHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Workout history')),
      body: historyAsync.when(
        loading: () => const BackendLoadingView(message: 'Loading history...'),
        error: (error, stackTrace) => BackendErrorView(
          error: error,
          onRetry: () => ref.invalidate(appDraftProvider),
        ),
        data: (history) {
          final completed = history
              .where(
                (log) =>
                    log.workoutLogId != null &&
                    log.endedAtLabel.trim().isNotEmpty,
              )
              .toList(growable: false);
          if (completed.isEmpty) {
            return JimPageScaffold(
              eyebrow: 'WORKOUT HISTORY',
              title: 'Completed workouts',
              bottomPadding: JimSpacing.xl,
              children: const [
                JimEmptyState(
                  title: 'No completed workouts yet',
                  message: 'Finished sessions will appear here.',
                  icon: Icons.history_rounded,
                ),
              ],
            );
          }
          return JimPageScaffold(
            eyebrow: 'WORKOUT HISTORY',
            title: 'Completed workouts',
            bottomPadding: JimSpacing.xl,
            children: completed
                .map(
                  (log) => Padding(
                    padding: const EdgeInsets.only(bottom: JimSpacing.md),
                    child: JimSurface(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(log.name),
                        subtitle: Text('${log.exercises.length} exercises'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pushNamed(
                          '/app/workouts/history/${log.workoutLogId}',
                        ),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          );
        },
      ),
    );
  }
}

class WorkoutHistoryDetailPage extends ConsumerWidget {
  const WorkoutHistoryDetailPage({
    super.key,
    required this.logId,
  });

  final int logId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(workoutHistoryProvider).valueOrNull ?? const [];
    WorkoutLogDraft? log;
    for (final item in history) {
      if (item.workoutLogId == logId && item.endedAtLabel.trim().isNotEmpty) {
        log = item;
        break;
      }
    }
    final available = log != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Workout detail')),
      body: JimPageScaffold(
        eyebrow: 'COMPLETED WORKOUT',
        title: available ? log.name : 'Workout unavailable',
        subtitle: available ? 'Read-only completed session' : null,
        bottomPadding: JimSpacing.xl,
        children: [
          if (!available)
            const JimEmptyState(
              title: 'Workout not found',
              message: 'Return to history and choose an available workout.',
              icon: Icons.search_off_rounded,
            )
          else ...[
            JimSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Session notes',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: JimSpacing.sm),
                  Text(log.notes.trim().isEmpty ? 'No notes' : log.notes),
                ],
              ),
            ),
            const SizedBox(height: JimSpacing.md),
            ...log.exercises.map(
              (exercise) => Padding(
                padding: const EdgeInsets.only(bottom: JimSpacing.md),
                child: JimSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.exerciseName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: JimSpacing.xs),
                      Text('${exercise.sets.length} completed sets'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _confirmDiscardActiveWorkout(
  BuildContext context,
  WidgetRef ref,
) async {
  final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Discard active workout?'),
          content: const Text(
            'This removes the in-progress checkpoint. The source template will not change.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep workout'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ) ??
      false;
  if (discard) {
    await ref.read(activeWorkoutProvider.notifier).discard();
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

class _TemplateLibrary extends StatefulWidget {
  const _TemplateLibrary({
    required this.templates,
    required this.activeTemplateId,
    required this.onCreate,
    required this.onOpen,
    required this.onStart,
    required this.onDelete,
  });

  final List<WorkoutTemplateDraft> templates;
  final int? activeTemplateId;
  final VoidCallback onCreate;
  final ValueChanged<WorkoutTemplateDraft> onOpen;
  final ValueChanged<WorkoutTemplateDraft> onStart;
  final ValueChanged<WorkoutTemplateDraft> onDelete;

  @override
  State<_TemplateLibrary> createState() => _TemplateLibraryState();
}

class _TemplateLibraryState extends State<_TemplateLibrary> {
  static const _pageSize = 20;
  int _visibleCount = _pageSize;

  @override
  Widget build(BuildContext context) {
    if (widget.templates.isEmpty) {
      return JimEmptyState(
        title: 'Create your first workout template.',
        message: 'Save a simple plan once, then reuse it when you train again.',
        actionLabel: 'Create Template',
        onAction: widget.onCreate,
        icon: Icons.note_add_rounded,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: JimSpacing.xs,
          children: [
            Text(
              'Saved templates',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            JimTextButton(
              label: 'Create Template',
              icon: Icons.add_rounded,
              onPressed: widget.onCreate,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...widget.templates.reversed.take(_visibleCount).map(
              (template) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TemplateCard(
                  template: template,
                  isActive: template.templateId == widget.activeTemplateId,
                  onOpen: () => widget.onOpen(template),
                  onStart: () => widget.onStart(template),
                  onDelete: () => widget.onDelete(template),
                ),
              ),
            ),
        if (_visibleCount < widget.templates.length)
          Align(
            alignment: Alignment.center,
            child: JimTextButton(
              label:
                  'Show more templates (${widget.templates.length - _visibleCount})',
              icon: Icons.expand_more_rounded,
              onPressed: () => setState(() {
                _visibleCount = (_visibleCount + _pageSize).clamp(
                  0,
                  widget.templates.length,
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _LastWorkoutSavedPanel extends StatelessWidget {
  const _LastWorkoutSavedPanel({
    required this.workoutLog,
    required this.mutation,
    required this.onRetry,
  });

  final WorkoutLogDraft workoutLog;
  final WorkoutMutationResult? mutation;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = mutation?.syncStatus ?? WorkoutSyncStatus.synced;
    final isSynced = status == WorkoutSyncStatus.synced;
    final needsReview = status == WorkoutSyncStatus.needsReview ||
        status == WorkoutSyncStatus.failed;
    return JimSurface(
      tone: JimSurfaceTone.soft,
      child: Row(
        children: [
          Icon(
            isSynced
                ? Icons.check_circle_rounded
                : needsReview
                    ? Icons.error_outline_rounded
                    : Icons.sync_rounded,
            color: isSynced ? JimColors.success : JimColors.accentStrong,
          ),
          const SizedBox(width: JimSpacing.sm),
          Expanded(
            child: Text(
              isSynced
                  ? '${workoutLog.name.trim().isEmpty ? 'Workout' : workoutLog.name} saved.'
                  : needsReview
                      ? 'Needs attention'
                      : 'Saved on device — waiting to sync',
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (mutation?.retryable == true)
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class _WorkoutSchedulePanel extends StatelessWidget {
  const _WorkoutSchedulePanel({
    required this.templates,
    required this.schedule,
    required this.onSchedule,
    required this.onClear,
  });

  final List<WorkoutTemplateDraft> templates;
  final List<WorkoutScheduleEntry> schedule;
  final Future<String> Function(
    WorkoutTemplateDraft template,
    int weekday,
    String timeLabel,
  ) onSchedule;
  final Future<void> Function(WorkoutScheduleEntry entry) onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (templates.isEmpty) {
      return JimEmptyState(
        title: 'Weekly schedule',
        message: 'Save a template first, then assign it to training days.',
        icon: Icons.calendar_month_rounded,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_month_rounded,
                color: JimColors.accentStrong),
            const SizedBox(width: JimSpacing.sm),
            Expanded(
              child: Text('Weekly schedule', style: theme.textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: JimSpacing.xs),
        Text(
          'Stored on this device for this account. Each active day repeats weekly.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: JimColors.inkSoft,
            height: 1.35,
          ),
        ),
        const SizedBox(height: JimSpacing.md),
        for (final weekday in _weekdays)
          Padding(
            padding: const EdgeInsets.only(bottom: JimSpacing.sm),
            child: _ScheduleDayRow(
              weekday: weekday,
              templates: templates,
              entry: _scheduleForWeekday(schedule, weekday),
              onSchedule: onSchedule,
              onClear: onClear,
            ),
          ),
      ],
    );
  }
}

class _ScheduleDayRow extends StatelessWidget {
  const _ScheduleDayRow({
    required this.weekday,
    required this.templates,
    required this.entry,
    required this.onSchedule,
    required this.onClear,
  });

  final int weekday;
  final List<WorkoutTemplateDraft> templates;
  final WorkoutScheduleEntry? entry;
  final Future<String> Function(
    WorkoutTemplateDraft template,
    int weekday,
    String timeLabel,
  ) onSchedule;
  final Future<void> Function(WorkoutScheduleEntry entry) onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheduledTemplate = _templateForId(templates, entry?.templateId);
    final selectedTemplateId = scheduledTemplate?.templateId;
    final timeLabel = entry?.timeLabel ?? '18:00';

    return JimSurface(
      tone: entry == null ? JimSurfaceTone.plain : JimSurfaceTone.soft,
      padding: const EdgeInsets.all(JimSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  weekdayName(weekday),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (entry != null)
                IconButton(
                  onPressed: () async {
                    await _runWorkoutAction(
                      context,
                      () async => onClear(entry!),
                      successMessage:
                          '${weekdayName(weekday)} workout removed.',
                    );
                  },
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Clear scheduled workout',
                ),
            ],
          ),
          const SizedBox(height: JimSpacing.sm),
          DropdownButtonFormField<int>(
            key: ValueKey('schedule-template-${weekdayName(weekday)}'),
            initialValue: selectedTemplateId,
            items: templates
                .where((template) => template.templateId != null)
                .map(
                  (template) => DropdownMenuItem<int>(
                    value: template.templateId,
                    child: Text(
                      template.name.trim().isEmpty
                          ? 'Untitled template'
                          : template.name.trim(),
                    ),
                  ),
                )
                .toList(),
            onChanged: (templateId) async {
              final template = _templateForId(templates, templateId);
              if (template == null) {
                return;
              }
              await _saveSchedule(context, template, weekday, timeLabel);
            },
            decoration: const InputDecoration(
              labelText: 'Template',
              prefixIcon: Icon(Icons.fitness_center_rounded),
            ),
          ),
          const SizedBox(height: JimSpacing.sm),
          Row(
            children: [
              Expanded(
                child: JimSecondaryButton(
                  label: timeLabel,
                  icon: Icons.schedule_rounded,
                  onPressed: () async {
                    final template = scheduledTemplate;
                    if (template == null) {
                      return;
                    }
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _timeOfDay(timeLabel),
                    );
                    if (picked == null || !context.mounted) {
                      return;
                    }
                    await _saveSchedule(
                      context,
                      template,
                      weekday,
                      _formatTimeOfDay(picked),
                    );
                  },
                ),
              ),
              const SizedBox(width: JimSpacing.sm),
              Expanded(
                child: Text(
                  entry == null ? 'No workout assigned' : 'Repeats weekly',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: JimColors.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveSchedule(
    BuildContext context,
    WorkoutTemplateDraft template,
    int weekday,
    String timeLabel,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await onSchedule(template, weekday, timeLabel);
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      await _showWorkoutErrorDialog(context, _friendlyWorkoutError(error));
    }
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.isActive,
    required this.onOpen,
    required this.onStart,
    required this.onDelete,
  });

  final WorkoutTemplateDraft template;
  final bool isActive;
  final VoidCallback onOpen;
  final VoidCallback onStart;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exerciseCount = template.exercises.length;
    final setCount = template.exercises.fold<int>(
      0,
      (total, exercise) => total + exercise.sets.length,
    );
    final subtitle = [
      '$exerciseCount ${exerciseCount == 1 ? 'exercise' : 'exercises'}',
      if (setCount > 0) '$setCount planned ${setCount == 1 ? 'set' : 'sets'}',
    ].join(' • ');

    return JimSurface(
      tone: isActive ? JimSurfaceTone.accent : JimSurfaceTone.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.fact_check_rounded,
                color: isActive ? JimColors.accentStrong : JimColors.inkMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  template.name.trim().isEmpty
                      ? 'Untitled template'
                      : template.name.trim(),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (template.templateId != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Delete template',
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: JimColors.inkMuted,
            ),
          ),
          if (template.description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              template.description.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: JimColors.inkSoft,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: JimSecondaryButton(
                  label: 'Open',
                  icon: Icons.edit_note_rounded,
                  onPressed: onOpen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: JimPrimaryButton(
                  label: 'Start',
                  icon: Icons.play_arrow_rounded,
                  onPressed: onStart,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExerciseEditor extends ConsumerStatefulWidget {
  const _ExerciseEditor({
    required this.index,
    required this.exercise,
    required this.fieldKeyPrefix,
    required this.onChanged,
    required this.onSuggestionSelected,
    required this.onSetChanged,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onRemove,
  });

  final int index;
  final WorkoutExerciseDraft exercise;
  final String fieldKeyPrefix;
  final ValueChanged<WorkoutExerciseDraft> onChanged;
  final ValueChanged<ExerciseSuggestion> onSuggestionSelected;
  final void Function(int setIndex, SetDraft setDraft) onSetChanged;
  final VoidCallback onAddSet;
  final ValueChanged<int> onRemoveSet;
  final VoidCallback? onRemove;

  @override
  ConsumerState<_ExerciseEditor> createState() => _ExerciseEditorState();
}

enum _ExerciseSearchStatus {
  idle,
  loading,
  results,
  noResults,
  cachedOffline,
  error,
}

class _ExerciseEditorState extends ConsumerState<_ExerciseEditor> {
  Timer? _debounce;
  late final TextEditingController _exerciseNameController;
  List<ExerciseSuggestion> _suggestions = const [];
  _ExerciseSearchStatus _searchStatus = _ExerciseSearchStatus.idle;
  Object? _searchError;
  final _searchGate = SearchRequestGate();

  @override
  void initState() {
    super.initState();
    _exerciseNameController =
        TextEditingController(text: widget.exercise.exerciseName);
  }

  @override
  void didUpdateWidget(covariant _ExerciseEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_exerciseNameController.text != widget.exercise.exerciseName) {
      _exerciseNameController.text = widget.exercise.exerciseName;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _exerciseNameController.dispose();
    super.dispose();
  }

  void _queueExerciseSearch(String query, {bool force = false}) {
    _debounce?.cancel();
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      _searchGate.clear();
      setState(() {
        _suggestions = const [];
        _searchStatus = _ExerciseSearchStatus.idle;
        _searchError = null;
      });
      return;
    }

    if (!force &&
        normalized == _searchGate.activeQuery &&
        _searchStatus != _ExerciseSearchStatus.loading) {
      return;
    }

    final generation = _searchGate.begin(normalized);
    setState(() {
      _searchStatus = _ExerciseSearchStatus.loading;
      _searchError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await ref
            .read(appDraftProvider.notifier)
            .searchExerciseSuggestions(normalized);
        if (!mounted || !_searchGate.isCurrent(generation, normalized)) {
          return;
        }
        setState(() {
          _suggestions = results;
          _searchStatus = results.isEmpty
              ? _ExerciseSearchStatus.noResults
              : _ExerciseSearchStatus.results;
          _searchError = null;
        });
      } on CachedSearchResultsException<ExerciseSuggestion> catch (error) {
        if (!mounted || !_searchGate.isCurrent(generation, normalized)) {
          return;
        }
        setState(() {
          _suggestions = error.results;
          _searchStatus = _ExerciseSearchStatus.cachedOffline;
          _searchError = error.error;
        });
      } catch (error) {
        if (!mounted || !_searchGate.isCurrent(generation, normalized)) {
          return;
        }
        setState(() {
          _suggestions = const [];
          _searchStatus = _ExerciseSearchStatus.error;
          _searchError = error;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    return JimSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Exercise ${widget.index + 1}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: JimColors.inkMuted,
                ),
          ),
          if (widget.onRemove != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove'),
              ),
            ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _exerciseNameController,
            onChanged: (value) {
              widget.onChanged(
                exercise.copyWith(exerciseId: null, exerciseName: value),
              );
              _queueExerciseSearch(value);
            },
            decoration: InputDecoration(
              labelText: 'Exercise name',
              prefixIcon: const Icon(Icons.fitness_center_rounded),
              suffixIcon: _searchStatus == _ExerciseSearchStatus.loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          if (_searchStatus == _ExerciseSearchStatus.loading) ...[
            const SizedBox(height: 8),
            Text(
              'Searching exercises...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: JimColors.inkMuted,
                  ),
            ),
          ] else if (_searchStatus == _ExerciseSearchStatus.noResults) ...[
            const SizedBox(height: 8),
            Text(
              'No exercise results found.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: JimColors.inkMuted,
                  ),
            ),
          ] else if (_searchStatus == _ExerciseSearchStatus.cachedOffline) ...[
            const SizedBox(height: 8),
            Text(
              'Offline — showing cached exercise results.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: JimColors.terracotta,
                  ),
            ),
          ] else if (_searchStatus == _ExerciseSearchStatus.error) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    presentAppError(
                      _searchError ?? Exception('Exercise search failed.'),
                      fallbackMessage:
                          'Exercise search is unavailable. Please try again.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: JimColors.terracotta,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: () => _queueExerciseSearch(
                    _exerciseNameController.text,
                    force: true,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _searchGate.activeQuery.length < 3
                  ? 'Suggestions'
                  : 'Ranked results',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: JimColors.inkMuted,
                  ),
            ),
            if (_searchGate.activeQuery.length >= 3) ...[
              const SizedBox(height: 4),
              Text(
                'Showing best matches from the exercise catalog. Try a more specific name for more precise results.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: JimColors.inkMuted,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            ..._suggestions.take(10).map(
                  (suggestion) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ExerciseSuggestionTile(
                      suggestion: suggestion,
                      onTap: () {
                        widget.onSuggestionSelected(suggestion);
                        _searchGate.clear();
                        setState(() {
                          _suggestions = const [];
                          _searchStatus = _ExerciseSearchStatus.idle;
                          _searchError = null;
                        });
                      },
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: '${exercise.targetSets}',
                  keyboardType: TextInputType.number,
                  onChanged: (value) => widget.onChanged(
                    exercise.copyWith(
                      targetSets: int.tryParse(value) ?? exercise.targetSets,
                    ),
                  ),
                  decoration: const InputDecoration(labelText: 'Target sets'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: '${exercise.targetReps}',
                  keyboardType: TextInputType.number,
                  onChanged: (value) => widget.onChanged(
                    exercise.copyWith(
                      targetReps: int.tryParse(value) ?? exercise.targetReps,
                    ),
                  ),
                  decoration: const InputDecoration(labelText: 'Target reps'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: exercise.notes,
            onChanged: (value) =>
                widget.onChanged(exercise.copyWith(notes: value)),
            decoration: const InputDecoration(
              labelText: 'Coaching note',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 14),
          ...exercise.sets.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SetEditor(
                    exerciseIndex: widget.index,
                    fieldKeyPrefix: widget.fieldKeyPrefix,
                    setDraft: entry.value,
                    canRemove: exercise.sets.length > 1,
                    onChanged: (setDraft) =>
                        widget.onSetChanged(entry.key, setDraft),
                    onRemove: () => widget.onRemoveSet(entry.key),
                  ),
                ),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onAddSet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add set'),
            ),
          ),
        ],
      ),
    );
  }
}

const _weekdays = [
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
  DateTime.saturday,
  DateTime.sunday,
];

WorkoutScheduleEntry? _scheduleForWeekday(
  List<WorkoutScheduleEntry> schedule,
  int weekday,
) {
  for (final entry in schedule) {
    if (entry.active && entry.weekday == weekday) {
      return entry;
    }
  }
  return null;
}

WorkoutTemplateDraft? _templateForId(
  List<WorkoutTemplateDraft> templates,
  int? templateId,
) {
  if (templateId == null) {
    return null;
  }
  for (final template in templates) {
    if (template.templateId == templateId) {
      return template;
    }
  }
  return null;
}

TimeOfDay _timeOfDay(String timeLabel) {
  final parts = timeLabel.split(':');
  final hour = parts.isEmpty ? 18 : int.tryParse(parts.first) ?? 18;
  final minute = parts.length < 2 ? 0 : int.tryParse(parts[1]) ?? 0;
  return TimeOfDay(
    hour: hour.clamp(0, 23),
    minute: minute.clamp(0, 59),
  );
}

String _formatTimeOfDay(TimeOfDay time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

class _ExerciseSuggestionTile extends StatelessWidget {
  const _ExerciseSuggestionTile({
    required this.suggestion,
    required this.onTap,
  });

  final ExerciseSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: JimColors.galleryWhite,
      borderRadius: BorderRadius.circular(JimRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JimRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(JimSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      suggestion.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: JimColors.inkMuted,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _runWorkoutAction(
  BuildContext context,
  Future<Object?> Function() action, {
  required String successMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(successMessage)),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    await _showWorkoutErrorDialog(context, _friendlyWorkoutError(error));
  }
}

void _showWorkoutSuccess(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

String _workoutMutationMessage(WorkoutMutationResult? result) {
  return switch (result?.syncStatus) {
    WorkoutSyncStatus.synced => 'Workout saved.',
    WorkoutSyncStatus.pendingSync => 'Saved on device — waiting to sync.',
    WorkoutSyncStatus.needsReview => 'Needs attention.',
    WorkoutSyncStatus.failed => 'Workout save failed. Retry when ready.',
    null => 'Workout status is unavailable.',
  };
}

void _showWorkoutFailure(BuildContext context, Object error) {
  if (!context.mounted) {
    return;
  }
  unawaited(_showWorkoutErrorDialog(context, _friendlyWorkoutError(error)));
}

Future<void> _showWorkoutErrorDialog(
  BuildContext context,
  String message,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Workout save failed'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: SelectableText(message),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

String _friendlyWorkoutError(Object error) {
  return presentAppError(
    error,
    fallbackMessage:
        'We could not save that workout change. Your edits are still here; please try again.',
  );
}

class _SetEditor extends StatelessWidget {
  const _SetEditor({
    required this.exerciseIndex,
    required this.fieldKeyPrefix,
    required this.setDraft,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int exerciseIndex;
  final String fieldKeyPrefix;
  final SetDraft setDraft;
  final bool canRemove;
  final ValueChanged<SetDraft> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(JimSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(JimRadius.md),
        color: JimColors.galleryWhite,
        border: Border.all(color: JimColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Set ${setDraft.setNumber}')),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  tooltip: 'Remove set',
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey(
                    fieldKeyPrefix == 'template'
                        ? 'set-weight-field-$exerciseIndex-${setDraft.setNumber}'
                        : '$fieldKeyPrefix-set-weight-field-$exerciseIndex-${setDraft.setNumber}',
                  ),
                  initialValue: '${setDraft.weightKg}',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) => onChanged(
                    setDraft.copyWith(
                      weightKg: double.tryParse(value) ?? setDraft.weightKg,
                    ),
                  ),
                  decoration: const InputDecoration(labelText: 'kg'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: '${setDraft.reps}',
                  keyboardType: TextInputType.number,
                  onChanged: (value) => onChanged(
                    setDraft.copyWith(
                      reps: int.tryParse(value) ?? setDraft.reps,
                    ),
                  ),
                  decoration: const InputDecoration(labelText: 'Reps'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: '${setDraft.rpe}',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) => onChanged(
                    setDraft.copyWith(
                      rpe: double.tryParse(value) ?? setDraft.rpe,
                    ),
                  ),
                  decoration: const InputDecoration(labelText: 'RPE'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

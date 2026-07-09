import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/notifications/workout_notification_service.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/action_state.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/jim_button.dart';
import '../../../shared/components/jim_page_scaffold.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/models/app_models.dart';

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

    return JimPageScaffold(
      eyebrow: 'WORKOUTS',
      title: 'Workout templates',
      subtitle:
          'Create reusable plans, open them later, then start a workout from the template.',
      headerTrailing: IconButton(
        onPressed: controller.createTemplateDraft,
        icon: const Icon(Icons.add_rounded),
        tooltip: 'Create Template',
      ),
      children: [
        _TemplateLibrary(
          templates: draft.templates,
          activeTemplateId: template.templateId,
          onCreate: controller.createTemplateDraft,
          onOpen: controller.openWorkoutTemplate,
          onStart: controller.startWorkoutFromTemplate,
          onDelete: (template) async {
            await _runWorkoutAction(
              context,
              () async => controller.deleteWorkoutTemplate(template),
              successMessage: 'Workout template deleted.',
            );
          },
        ),
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
            return result.notification.message;
          },
          onClear: controller.deleteWorkoutSchedule,
        ),
        const SizedBox(height: 16),
        if (draft.workoutLog.isInProgress) ...[
          _WorkoutExecutionPanel(
            workoutLog: draft.workoutLog,
            onNotesChanged: controller.updateWorkoutNotes,
            onExerciseChanged: controller.updateWorkoutExercise,
            onSuggestionSelected: controller.applyWorkoutExerciseSuggestion,
            onSetChanged: controller.updateWorkoutSet,
            onAddSet: controller.addWorkoutSet,
            onRemoveSet: controller.removeWorkoutSet,
            onFinish: () async {
              await _runWorkoutAction(
                context,
                () async => controller.logWorkoutSession(),
                successMessage: 'Workout finished and saved.',
              );
            },
          ),
          const SizedBox(height: 16),
        ] else if (draft.workoutLog.workoutLogId != null &&
            draft.workoutLog.endedAtLabel.trim().isNotEmpty) ...[
          _LastWorkoutSavedPanel(workoutLog: draft.workoutLog),
          const SizedBox(height: 16),
        ],
        JimSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Template builder', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
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
              const SizedBox(height: 14),
              TextFormField(
                initialValue: template.description,
                minLines: 2,
                maxLines: 3,
                onChanged: (value) => controller.updateTemplate(
                  template.copyWith(description: value),
                ),
                decoration: const InputDecoration(
                  labelText: 'Session description',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 18),
              Text('Add exercises', style: theme.textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(
                '${template.exercises.length} exercises in this draft. Add one movement, choose a suggestion, then fill sets.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: JimColors.inkSoft,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: JimPrimaryButton(
                  label: 'Add exercise',
                  icon: Icons.add_rounded,
                  onPressed: controller.addExercise,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (template.exercises.isEmpty)
          JimEmptyState(
            title: 'No movements yet',
            message:
                'Add your first exercise when you are ready to build this session.',
            actionLabel: 'Add exercise',
            onAction: controller.addExercise,
            icon: Icons.fitness_center_rounded,
          )
        else
          ...template.exercises.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _ExerciseEditor(
                    index: entry.key,
                    exercise: entry.value,
                    fieldKeyPrefix: 'template',
                    onChanged: (exercise) =>
                        controller.updateExercise(entry.key, exercise),
                    onSuggestionSelected: (suggestion) => controller
                        .applyExerciseSuggestion(entry.key, suggestion),
                    onSetChanged: (setIndex, setDraft) =>
                        controller.updateSet(entry.key, setIndex, setDraft),
                    onAddSet: () => controller.addSet(entry.key),
                    onRemoveSet: (setIndex) =>
                        controller.removeSet(entry.key, setIndex),
                    onRemove: () => controller.removeExercise(entry.key),
                  ),
                ),
              ),
        JimSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Session note', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: draft.workoutLog.notes,
                minLines: 2,
                maxLines: 4,
                onChanged: controller.updateWorkoutNotes,
                decoration: const InputDecoration(
                  labelText: 'How did the session feel?',
                  prefixIcon: Icon(Icons.mic_none_rounded),
                ),
              ),
              const SizedBox(height: 18),
              Text('Save or log', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: JimGuardedPrimaryButton(
                      label: 'Save Template',
                      loadingLabel: 'Saving...',
                      icon: Icons.save_rounded,
                      onRun: () => controller.saveWorkoutTemplate(),
                      onSuccess: () => _showWorkoutSuccess(
                        context,
                        'Workout template saved.',
                      ),
                      onError: (error) => _showWorkoutFailure(context, error),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: JimGuardedPrimaryButton(
                  label: draft.workoutLog.isInProgress
                      ? 'Finish Workout'
                      : 'Log Workout',
                  loadingLabel: draft.workoutLog.isInProgress
                      ? 'Finishing...'
                      : 'Saving...',
                  icon: Icons.cloud_upload_rounded,
                  onRun: () => controller.logWorkoutSession(),
                  onSuccess: () => _showWorkoutSuccess(
                    context,
                    draft.workoutLog.isInProgress
                        ? 'Workout finished and saved.'
                        : 'Workout log saved to Supabase.',
                  ),
                  onError: (error) => _showWorkoutFailure(context, error),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TemplateLibrary extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (templates.isEmpty) {
      return JimEmptyState(
        title: 'Create your first workout template.',
        message: 'Save a simple plan once, then reuse it when you train again.',
        actionLabel: 'Create Template',
        onAction: onCreate,
        icon: Icons.note_add_rounded,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Saved templates',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            JimTextButton(
              label: 'Create Template',
              icon: Icons.add_rounded,
              onPressed: onCreate,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...templates.reversed.map(
          (template) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TemplateCard(
              template: template,
              isActive: template.templateId == activeTemplateId,
              onOpen: () => onOpen(template),
              onStart: () => onStart(template),
              onDelete: () => onDelete(template),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkoutExecutionPanel extends StatelessWidget {
  const _WorkoutExecutionPanel({
    required this.workoutLog,
    required this.onNotesChanged,
    required this.onExerciseChanged,
    required this.onSuggestionSelected,
    required this.onSetChanged,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onFinish,
  });

  final WorkoutLogDraft workoutLog;
  final ValueChanged<String> onNotesChanged;
  final void Function(int index, WorkoutExerciseDraft exercise)
      onExerciseChanged;
  final void Function(int index, ExerciseSuggestion suggestion)
      onSuggestionSelected;
  final void Function(int exerciseIndex, int setIndex, SetDraft setDraft)
      onSetChanged;
  final ValueChanged<int> onAddSet;
  final void Function(int exerciseIndex, int setIndex) onRemoveSet;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final setCount = workoutLog.exercises.fold<int>(
      0,
      (total, exercise) => total + exercise.sets.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JimSurface(
          tone: JimSurfaceTone.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.timer_rounded,
                    color: JimColors.accentStrong,
                  ),
                  const SizedBox(width: JimSpacing.sm),
                  Expanded(
                    child: Text(
                      workoutLog.name.trim().isEmpty
                          ? 'Workout in progress'
                          : workoutLog.name,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: JimSpacing.xs),
              Text(
                '${workoutLog.exercises.length} exercises • $setCount sets',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: JimColors.inkSoft,
                ),
              ),
              const SizedBox(height: JimSpacing.md),
              TextFormField(
                initialValue: workoutLog.notes,
                minLines: 2,
                maxLines: 4,
                onChanged: onNotesChanged,
                decoration: const InputDecoration(
                  labelText: 'Session notes',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: JimSpacing.md),
        if (workoutLog.exercises.isEmpty)
          const JimEmptyState(
            title: 'No exercises loaded',
            message: 'Start from a saved template to preload your workout.',
            icon: Icons.fitness_center_rounded,
          )
        else
          ...workoutLog.exercises.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: JimSpacing.md),
                  child: _ExerciseEditor(
                    index: entry.key,
                    exercise: entry.value,
                    fieldKeyPrefix: 'workout',
                    onChanged: (exercise) =>
                        onExerciseChanged(entry.key, exercise),
                    onSuggestionSelected: (suggestion) =>
                        onSuggestionSelected(entry.key, suggestion),
                    onSetChanged: (setIndex, setDraft) =>
                        onSetChanged(entry.key, setIndex, setDraft),
                    onAddSet: () => onAddSet(entry.key),
                    onRemoveSet: (setIndex) => onRemoveSet(entry.key, setIndex),
                    onRemove: null,
                  ),
                ),
              ),
        SizedBox(
          width: double.infinity,
          child: JimGuardedPrimaryButton(
            label: 'Finish Workout',
            loadingLabel: 'Finishing...',
            icon: Icons.check_circle_rounded,
            onRun: onFinish,
          ),
        ),
      ],
    );
  }
}

class _LastWorkoutSavedPanel extends StatelessWidget {
  const _LastWorkoutSavedPanel({
    required this.workoutLog,
  });

  final WorkoutLogDraft workoutLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JimSurface(
      tone: JimSurfaceTone.soft,
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: JimColors.success),
          const SizedBox(width: JimSpacing.sm),
          Expanded(
            child: Text(
              '${workoutLog.name.trim().isEmpty ? 'Workout' : workoutLog.name} saved.',
              style: theme.textTheme.titleSmall,
            ),
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
          'Assign saved templates to days. Each active day repeats weekly.',
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

class _ExerciseEditorState extends ConsumerState<_ExerciseEditor> {
  Timer? _debounce;
  late final TextEditingController _exerciseNameController;
  List<ExerciseSuggestion> _suggestions = const [];
  bool _isSearching = false;
  bool _searchFailed = false;
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

  void _queueExerciseSearch(String query) {
    _debounce?.cancel();
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      _searchGate.clear();
      setState(() {
        _suggestions = const [];
        _isSearching = false;
        _searchFailed = false;
      });
      return;
    }

    if (normalized == _searchGate.activeQuery && !_isSearching) {
      return;
    }

    final generation = _searchGate.begin(normalized);
    setState(() {
      _isSearching = true;
      _searchFailed = false;
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
          _isSearching = false;
          _searchFailed = false;
        });
      } catch (_) {
        if (!mounted || !_searchGate.isCurrent(generation, normalized)) {
          return;
        }
        setState(() {
          _isSearching = false;
          _searchFailed = true;
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
              suffixIcon: _isSearching
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
          if (_isSearching) ...[
            const SizedBox(height: 8),
            Text(
              'Searching exercises...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: JimColors.inkMuted,
                  ),
            ),
          ] else if (_searchFailed) ...[
            const SizedBox(height: 8),
            Text(
              'Couldn\'t refresh exercises. Check connection and try again.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: JimColors.terracotta,
                  ),
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
                        setState(() => _suggestions = const []);
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
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'Workout save timeout\nsource: lib/features/workouts/presentation/workouts_page.dart -> _runWorkoutAction\nproblem: backend did not answer before Dio timeout\nraw: ${error.message}',
      DioExceptionType.connectionError =>
        'Workout save connection error\nsource: lib/features/workouts/presentation/workouts_page.dart -> _runWorkoutAction\nproblem: Flutter could not reach FastAPI/ngrok\nraw: ${error.message}',
      DioExceptionType.badResponse => _friendlyStatusError(
          error.response?.statusCode,
          error.response?.data,
        ),
      DioExceptionType.cancel => 'The workout request was cancelled.',
      DioExceptionType.badCertificate =>
        'The backend TLS certificate was rejected. Check the backend URL.',
      DioExceptionType.unknown =>
        'Workout save failed before backend response\nsource: lib/features/workouts/presentation/workouts_page.dart -> _runWorkoutAction\nraw: ${error.message}',
    };
  }

  final raw = error.toString().replaceFirst('Exception: ', '').trim();
  if (raw.contains('receive timeout') || raw.contains('send timeout')) {
    return 'Workout save timeout\nsource: lib/features/workouts/presentation/workouts_page.dart -> _runWorkoutAction\nproblem: backend did not answer before Dio timeout\nraw: $raw';
  }
  return raw;
}

String _friendlyStatusError(int? statusCode, Object? body) {
  if (statusCode == 401) {
    return 'Workout save unauthorized\nsource: lib/features/workouts/presentation/workouts_page.dart -> _friendlyStatusError\nstatus: 401\nproblem: FastAPI rejected the Authorization bearer token.\nresponse_body: ${body ?? 'empty'}\nfix: Verify backend JWT validation, Supabase project ref, and whether Flutter is sending a fresh access token.';
  }
  if (statusCode == 422) {
    return 'Workout payload rejected\nsource: lib/features/workouts/presentation/workouts_page.dart -> _friendlyStatusError\nstatus: 422\nproblem: FastAPI rejected the workout request schema.\nresponse_body: ${body ?? 'empty'}\nfix: Compare the request payload shown in app_repositories.dart diagnostics with the backend Pydantic model.';
  }
  if (statusCode != null && statusCode >= 500) {
    return 'Workout backend server error\nsource: lib/features/workouts/presentation/workouts_page.dart -> _friendlyStatusError\nstatus: $statusCode\nproblem: FastAPI crashed or returned an internal error while saving workout.\nresponse_body: ${body ?? 'empty'}\nfix: Inspect backend logs for this route and confirm DB insert/user lookup succeeds.';
  }
  final bodyText = body?.toString() ?? 'Workout save failed.';
  return 'Workout save failed\nsource: lib/features/workouts/presentation/workouts_page.dart -> _friendlyStatusError\nstatus: ${statusCode ?? 'unknown'}\nresponse_body: $bodyText';
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

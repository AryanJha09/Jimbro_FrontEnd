import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/jim_button.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/components/section_header.dart';
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

    return _BaseFeaturePage(
      eyebrow: 'WORKOUTS',
      title: 'Editable training draft',
      child: Column(
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
                Row(
                  children: [
                    Expanded(
                      child: _PillMetric(
                        label: 'Exercises',
                        value: '${template.exercises.length}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PillMetric(
                        label: 'Duration',
                        value: '${template.durationMinutes} min',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PillMetric(
                        label: 'Goal',
                        value: template.goal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: JimPrimaryButton(
                        label: 'Add exercise',
                        icon: Icons.add_rounded,
                        onPressed: controller.addExercise,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: JimPrimaryButton(
                        label: 'Save template',
                        icon: Icons.save_rounded,
                        onPressed: () async {
                          await _runWorkoutAction(
                            context,
                            () async => controller.saveWorkoutTemplate(),
                            successMessage:
                                'Workout template saved to Supabase.',
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: JimPrimaryButton(
                    label: 'Log workout',
                    icon: Icons.cloud_upload_rounded,
                    onPressed: () async {
                      await _runWorkoutAction(
                        context,
                        () async => controller.logWorkoutSession(),
                        successMessage: 'Workout log saved to Supabase.',
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (template.exercises.isEmpty)
            const JimSurface(
              child: Text(
                'No exercises yet. Add your first exercise and then save or log the workout.',
              ),
            )
          else
            ...template.exercises.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _ExerciseEditor(
                      index: entry.key,
                      exercise: entry.value,
                      onChanged: (exercise) =>
                          controller.updateExercise(entry.key, exercise),
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
                Text('Current workout note', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: draft.workoutLog.notes,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: controller.updateWorkoutNotes,
                  decoration: const InputDecoration(
                    labelText: 'Live session note',
                    prefixIcon: Icon(Icons.mic_none_rounded),
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

class _ExerciseEditor extends ConsumerStatefulWidget {
  const _ExerciseEditor({
    required this.index,
    required this.exercise,
    required this.onChanged,
    required this.onSetChanged,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onRemove,
  });

  final int index;
  final WorkoutExerciseDraft exercise;
  final ValueChanged<WorkoutExerciseDraft> onChanged;
  final void Function(int setIndex, SetDraft setDraft) onSetChanged;
  final VoidCallback onAddSet;
  final ValueChanged<int> onRemoveSet;
  final VoidCallback onRemove;

  @override
  ConsumerState<_ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends ConsumerState<_ExerciseEditor> {
  Timer? _debounce;
  late final TextEditingController _exerciseNameController;
  List<ExerciseSuggestion> _suggestions = const [];
  bool _isSearching = false;

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
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _suggestions = const [];
        _isSearching = false;
      });
      return;
    }
    final local = _instantExerciseSuggestions(trimmed);
    setState(() {
      _suggestions = local;
      _isSearching = true;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref
          .read(appDraftProvider.notifier)
          .searchExerciseSuggestions(trimmed);
      if (!mounted) {
        return;
      }
      setState(() {
        _suggestions =
            results.isEmpty ? local : _mergeVisibleSuggestions(results, local);
        _isSearching = false;
      });
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
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._suggestions.take(4).map(
                  (suggestion) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ExerciseSuggestionTile(
                      suggestion: suggestion,
                      onTap: () {
                        ref
                            .read(appDraftProvider.notifier)
                            .applyExerciseSuggestion(widget.index, suggestion);
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

List<ExerciseSuggestion> _instantExerciseSuggestions(String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.length < 2) {
    return const [];
  }
  return const [
    ExerciseSuggestion(
      exerciseId: 111,
      name: 'Bench Press (Barbell)',
      subtitle: 'Barbell • chest',
    ),
    ExerciseSuggestion(
      exerciseId: 113,
      name: 'Bench Press (Dumbbell)',
      subtitle: 'Dumbbell • chest',
    ),
    ExerciseSuggestion(
      exerciseId: 115,
      name: 'Bench Press - Wide Grip (Barbell)',
      subtitle: 'Barbell • chest',
    ),
    ExerciseSuggestion(
      exerciseId: 350,
      name: 'Bench Press - Close Grip (Barbell)',
      subtitle: 'Barbell • triceps',
    ),
    ExerciseSuggestion(
      exerciseId: 349,
      name: 'Bench Dip',
      subtitle: 'Bodyweight • triceps',
    ),
  ].where((item) => item.name.toLowerCase().contains(normalized)).toList();
}

List<ExerciseSuggestion> _mergeVisibleSuggestions(
  List<ExerciseSuggestion> primary,
  List<ExerciseSuggestion> fallback,
) {
  final byId = <int, ExerciseSuggestion>{};
  for (final item in [...primary, ...fallback]) {
    byId.putIfAbsent(item.exerciseId, () => item);
  }
  return byId.values.toList();
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
    messenger.showSnackBar(
      SnackBar(content: Text(successMessage)),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(_friendlyWorkoutError(error))),
    );
  }
}

String _friendlyWorkoutError(Object error) {
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'The backend is taking longer than expected. Your draft is still here; try again in a moment.',
      DioExceptionType.connectionError =>
        'Could not reach the backend. Check the ngrok URL and internet connection, then retry.',
      DioExceptionType.badResponse => _friendlyStatusError(
          error.response?.statusCode,
          error.response?.data,
        ),
      DioExceptionType.cancel => 'The workout request was cancelled.',
      DioExceptionType.badCertificate =>
        'The backend TLS certificate was rejected. Check the backend URL.',
      DioExceptionType.unknown =>
        'Workout save failed before the backend responded. Please retry.',
    };
  }

  final raw = error.toString().replaceFirst('Exception: ', '').trim();
  if (raw.contains('receive timeout') || raw.contains('send timeout')) {
    return 'The backend is taking longer than expected. Your draft is still here; try again in a moment.';
  }
  if (raw.contains('status: 401') ||
      raw.toLowerCase().contains('invalid token') ||
      raw.toLowerCase().contains('could not validate credentials')) {
    return 'Your session token was rejected. Sign out, sign back in, then retry the workout save.';
  }
  if (raw.toLowerCase().contains('socket') ||
      raw.toLowerCase().contains('connection')) {
    return 'Could not reach the backend. Check the ngrok URL and internet connection, then retry.';
  }
  return raw.length > 180 ? '${raw.substring(0, 180)}...' : raw;
}

String _friendlyStatusError(int? statusCode, Object? body) {
  if (statusCode == 401) {
    return 'Your session token was rejected. Sign out, sign back in, then retry the workout save.';
  }
  if (statusCode == 422) {
    return 'The backend rejected the workout payload. Check exercise, set, reps, and weight fields.';
  }
  if (statusCode != null && statusCode >= 500) {
    return 'The backend hit a server error while saving. Your draft is still here; retry after the API recovers.';
  }
  final bodyText = body?.toString() ?? 'Workout save failed.';
  return bodyText.length > 180 ? '${bodyText.substring(0, 180)}...' : bodyText;
}

class _SetEditor extends StatelessWidget {
  const _SetEditor({
    required this.exerciseIndex,
    required this.setDraft,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int exerciseIndex;
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
                    'set-weight-field-$exerciseIndex-${setDraft.setNumber}',
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

class _PillMetric extends StatelessWidget {
  const _PillMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          Text(
            label,
            style:
                theme.textTheme.labelLarge?.copyWith(color: JimColors.inkMuted),
          ),
          const SizedBox(height: 6),
          Text(value, style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _BaseFeaturePage extends StatelessWidget {
  const _BaseFeaturePage({
    required this.eyebrow,
    required this.title,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [JimColors.galleryWhite, JimColors.ivory],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            SectionHeader(eyebrow: eyebrow, title: title),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

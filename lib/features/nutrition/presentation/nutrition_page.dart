import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/navigation/app_state.dart';
import '../../../core/repositories/app_repositories.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/insight_card.dart';
import '../../../shared/components/jim_page_scaffold.dart';
import '../../../shared/components/jim_surface.dart';
import '../../../shared/components/metric_tile.dart';
import '../../../shared/components/section_header.dart';
import '../../../shared/models/app_models.dart';

class NutritionPage extends ConsumerWidget {
  const NutritionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftAsync = ref.watch(appDraftProvider);
    return draftAsync.when(
      loading: () => const BackendLoadingView(message: 'Loading nutrition...'),
      error: (error, stackTrace) => BackendErrorView(
        error: error,
        onRetry: () => ref.invalidate(appDraftProvider),
      ),
      data: (draft) => _NutritionContent(draft: draft),
    );
  }
}

class _NutritionContent extends ConsumerWidget {
  const _NutritionContent({
    required this.draft,
  });

  final AppDraftState draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appDraftProvider.notifier);
    final summary = draft.nutritionSummary;
    final foodLogs = draft.foodLogs;
    final insightAsync = ref.watch(nutritionInsightProvider);
    final theme = Theme.of(context);
    final groupedMeals = _groupFoodLogsByMeal(foodLogs);

    return JimPageScaffold(
      scrollKey: const ValueKey('nutrition-scroll-view'),
      eyebrow: 'NUTRITION',
      title: 'Today\'s food log',
      subtitle: 'Add meals manually and keep the day easy to understand.',
      children: [
        JimSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                eyebrow: 'TODAY',
                title: 'Daily summary',
                subtitle: summary.targetCalories > 0
                    ? '${_formatNumber(summary.remainingCalories)} calories left'
                    : '${_formatNumber(summary.consumedCalories)} calories logged',
              ),
              const SizedBox(height: 14),
              _MacroSummaryGrid(summary: summary),
              if (draft.metrics.bmr > 0 || draft.metrics.tdee > 0) ...[
                const SizedBox(height: 12),
                _TargetEstimateNote(metrics: draft.metrics),
              ],
              const SizedBox(height: 14),
              _MacroProgress(
                label: 'Calories',
                consumed: summary.consumedCalories,
                target: summary.targetCalories,
                unit: 'kcal',
              ),
              const SizedBox(height: 10),
              _MacroProgress(
                label: 'Protein',
                consumed: summary.proteinConsumed,
                target: summary.proteinTarget,
                unit: 'g',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (foodLogs.isEmpty) ...[
          JimEmptyState(
            title: 'No food logged yet',
            message: 'Start with one meal. Manual numbers are enough for MVP.',
            actionLabel: 'Add breakfast',
            onAction: () => controller.addFoodLog(MealType.breakfast),
            icon: Icons.ramen_dining_outlined,
          ),
          const SizedBox(height: 16),
        ],
        ...MealType.values.map(
          (mealType) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _MealSection(
              mealType: mealType,
              entries: groupedMeals[mealType] ?? const [],
              onAddFood: () => controller.addFoodLog(mealType),
              onChanged: controller.updateFoodLog,
              onLog: controller.saveNutritionLogs,
              onDelete: controller.deleteFoodLog,
              onUndoDelete: controller.restoreDeletedFoodLog,
            ),
          ),
        ),
        const SizedBox(height: 16),
        JimSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hydration', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              _HydrationStepper(
                consumedLiters: summary.hydrationConsumedLiters,
                targetLiters: summary.hydrationTargetLiters,
                onChanged: controller.updateHydration,
              ),
              const SizedBox(height: 8),
              Text(
                'Hydration is kept on this screen only and is not synced yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: JimColors.terracotta,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        JimSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Jim note', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              insightAsync.when(
                loading: () => const Text('Loading nutrition insight...'),
                error: (error, stackTrace) => Text(
                  'Nutrition insight failed: ${_technicalError(error)}',
                ),
                data: (insight) => InsightCard(insight: insight),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TargetEstimateNote extends StatelessWidget {
  const _TargetEstimateNote({required this.metrics});

  final UserStaticMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return JimSurface(
      padding: const EdgeInsets.all(JimSpacing.md),
      tone: JimSurfaceTone.soft,
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: JimColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Estimate: BMR ${_formatNumber(metrics.bmr)} kcal, TDEE ${_formatNumber(metrics.tdee)} kcal. Guidance only, not medical advice.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: JimColors.inkSoft,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MealFoodLogEntry {
  const _MealFoodLogEntry({
    required this.index,
    required this.foodLog,
  });

  final int index;
  final FoodLogDraft foodLog;
}

class _MacroSummaryGrid extends StatelessWidget {
  const _MacroSummaryGrid({required this.summary});

  final DailyNutritionSummary summary;

  @override
  Widget build(BuildContext context) {
    final hasCalorieTarget = summary.targetCalories > 0;
    final hasProteinTarget = summary.proteinTarget > 0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: JimMetricCard(
                label: hasCalorieTarget ? 'Calories left' : 'Calories logged',
                value: hasCalorieTarget
                    ? '${_formatNumber(summary.remainingCalories)} kcal'
                    : '${_formatNumber(summary.consumedCalories)} kcal',
                detail: hasCalorieTarget
                    ? '${_formatNumber(summary.consumedCalories)} / ${_formatNumber(summary.targetCalories)}'
                    : 'No target set',
                icon: Icons.local_fire_department_outlined,
              ),
            ),
            const SizedBox(width: JimSpacing.sm),
            Expanded(
              child: JimMetricCard(
                label: hasProteinTarget ? 'Protein left' : 'Protein logged',
                value: hasProteinTarget
                    ? '${_formatNumber(summary.remainingProtein)} g'
                    : '${_formatNumber(summary.proteinConsumed)} g',
                detail: hasProteinTarget
                    ? '${_formatNumber(summary.proteinConsumed)} / ${_formatNumber(summary.proteinTarget)} g'
                    : 'No target set',
                icon: Icons.egg_alt_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: JimSpacing.sm),
        Row(
          children: [
            Expanded(
              child: JimMetricCard(
                label: 'Carbs',
                value: '${_formatNumber(summary.carbsConsumed)} g',
                detail: '${_formatNumber(summary.carbsTarget)} g target',
                icon: Icons.grain_rounded,
              ),
            ),
            const SizedBox(width: JimSpacing.sm),
            Expanded(
              child: JimMetricCard(
                label: 'Fat',
                value: '${_formatNumber(summary.fatConsumed)} g',
                detail: '${_formatNumber(summary.fatTarget)} g target',
                icon: Icons.opacity_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MacroProgress extends StatelessWidget {
  const _MacroProgress({
    required this.label,
    required this.consumed,
    required this.target,
    required this.unit,
  });

  final String label;
  final double consumed;
  final double target;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = target <= 0 ? 0.0 : (consumed / target).clamp(0.0, 1.0);
    final value = '${_formatNumber(consumed)} / ${_formatNumber(target)} $unit';
    final useStackedLabels = MediaQuery.textScalerOf(context).scale(1) > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (useStackedLabels)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: JimSpacing.xxs),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: JimColors.inkMuted,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: Text(label, style: theme.textTheme.labelLarge),
              ),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: JimColors.inkMuted,
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(JimRadius.pill),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: JimColors.galleryWhite,
            color: JimColors.accentStrong,
          ),
        ),
      ],
    );
  }
}

class _MealSection extends StatefulWidget {
  const _MealSection({
    required this.mealType,
    required this.entries,
    required this.onAddFood,
    required this.onChanged,
    required this.onLog,
    required this.onDelete,
    required this.onUndoDelete,
  });

  final MealType mealType;
  final List<_MealFoodLogEntry> entries;
  final VoidCallback onAddFood;
  final Future<void> Function(int index, FoodLogDraft foodLog) onChanged;
  final Future<NutritionMutationResult> Function() onLog;
  final Future<FoodLogDraft> Function(int index) onDelete;
  final Future<void> Function(int index, FoodLogDraft deleted) onUndoDelete;

  @override
  State<_MealSection> createState() => _MealSectionState();
}

class _MealSectionState extends State<_MealSection> {
  static const _pageSize = 20;
  int _visibleCount = _pageSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calories = widget.entries.fold<double>(
      0,
      (total, entry) => total + entry.foodLog.calories,
    );
    final protein = widget.entries.fold<double>(
      0,
      (total, entry) => total + entry.foodLog.protein,
    );
    final mealLabel = _mealTypeLabel(widget.mealType);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          eyebrow: mealLabel.toUpperCase(),
          title: '$mealLabel · ${_formatNumber(calories)} kcal',
          subtitle: widget.entries.isEmpty
              ? 'No foods yet'
              : '${widget.entries.length} food${widget.entries.length == 1 ? '' : 's'} · ${_formatNumber(protein)} g protein',
          trailing: IconButton.outlined(
            key: ValueKey('add-food-${widget.mealType.name}-button'),
            tooltip: 'Add $mealLabel food',
            onPressed: widget.onAddFood,
            icon: const Icon(Icons.add_rounded),
          ),
        ),
        const SizedBox(height: 10),
        if (widget.entries.isEmpty)
          JimSurface(
            padding: const EdgeInsets.all(JimSpacing.md),
            tone: JimSurfaceTone.soft,
            child: Row(
              children: [
                Icon(_mealTypeIcon(widget.mealType), color: JimColors.inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Add food when you eat this meal.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: JimColors.inkSoft,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onAddFood,
                  child: const Text('Add'),
                ),
              ],
            ),
          )
        else
          ...widget.entries.take(_visibleCount).map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FoodLogEditor(
                    index: entry.index,
                    foodLog: entry.foodLog,
                    onChanged: (foodLog) =>
                        widget.onChanged(entry.index, foodLog),
                    onLog: widget.onLog,
                    onDelete: () => widget.onDelete(entry.index),
                    onUndoDelete: (deleted) =>
                        widget.onUndoDelete(entry.index, deleted),
                  ),
                ),
              ),
        if (_visibleCount < widget.entries.length)
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _visibleCount = (_visibleCount + _pageSize).clamp(
                  0,
                  widget.entries.length,
                );
              }),
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(
                'Show more $mealLabel (${widget.entries.length - _visibleCount})',
              ),
            ),
          ),
      ],
    );
  }
}

class _FoodLogEditor extends ConsumerStatefulWidget {
  const _FoodLogEditor({
    required this.index,
    required this.foodLog,
    required this.onChanged,
    required this.onLog,
    required this.onDelete,
    required this.onUndoDelete,
  });

  final int index;
  final FoodLogDraft foodLog;
  final ValueChanged<FoodLogDraft> onChanged;
  final Future<NutritionMutationResult> Function() onLog;
  final Future<FoodLogDraft> Function() onDelete;
  final Future<void> Function(FoodLogDraft deleted) onUndoDelete;

  @override
  ConsumerState<_FoodLogEditor> createState() => _FoodLogEditorState();
}

class _HydrationStepper extends StatefulWidget {
  const _HydrationStepper({
    required this.consumedLiters,
    required this.targetLiters,
    required this.onChanged,
  });

  final double consumedLiters;
  final double targetLiters;
  final ValueChanged<double> onChanged;

  @override
  State<_HydrationStepper> createState() => _HydrationStepperState();
}

class _HydrationStepperState extends State<_HydrationStepper> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatNumber(widget.consumedLiters),
    );
  }

  @override
  void didUpdateWidget(covariant _HydrationStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _formatNumber(widget.consumedLiters);
    if (_controller.text != next) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = widget.targetLiters <= 0
        ? 'No target set'
        : 'Target ${widget.targetLiters.toStringAsFixed(1)} L';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) {
                  final parsed = double.tryParse(value);
                  if (parsed != null && parsed >= 0) {
                    widget.onChanged(parsed);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Water today',
                  suffixText: 'L',
                  prefixIcon: Icon(Icons.water_drop_outlined),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _HydrationButton(
              icon: Icons.remove_rounded,
              onTap: () => widget.onChanged(
                (widget.consumedLiters - .25).clamp(0, double.infinity),
              ),
            ),
            const SizedBox(width: 8),
            _HydrationButton(
              icon: Icons.add_rounded,
              onTap: () => widget.onChanged(widget.consumedLiters + .25),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '$target • No cap, log what you actually drank.',
          style: theme.textTheme.bodySmall?.copyWith(color: JimColors.inkMuted),
        ),
      ],
    );
  }
}

class _HydrationButton extends StatelessWidget {
  const _HydrationButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: JimColors.accentSoft,
      borderRadius: BorderRadius.circular(JimRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JimRadius.md),
        child: SizedBox(
          width: 48,
          height: 56,
          child: Icon(icon, color: JimColors.accentStrong),
        ),
      ),
    );
  }
}

enum _FoodEntryStatus { editing, logged, pendingSync, failed }

enum _FeatureSearchStatus {
  idle,
  loading,
  results,
  noResults,
  cachedOffline,
  error,
}

class _FoodLogEditorState extends ConsumerState<_FoodLogEditor> {
  Timer? _debounce;
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  List<FoodSuggestion> _suggestions = const [];
  late _FoodEntryStatus _entryStatus;
  _FeatureSearchStatus _searchStatus = _FeatureSearchStatus.idle;
  Object? _searchError;
  bool _mutationInFlight = false;
  final _searchGate = SearchRequestGate();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.foodLog.foodName);
    _quantityController = TextEditingController(
      text: _formatNumber(widget.foodLog.quantityGrams),
    );
    _entryStatus = widget.foodLog.isDirty
        ? _FoodEntryStatus.editing
        : _FoodEntryStatus.logged;
  }

  @override
  void didUpdateWidget(covariant _FoodLogEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_nameController.text != widget.foodLog.foodName) {
      _nameController.text = widget.foodLog.foodName;
    }
    final quantityText = _formatNumber(widget.foodLog.quantityGrams);
    if (_quantityController.text != quantityText) {
      _quantityController.text = quantityText;
    }
    if (oldWidget.foodLog.isDirty && !widget.foodLog.isDirty) {
      _entryStatus = _FoodEntryStatus.logged;
    } else if (!oldWidget.foodLog.isDirty && widget.foodLog.isDirty) {
      _entryStatus = _FoodEntryStatus.editing;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _queueFoodSearch(String query, {bool force = false}) {
    _debounce?.cancel();
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      _searchGate.clear();
      setState(() {
        _suggestions = const [];
        _searchStatus = _FeatureSearchStatus.idle;
        _searchError = null;
      });
      return;
    }

    if (!force &&
        normalized == _searchGate.activeQuery &&
        _searchStatus != _FeatureSearchStatus.loading) {
      return;
    }

    final generation = _searchGate.begin(normalized);
    setState(() {
      _searchStatus = _FeatureSearchStatus.loading;
      _searchError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 420), () async {
      try {
        final results = await ref
            .read(appDraftProvider.notifier)
            .searchFoodSuggestions(normalized);
        if (!mounted || !_searchGate.isCurrent(generation, normalized)) {
          return;
        }
        setState(() {
          _suggestions = results;
          _searchStatus = results.isEmpty
              ? _FeatureSearchStatus.noResults
              : _FeatureSearchStatus.results;
          _searchError = null;
        });
      } on CachedSearchResultsException<FoodSuggestion> catch (error) {
        if (!mounted || !_searchGate.isCurrent(generation, normalized)) {
          return;
        }
        setState(() {
          _suggestions = error.results;
          _searchStatus = _FeatureSearchStatus.cachedOffline;
          _searchError = error.error;
        });
      } catch (error) {
        if (!mounted || !_searchGate.isCurrent(generation, normalized)) {
          return;
        }
        setState(() {
          _suggestions = const [];
          _searchStatus = _FeatureSearchStatus.error;
          _searchError = error;
        });
      }
    });
  }

  void _markEditing() {
    if (_entryStatus != _FoodEntryStatus.editing && mounted) {
      setState(() => _entryStatus = _FoodEntryStatus.editing);
    }
  }

  Future<void> _logFood() async {
    if (_mutationInFlight || _entryStatus == _FoodEntryStatus.pendingSync) {
      return;
    }
    setState(() => _mutationInFlight = true);
    try {
      final result = await widget.onLog();
      if (!mounted) {
        return;
      }
      setState(() {
        _entryStatus = result.syncStatus == NutritionMutationSyncStatus.synced
            ? _FoodEntryStatus.logged
            : _FoodEntryStatus.pendingSync;
      });
      if (result.syncStatus == NutritionMutationSyncStatus.synced) {
        _showNutritionSuccess(context, 'Food logged and synced.');
      }
    } on NutritionMutationPendingException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _entryStatus = _FoodEntryStatus.pendingSync);
      _showNutritionFailure(context, error);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _entryStatus = _FoodEntryStatus.failed);
      _showNutritionFailure(context, error);
    } finally {
      if (mounted) {
        setState(() => _mutationInFlight = false);
      }
    }
  }

  Future<void> _deleteFood() async {
    if (_mutationInFlight) {
      return;
    }
    setState(() => _mutationInFlight = true);
    try {
      final deleted = await widget.onDelete();
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            deleted.foodLogId == null ? 'Food draft removed.' : 'Food deleted.',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await widget.onUndoDelete(deleted);
                if (messenger.mounted && deleted.foodLogId != null) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Food restored and synced.'),
                    ),
                  );
                }
              } catch (error) {
                if (messenger.mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(_friendlyNutritionError(error))),
                  );
                }
              }
            },
          ),
        ),
      );
    } on NutritionMutationPendingException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _entryStatus = _FoodEntryStatus.pendingSync);
      _showNutritionFailure(context, error);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _entryStatus = _FoodEntryStatus.failed);
      _showNutritionFailure(context, error);
    } finally {
      if (mounted) {
        setState(() => _mutationInFlight = false);
      }
    }
  }

  Widget _mealField(FoodLogDraft foodLog) {
    return DropdownButtonFormField<MealType>(
      key: ValueKey('food-meal-field-${widget.index}'),
      isExpanded: true,
      initialValue: foodLog.mealType,
      items: MealType.values
          .map(
            (mealType) => DropdownMenuItem(
              value: mealType,
              child: Text(_mealTypeLabel(mealType)),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          _markEditing();
          widget.onChanged(foodLog.copyWith(mealType: value));
        }
      },
      decoration: const InputDecoration(labelText: 'Meal type'),
    );
  }

  Widget _quantityField(FoodLogDraft foodLog) {
    return TextFormField(
      key: ValueKey('food-quantity-field-${widget.index}'),
      controller: _quantityController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (value) {
        _markEditing();
        widget.onChanged(
          foodLog.copyWith(
            quantityGrams: double.tryParse(value) ?? foodLog.quantityGrams,
          ),
        );
      },
      decoration: const InputDecoration(labelText: 'Grams'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final foodLog = widget.foodLog;
    return JimSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 400;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isCompact) ...[
                _NutritionStatusBadge(status: _entryStatus),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: ValueKey('delete-food-${widget.index}-button'),
                    onPressed: _mutationInFlight ? null : _deleteFood,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                ),
              ] else
                Row(
                  children: [
                    _NutritionStatusBadge(status: _entryStatus),
                    const Spacer(),
                    TextButton.icon(
                      key: ValueKey('delete-food-${widget.index}-button'),
                      onPressed: _mutationInFlight ? null : _deleteFood,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              TextFormField(
                key: ValueKey('food-name-field-${widget.index}'),
                controller: _nameController,
                onChanged: (value) {
                  _markEditing();
                  widget.onChanged(
                    foodLog.copyWith(
                      foodId: null,
                      caloriesPer100g: null,
                      proteinPer100g: null,
                      carbsPer100g: null,
                      fatPer100g: null,
                      foodName: value,
                    ),
                  );
                  _queueFoodSearch(value);
                },
                decoration: InputDecoration(
                  labelText: 'Food name',
                  prefixIcon: const Icon(Icons.ramen_dining_outlined),
                  suffixIcon: _searchStatus == _FeatureSearchStatus.loading
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
              if (_searchStatus == _FeatureSearchStatus.loading) ...[
                const SizedBox(height: 8),
                Text(
                  'Searching foods...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: JimColors.inkMuted,
                      ),
                ),
              ] else if (_searchStatus == _FeatureSearchStatus.noResults) ...[
                const SizedBox(height: 8),
                Text(
                  'No food results found.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: JimColors.inkMuted,
                      ),
                ),
              ] else if (_searchStatus ==
                  _FeatureSearchStatus.cachedOffline) ...[
                const SizedBox(height: 8),
                Text(
                  'Offline — showing cached food results.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: JimColors.terracotta,
                      ),
                ),
              ] else if (_searchStatus == _FeatureSearchStatus.error) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        presentAppError(
                          _searchError ?? Exception('Food search failed.'),
                          fallbackMessage:
                              'Food search is unavailable. Please try again.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: JimColors.terracotta,
                            ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _queueFoodSearch(
                        _nameController.text,
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
                      : 'Food matches',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: JimColors.inkMuted,
                      ),
                ),
                const SizedBox(height: 8),
                ..._suggestions.take(4).map(
                      (suggestion) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _FoodSuggestionTile(
                          suggestion: suggestion,
                          quantityGrams: foodLog.quantityGrams,
                          onTap: () {
                            _markEditing();
                            ref
                                .read(appDraftProvider.notifier)
                                .applyFoodSuggestion(widget.index, suggestion);
                            _searchGate.clear();
                            setState(() {
                              _suggestions = const [];
                              _searchStatus = _FeatureSearchStatus.idle;
                              _searchError = null;
                            });
                          },
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 12),
              if (isCompact) ...[
                _mealField(foodLog),
                const SizedBox(height: 12),
                _quantityField(foodLog),
              ] else
                Row(
                  children: [
                    Expanded(child: _mealField(foodLog)),
                    const SizedBox(width: 12),
                    Expanded(child: _quantityField(foodLog)),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MacroInput(
                      fieldKey: ValueKey('food-calories-field-${widget.index}'),
                      label: 'Calories',
                      initialValue: foodLog.calories,
                      onChanged: (value) {
                        _markEditing();
                        widget.onChanged(
                          foodLog.copyWith(
                            foodId: null,
                            caloriesPer100g: null,
                            proteinPer100g: null,
                            carbsPer100g: null,
                            fatPer100g: null,
                            calories: value,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MacroInput(
                      fieldKey: ValueKey('food-protein-field-${widget.index}'),
                      label: 'Protein',
                      initialValue: foodLog.protein,
                      onChanged: (value) {
                        _markEditing();
                        widget.onChanged(
                          foodLog.copyWith(
                            foodId: null,
                            caloriesPer100g: null,
                            proteinPer100g: null,
                            carbsPer100g: null,
                            fatPer100g: null,
                            protein: value,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MacroInput(
                      fieldKey: ValueKey('food-carbs-field-${widget.index}'),
                      label: 'Carbs',
                      initialValue: foodLog.carbs,
                      onChanged: (value) {
                        _markEditing();
                        widget.onChanged(
                          foodLog.copyWith(
                            foodId: null,
                            caloriesPer100g: null,
                            proteinPer100g: null,
                            carbsPer100g: null,
                            fatPer100g: null,
                            carbs: value,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MacroInput(
                      fieldKey: ValueKey('food-fat-field-${widget.index}'),
                      label: 'Fat',
                      initialValue: foodLog.fat,
                      onChanged: (value) {
                        _markEditing();
                        widget.onChanged(
                          foodLog.copyWith(
                            foodId: null,
                            caloriesPer100g: null,
                            proteinPer100g: null,
                            carbsPer100g: null,
                            fatPer100g: null,
                            fat: value,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ValueKey('log-food-${widget.index}-button'),
                  onPressed: _mutationInFlight ||
                          _entryStatus == _FoodEntryStatus.logged ||
                          _entryStatus == _FoodEntryStatus.pendingSync
                      ? null
                      : _logFood,
                  icon: _mutationInFlight
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _entryStatus == _FoodEntryStatus.failed
                              ? Icons.refresh_rounded
                              : Icons.check_rounded,
                        ),
                  label: Text(
                    _foodEntryActionLabel(
                      _entryStatus,
                      isExistingEntry: foodLog.foodLogId != null,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NutritionStatusBadge extends StatelessWidget {
  const _NutritionStatusBadge({required this.status});

  final _FoodEntryStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      _FoodEntryStatus.editing => (
          'Not logged',
          Icons.edit_outlined,
          JimColors.inkMuted,
        ),
      _FoodEntryStatus.logged => (
          'Logged',
          Icons.cloud_done_outlined,
          JimColors.accentStrong,
        ),
      _FoodEntryStatus.pendingSync => (
          'Pending sync',
          Icons.cloud_upload_outlined,
          JimColors.terracotta,
        ),
      _FoodEntryStatus.failed => (
          'Failed — retry',
          Icons.error_outline_rounded,
          JimColors.terracotta,
        ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style:
                Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

String _foodEntryActionLabel(
  _FoodEntryStatus status, {
  required bool isExistingEntry,
}) {
  return switch (status) {
    _FoodEntryStatus.editing => isExistingEntry ? 'Save changes' : 'Log food',
    _FoodEntryStatus.logged => 'Logged',
    _FoodEntryStatus.pendingSync => 'Pending sync',
    _FoodEntryStatus.failed => 'Retry logging',
  };
}

Map<MealType, List<_MealFoodLogEntry>> _groupFoodLogsByMeal(
  List<FoodLogDraft> foodLogs,
) {
  final grouped = {
    for (final mealType in MealType.values) mealType: <_MealFoodLogEntry>[],
  };
  for (final entry in foodLogs.asMap().entries) {
    grouped[entry.value.mealType]!.add(
      _MealFoodLogEntry(index: entry.key, foodLog: entry.value),
    );
  }
  return grouped;
}

String _mealTypeLabel(MealType mealType) {
  return switch (mealType) {
    MealType.breakfast => 'Breakfast',
    MealType.lunch => 'Lunch',
    MealType.dinner => 'Dinner',
    MealType.snack => 'Snack',
    MealType.preWorkout => 'Pre-workout',
    MealType.postWorkout => 'Post-workout',
  };
}

IconData _mealTypeIcon(MealType mealType) {
  return switch (mealType) {
    MealType.breakfast => Icons.free_breakfast_outlined,
    MealType.lunch => Icons.lunch_dining_outlined,
    MealType.dinner => Icons.dinner_dining_outlined,
    MealType.snack => Icons.cookie_outlined,
    MealType.preWorkout => Icons.bolt_outlined,
    MealType.postWorkout => Icons.fitness_center_outlined,
  };
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}

class _FoodSuggestionTile extends StatelessWidget {
  const _FoodSuggestionTile({
    required this.suggestion,
    required this.quantityGrams,
    required this.onTap,
  });

  final FoodSuggestion suggestion;
  final double quantityGrams;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final multiplier = quantityGrams / 100;
    final calories = suggestion.caloriesPer100g * multiplier;
    final protein = suggestion.proteinPer100g * multiplier;
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
                      '${calories.toStringAsFixed(0)} kcal • ${protein.toStringAsFixed(0)}g protein for ${quantityGrams.toStringAsFixed(0)}g',
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

void _showNutritionSuccess(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

void _showNutritionFailure(BuildContext context, Object error) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_friendlyNutritionError(error))),
  );
}

String _friendlyNutritionError(Object error) {
  if (error is NutritionMutationConflictException) {
    return 'This day changed elsewhere. Reload it before saving so newer data is not overwritten.';
  }
  if (error is NutritionMutationPendingException) {
    return 'Saved on this device — waiting to sync. Your current day is unchanged.';
  }
  return presentAppError(
    error,
    fallbackMessage:
        'We could not save that nutrition change. Your entry is still here; please try again.',
  );
}

String _technicalError(Object error) {
  return presentAppError(
    error,
    fallbackMessage: 'Nutrition data is unavailable right now.',
  );
}

class _MacroInput extends StatefulWidget {
  const _MacroInput({
    required this.fieldKey,
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final double initialValue;
  final ValueChanged<double> onChanged;

  @override
  State<_MacroInput> createState() => _MacroInputState();
}

class _MacroInputState extends State<_MacroInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatNumber(widget.initialValue),
    );
  }

  @override
  void didUpdateWidget(covariant _MacroInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = _formatNumber(widget.initialValue);
    if (_controller.text != nextText) {
      _controller.text = nextText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: widget.fieldKey,
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (value) =>
          widget.onChanged(double.tryParse(value) ?? widget.initialValue),
      decoration: InputDecoration(labelText: widget.label),
    );
  }
}

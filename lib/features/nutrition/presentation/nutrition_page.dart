import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/action_state.dart';
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
                trailing: JimGuardedIconButton(
                  tooltip: 'Save day',
                  onRun: () => controller.saveNutritionLogs(),
                  onSuccess: () => _showNutritionSuccess(
                    context,
                    'Nutrition logs saved to Supabase.',
                  ),
                  onError: (error) => _showNutritionFailure(context, error),
                  icon: Icons.save_rounded,
                ),
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
              onRemove: controller.removeFoodLog,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.labelLarge),
            ),
            Text(
              '${_formatNumber(consumed)} / ${_formatNumber(target)} $unit',
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

class _MealSection extends StatelessWidget {
  const _MealSection({
    required this.mealType,
    required this.entries,
    required this.onAddFood,
    required this.onChanged,
    required this.onRemove,
  });

  final MealType mealType;
  final List<_MealFoodLogEntry> entries;
  final VoidCallback onAddFood;
  final Future<void> Function(int index, FoodLogDraft foodLog) onChanged;
  final Future<void> Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calories = entries.fold<double>(
      0,
      (total, entry) => total + entry.foodLog.calories,
    );
    final protein = entries.fold<double>(
      0,
      (total, entry) => total + entry.foodLog.protein,
    );
    final mealLabel = _mealTypeLabel(mealType);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          eyebrow: mealLabel.toUpperCase(),
          title: '$mealLabel · ${_formatNumber(calories)} kcal',
          subtitle: entries.isEmpty
              ? 'No foods yet'
              : '${entries.length} food${entries.length == 1 ? '' : 's'} · ${_formatNumber(protein)} g protein',
          trailing: IconButton.outlined(
            key: ValueKey('add-food-${mealType.name}-button'),
            tooltip: 'Add $mealLabel food',
            onPressed: onAddFood,
            icon: const Icon(Icons.add_rounded),
          ),
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          JimSurface(
            padding: const EdgeInsets.all(JimSpacing.md),
            tone: JimSurfaceTone.soft,
            child: Row(
              children: [
                Icon(_mealTypeIcon(mealType), color: JimColors.inkMuted),
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
                  onPressed: onAddFood,
                  child: const Text('Add'),
                ),
              ],
            ),
          )
        else
          ...entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FoodLogEditor(
                index: entry.index,
                foodLog: entry.foodLog,
                onChanged: (foodLog) => onChanged(entry.index, foodLog),
                onRemove: () => onRemove(entry.index),
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
    required this.onRemove,
  });

  final int index;
  final FoodLogDraft foodLog;
  final ValueChanged<FoodLogDraft> onChanged;
  final VoidCallback onRemove;

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

class _FoodLogEditorState extends ConsumerState<_FoodLogEditor> {
  Timer? _debounce;
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  List<FoodSuggestion> _suggestions = const [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.foodLog.foodName);
    _quantityController = TextEditingController(
      text: _formatNumber(widget.foodLog.quantityGrams),
    );
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
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _queueFoodSearch(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _suggestions = const [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 320), () async {
      final results = await ref
          .read(appDraftProvider.notifier)
          .searchFoodSuggestions(trimmed);
      if (!mounted) {
        return;
      }
      setState(() {
        _suggestions = results;
        _isSearching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final foodLog = widget.foodLog;
    return JimSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Remove'),
            ),
          ),
          TextFormField(
            key: ValueKey('food-name-field-${widget.index}'),
            controller: _nameController,
            onChanged: (value) {
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
                    child: _FoodSuggestionTile(
                      suggestion: suggestion,
                      quantityGrams: foodLog.quantityGrams,
                      onTap: () {
                        ref
                            .read(appDraftProvider.notifier)
                            .applyFoodSuggestion(widget.index, suggestion);
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
                child: DropdownButtonFormField<MealType>(
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
                      widget.onChanged(foodLog.copyWith(mealType: value));
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Meal type'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _quantityController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) => widget.onChanged(
                    foodLog.copyWith(
                      quantityGrams:
                          double.tryParse(value) ?? foodLog.quantityGrams,
                    ),
                  ),
                  decoration: const InputDecoration(labelText: 'Grams'),
                ),
              ),
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
                  onChanged: (value) => widget.onChanged(
                    foodLog.copyWith(
                      foodId: null,
                      caloriesPer100g: null,
                      proteinPer100g: null,
                      carbsPer100g: null,
                      fatPer100g: null,
                      calories: value,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MacroInput(
                  fieldKey: ValueKey('food-protein-field-${widget.index}'),
                  label: 'Protein',
                  initialValue: foodLog.protein,
                  onChanged: (value) => widget.onChanged(
                    foodLog.copyWith(
                      foodId: null,
                      caloriesPer100g: null,
                      proteinPer100g: null,
                      carbsPer100g: null,
                      fatPer100g: null,
                      protein: value,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MacroInput(
                  fieldKey: ValueKey('food-carbs-field-${widget.index}'),
                  label: 'Carbs',
                  initialValue: foodLog.carbs,
                  onChanged: (value) => widget.onChanged(
                    foodLog.copyWith(
                      foodId: null,
                      caloriesPer100g: null,
                      proteinPer100g: null,
                      carbsPer100g: null,
                      fatPer100g: null,
                      carbs: value,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MacroInput(
                  fieldKey: ValueKey('food-fat-field-${widget.index}'),
                  label: 'Fat',
                  initialValue: foodLog.fat,
                  onChanged: (value) => widget.onChanged(
                    foodLog.copyWith(
                      foodId: null,
                      caloriesPer100g: null,
                      proteinPer100g: null,
                      carbsPer100g: null,
                      fatPer100g: null,
                      fat: value,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'Nutrition save timeout\nsource: lib/features/nutrition/presentation/nutrition_page.dart -> _runNutritionAction\nproblem: backend did not answer before Dio timeout\nraw: ${error.message}',
      DioExceptionType.connectionError =>
        'Nutrition save connection error\nsource: lib/features/nutrition/presentation/nutrition_page.dart -> _runNutritionAction\nproblem: Flutter could not reach FastAPI/ngrok\nraw: ${error.message}',
      DioExceptionType.badResponse => _friendlyNutritionStatusError(
          error.response?.statusCode,
          error.response?.data,
        ),
      DioExceptionType.cancel => 'The nutrition request was cancelled.',
      DioExceptionType.badCertificate =>
        'The backend TLS certificate was rejected. Check the backend URL.',
      DioExceptionType.unknown =>
        'Nutrition save failed before backend response\nsource: lib/features/nutrition/presentation/nutrition_page.dart -> _runNutritionAction\nraw: ${error.message}',
    };
  }

  final raw = error.toString().replaceFirst('Exception: ', '').trim();
  if (raw.contains('receive timeout') || raw.contains('send timeout')) {
    return 'The backend is taking longer than expected. Your food entry is still here; try again in a moment.';
  }
  return raw;
}

String _technicalError(Object error) {
  return error.toString().replaceFirst('Exception: ', '').trim();
}

String _friendlyNutritionStatusError(int? statusCode, Object? body) {
  if (statusCode == 401) {
    return 'Your session token was rejected. Sign out, sign back in, then retry nutrition save.';
  }
  if (statusCode == 422) {
    return 'The backend rejected the food payload. Check food, quantity, meal type, and macros.';
  }
  if (statusCode != null && statusCode >= 500) {
    return 'The backend hit a server error while saving food. Your entry is still here; retry after the API recovers.';
  }
  final bodyText = body?.toString() ?? 'Nutrition save failed.';
  return bodyText.length > 180 ? '${bodyText.substring(0, 180)}...' : bodyText;
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

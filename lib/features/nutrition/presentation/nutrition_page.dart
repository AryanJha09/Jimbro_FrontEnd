import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_state.dart';
import '../../../core/theme/jim_tokens.dart';
import '../../../shared/components/backend_state_view.dart';
import '../../../shared/components/insight_card.dart';
import '../../../shared/components/jim_button.dart';
import '../../../shared/components/jim_surface.dart';
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
          key: const ValueKey('nutrition-scroll-view'),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            const SectionHeader(
              eyebrow: 'NUTRITION',
              title: 'Editable food logging',
            ),
            const SizedBox(height: 18),
            JimSurface(
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryMetric(
                      label: 'Remaining calories',
                      value:
                          '${summary.remainingCalories.toStringAsFixed(0)} kcal',
                    ),
                  ),
                  Expanded(
                    child: _SummaryMetric(
                      label: 'Protein',
                      value:
                          '${summary.proteinConsumed.toStringAsFixed(0)} / ${summary.proteinTarget.toStringAsFixed(0)} g',
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
                  Text('Hydration', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Slider(
                    value: summary.hydrationConsumedLiters.clamp(
                      0,
                      summary.hydrationTargetLiters,
                    ),
                    max: summary.hydrationTargetLiters,
                    onChanged: controller.updateHydration,
                  ),
                  Text(
                    '${summary.hydrationConsumedLiters.toStringAsFixed(1)} / ${summary.hydrationTargetLiters.toStringAsFixed(1)} L',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: JimColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: JimPrimaryButton(
                    key: const ValueKey('add-food-entry-button'),
                    label: 'Add food entry',
                    icon: Icons.add_rounded,
                    onPressed: controller.addFoodLog,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: JimPrimaryButton(
                    label: 'Save nutrition',
                    icon: Icons.save_rounded,
                    onPressed: () async {
                      await _runNutritionAction(
                        context,
                        () async => controller.saveNutritionLogs(),
                        successMessage: 'Nutrition logs saved to Supabase.',
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (foodLogs.isEmpty)
              const JimSurface(
                child: Text(
                  'No food entries yet. Add your first meal and save it to Supabase.',
                ),
              )
            else
              ...foodLogs.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _FoodLogEditor(
                        index: entry.key,
                        foodLog: entry.value,
                        onChanged: (foodLog) =>
                            controller.updateFoodLog(entry.key, foodLog),
                        onRemove: () => controller.removeFoodLog(entry.key),
                      ),
                    ),
                  ),
            const SizedBox(height: 8),
            insightAsync.when(
              loading: () => const JimSurface(
                child: Text('Loading nutrition insight...'),
              ),
              error: (error, stackTrace) => JimSurface(
                child: Text('Nutrition insight failed: $error'),
              ),
              data: (insight) => InsightCard(insight: insight),
            ),
          ],
        ),
      ),
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
                          child: Text(mealType.name),
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

Future<void> _runNutritionAction(
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
      SnackBar(content: Text(_friendlyNutritionError(error))),
    );
  }
}

String _friendlyNutritionError(Object error) {
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'The backend is taking longer than expected. Your food entry is still here; try again in a moment.',
      DioExceptionType.connectionError =>
        'Could not reach the backend. Check the ngrok URL and internet connection, then retry.',
      DioExceptionType.badResponse => _friendlyNutritionStatusError(
          error.response?.statusCode,
          error.response?.data,
        ),
      DioExceptionType.cancel => 'The nutrition request was cancelled.',
      DioExceptionType.badCertificate =>
        'The backend TLS certificate was rejected. Check the backend URL.',
      DioExceptionType.unknown =>
        'Nutrition save failed before the backend responded. Please retry.',
    };
  }

  final raw = error.toString().replaceFirst('Exception: ', '').trim();
  if (raw.contains('receive timeout') || raw.contains('send timeout')) {
    return 'The backend is taking longer than expected. Your food entry is still here; try again in a moment.';
  }
  if (raw.contains('status: 401') ||
      raw.toLowerCase().contains('invalid token') ||
      raw.toLowerCase().contains('could not validate credentials')) {
    return 'Your session token was rejected. Sign out, sign back in, then retry nutrition save.';
  }
  if (raw.toLowerCase().contains('socket') ||
      raw.toLowerCase().contains('connection')) {
    return 'Could not reach the backend. Check the ngrok URL and internet connection, then retry.';
  }
  return raw.length > 180 ? '${raw.substring(0, 180)}...' : raw;
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

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(JimSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: JimColors.inkMuted,
                ),
          ),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

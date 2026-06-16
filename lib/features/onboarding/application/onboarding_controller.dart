import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/navigation/app_state.dart';
import '../../../shared/models/onboarding_models.dart';

const int onboardingSchemaVersion = 1;

enum OnboardingStepId {
  welcome('welcome'),
  goal('goal'),
  motivation('motivation'),
  experience('experience'),
  goalInsight('goal_insight'),
  activityLevel('activity_level'),
  availableTime('available_time'),
  trainingPreference('training_preference'),
  lifestyleInsight('lifestyle_insight'),
  dietaryPreference('dietary_preference'),
  age('age'),
  sex('sex'),
  height('height'),
  weight('weight'),
  coachSummary('coach_summary');

  const OnboardingStepId(this.wireValue);

  final String wireValue;

  static OnboardingStepId fromWireValue(String value) {
    for (final step in values) {
      if (step.wireValue == value || step.name == value) {
        return step;
      }
    }
    return OnboardingStepId.welcome;
  }
}

class OnboardingValidationResult {
  const OnboardingValidationResult.valid()
      : isValid = true,
        message = null;

  const OnboardingValidationResult.invalid(this.message) : isValid = false;

  final bool isValid;
  final String? message;
}

abstract class OnboardingPersistenceStore {
  Future<OnboardingPersistenceModel?> load(String userId);
  Future<void> save(OnboardingPersistenceModel model);
  Future<void> clear(String userId);
}

class SharedPreferencesOnboardingPersistenceStore
    implements OnboardingPersistenceStore {
  const SharedPreferencesOnboardingPersistenceStore(this._preferences);

  static const _prefix = 'jimbro.onboarding.v1';

  final SharedPreferences _preferences;

  @override
  Future<OnboardingPersistenceModel?> load(String userId) async {
    final key = _keyFor(userId);
    final raw = _preferences.getString(key);
    final temporaryRaw = _preferences.getString(_temporaryKeyFor(userId));
    final source = raw ?? temporaryRaw;
    if (source == null || source.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw const FormatException('Onboarding payload is not an object.');
      }
      return OnboardingPersistenceModel.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      await _preferences.setString(
        '$key.corrupt.${DateTime.now().millisecondsSinceEpoch}',
        source,
      );
      await _preferences.remove(key);
      await _preferences.remove(_temporaryKeyFor(userId));
      return null;
    }
  }

  @override
  Future<void> save(OnboardingPersistenceModel model) async {
    final key = _keyFor(model.userId);
    final temporaryKey = _temporaryKeyFor(model.userId);
    final payload = jsonEncode(model.toJson());
    await _preferences.setString(temporaryKey, payload);
    await _preferences.setString(key, payload);
    await _preferences.remove(temporaryKey);
  }

  @override
  Future<void> clear(String userId) async {
    await _preferences.remove(_keyFor(userId));
    await _preferences.remove(_temporaryKeyFor(userId));
  }

  String _keyFor(String userId) {
    return '$_prefix.${Uri.encodeComponent(userId)}';
  }

  String _temporaryKeyFor(String userId) {
    return '${_keyFor(userId)}.tmp';
  }
}

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

final onboardingPersistenceStoreProvider =
    FutureProvider<OnboardingPersistenceStore>((ref) async {
  final preferences = await ref.watch(sharedPreferencesProvider.future);
  return SharedPreferencesOnboardingPersistenceStore(preferences);
});

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, OnboardingStateModel>(
  OnboardingController.new,
  dependencies: [
    authSessionProvider,
    onboardingPersistenceStoreProvider,
  ],
);

class OnboardingController extends AsyncNotifier<OnboardingStateModel> {
  static const _localUserId = 'local';

  @override
  Future<OnboardingStateModel> build() async {
    final session = ref.watch(authSessionProvider);
    final userId = session?.userId ?? _localUserId;
    final store = await ref.watch(onboardingPersistenceStoreProvider.future);
    final saved = await store.load(userId);
    if (saved == null) {
      return _initialState();
    }
    return _repairForResume(saved.toStateModel());
  }

  Future<void> answerFitnessGoal(OnboardingFitnessGoal value) {
    return _updateAnswers(
      (answers) => answers.copyWith(fitnessGoal: value),
    );
  }

  Future<void> answerMotivation(OnboardingMotivation value) {
    return _updateAnswers(
      (answers) => answers.copyWith(motivation: value),
    );
  }

  Future<void> answerExperienceLevel(OnboardingExperienceLevel value) {
    return _updateAnswers(
      (answers) => answers.copyWith(experienceLevel: value),
    );
  }

  Future<void> answerActivityLevel(OnboardingActivityLevel value) {
    return _updateAnswers(
      (answers) => answers.copyWith(activityLevel: value),
    );
  }

  Future<void> answerAvailableTimeMin(int value) {
    return _updateAnswers(
      (answers) => answers.copyWith(availableTimeMin: value),
    );
  }

  Future<void> answerTrainingPreference(OnboardingTrainingPreference value) {
    return _updateAnswers(
      (answers) => answers.copyWith(trainingPreference: value),
    );
  }

  Future<void> answerDietaryPreference(OnboardingDietaryPreference value) {
    return _updateAnswers(
      (answers) => answers.copyWith(dietaryPreference: value),
    );
  }

  Future<void> answerAge(int value) {
    return _updateAnswers(
      (answers) => answers.copyWith(age: value),
    );
  }

  Future<void> answerSex(OnboardingSex value) {
    return _updateAnswers(
      (answers) => answers.copyWith(sex: value),
    );
  }

  Future<void> answerHeightCm(double value) {
    return _updateAnswers(
      (answers) => answers.copyWith(heightCm: value),
    );
  }

  Future<void> answerWeightKg(double value) {
    return _updateAnswers(
      (answers) => answers.copyWith(weightKg: value),
    );
  }

  Future<void> updateInference({
    required String recommendedFrequency,
    required int adherenceScore,
  }) async {
    final current = _requireState();
    final next = current.copyWith(
      inference: OnboardingInferenceResultDto(
        recommendedFrequency: recommendedFrequency.trim(),
        adherenceScore: adherenceScore.clamp(0, 100).toInt(),
        extra: current.inference.extra,
      ),
      errorMessage: null,
    );
    await _commit(next);
  }

  Future<void> continueFromCurrentStep() async {
    final current = _requireState();
    final validation = validateStep(current.currentStepId, current);
    if (!validation.isValid) {
      state = AsyncData(current.copyWith(errorMessage: validation.message));
      return;
    }

    final step = OnboardingStepId.fromWireValue(current.currentStepId);
    final completed = {
      ...current.completedStepIds,
      step.wireValue,
    }.toList(growable: false);
    final nextStep = _nextStepAfter(step);
    final next = current.copyWith(
      currentStepId: nextStep.wireValue,
      completedStepIds: completed,
      errorMessage: null,
    );
    await _commit(next);
  }

  Future<void> goBack() async {
    final current = _requireState();
    final step = OnboardingStepId.fromWireValue(current.currentStepId);
    final previousStep = _previousStepBefore(step);
    final next = current.copyWith(
      currentStepId: previousStep.wireValue,
      errorMessage: null,
    );
    await _commit(next);
  }

  Future<void> goToStep(OnboardingStepId step) async {
    final current = _requireState();
    final next = current.copyWith(
      currentStepId: step.wireValue,
      errorMessage: null,
    );
    await _commit(next);
  }

  Future<void> complete() async {
    final current = _requireState();
    final validation = validateForCompletion(current);
    if (!validation.isValid) {
      state = AsyncData(current.copyWith(errorMessage: validation.message));
      return;
    }
    final completedSteps = {
      ...current.completedStepIds,
      for (final step in OnboardingStepId.values) step.wireValue,
    }.toList(growable: false);
    final next = current.copyWith(
      currentStepId: OnboardingStepId.coachSummary.wireValue,
      completedStepIds: completedSteps,
      errorMessage: null,
    );
    await _commit(
      next,
      status: OnboardingPersistenceStatus.completed,
      completedAt: DateTime.now(),
    );
  }

  Future<void> reset() async {
    final store = await ref.read(onboardingPersistenceStoreProvider.future);
    await store.clear(_currentUserId);
    state = AsyncData(_initialState());
  }

  Future<void> retryPersist() async {
    final current = _requireState();
    await _commit(current);
  }

  OnboardingValidationResult validateForCompletion(
    OnboardingStateModel value,
  ) {
    final missingStep = _firstIncompleteStep(value);
    if (missingStep != null) {
      return OnboardingValidationResult.invalid(
        _validationMessageForStep(missingStep),
      );
    }
    if (!value.hasInferenceOutput) {
      return const OnboardingValidationResult.invalid(
        'Your coach summary is still being prepared.',
      );
    }
    return const OnboardingValidationResult.valid();
  }

  OnboardingValidationResult validateCurrentStep() {
    final current = _requireState();
    return validateStep(current.currentStepId, current);
  }

  OnboardingValidationResult validateStep(
    String stepId,
    OnboardingStateModel value,
  ) {
    final step = OnboardingStepId.fromWireValue(stepId);
    final answers = value.answers;
    return switch (step) {
      OnboardingStepId.welcome => const OnboardingValidationResult.valid(),
      OnboardingStepId.goal => answers.fitnessGoal == null
          ? OnboardingValidationResult.invalid(_validationMessageForStep(step))
          : const OnboardingValidationResult.valid(),
      OnboardingStepId.motivation => answers.motivation == null
          ? OnboardingValidationResult.invalid(_validationMessageForStep(step))
          : const OnboardingValidationResult.valid(),
      OnboardingStepId.experience => answers.experienceLevel == null
          ? OnboardingValidationResult.invalid(_validationMessageForStep(step))
          : const OnboardingValidationResult.valid(),
      OnboardingStepId.goalInsight => answers.fitnessGoal == null ||
              answers.motivation == null ||
              answers.experienceLevel == null
          ? OnboardingValidationResult.invalid(
              _validationMessageForStep(step),
            )
          : const OnboardingValidationResult.valid(),
      OnboardingStepId.activityLevel => answers.activityLevel == null
          ? OnboardingValidationResult.invalid(_validationMessageForStep(step))
          : const OnboardingValidationResult.valid(),
      OnboardingStepId.availableTime => _validateAvailableTime(answers),
      OnboardingStepId.trainingPreference => answers.trainingPreference == null
          ? OnboardingValidationResult.invalid(
              _validationMessageForStep(step),
            )
          : const OnboardingValidationResult.valid(),
      OnboardingStepId.lifestyleInsight => answers.activityLevel == null ||
              answers.availableTimeMin == null ||
              answers.trainingPreference == null
          ? OnboardingValidationResult.invalid(
              _validationMessageForStep(step),
            )
          : const OnboardingValidationResult.valid(),
      OnboardingStepId.dietaryPreference => answers.dietaryPreference == null
          ? OnboardingValidationResult.invalid(_validationMessageForStep(step))
          : const OnboardingValidationResult.valid(),
      OnboardingStepId.age => _validateAge(answers),
      OnboardingStepId.sex => answers.sex == null
          ? OnboardingValidationResult.invalid(_validationMessageForStep(step))
          : const OnboardingValidationResult.valid(),
      OnboardingStepId.height => _validateHeight(answers),
      OnboardingStepId.weight => _validateWeight(answers),
      OnboardingStepId.coachSummary => validateForCompletion(value),
    };
  }

  Future<void> _updateAnswers(
    OnboardingAnswersDto Function(OnboardingAnswersDto answers) update,
  ) async {
    final current = _requireState();
    final next = current.copyWith(
      answers: update(current.answers),
      errorMessage: null,
    );
    await _commit(next);
  }

  Future<void> _commit(
    OnboardingStateModel next, {
    OnboardingPersistenceStatus status = OnboardingPersistenceStatus.inProgress,
    DateTime? completedAt,
  }) async {
    final store = await ref.read(onboardingPersistenceStoreProvider.future);
    final now = DateTime.now();
    final persisted = OnboardingPersistenceModel.fromState(
      userId: _currentUserId,
      status: status,
      state: next,
      startedAt: _startedAtFor(next) ?? now,
      updatedAt: now,
      completedAt: completedAt,
    );
    state = AsyncData(next.copyWith(errorMessage: null));
    try {
      await store.save(persisted);
    } catch (_) {
      state = AsyncData(
        next.copyWith(
          errorMessage:
              'Your answers are still here, but they could not be saved on this device yet.',
        ),
      );
    }
  }

  OnboardingStateModel _repairForResume(OnboardingStateModel value) {
    final firstIncomplete = _firstIncompleteStep(value);
    final currentStep = OnboardingStepId.fromWireValue(value.currentStepId);
    if (firstIncomplete != null &&
        _stepIndex(currentStep) > _stepIndex(firstIncomplete)) {
      return value.copyWith(
        currentStepId: firstIncomplete.wireValue,
        errorMessage: null,
      );
    }
    return value.copyWith(errorMessage: null);
  }

  OnboardingStepId? _firstIncompleteStep(OnboardingStateModel value) {
    for (final step in OnboardingStepId.values) {
      if (step == OnboardingStepId.welcome) {
        continue;
      }
      if (step == OnboardingStepId.coachSummary) {
        if (!value.hasRequiredInferenceInputs || !value.hasInferenceOutput) {
          return step;
        }
        continue;
      }
      if (!validateStep(step.wireValue, value).isValid) {
        return step;
      }
    }
    return null;
  }

  DateTime? _startedAtFor(OnboardingStateModel state) {
    final raw = state.extra['started_at'];
    if (raw is DateTime) {
      return raw;
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  OnboardingStateModel _initialState() {
    return OnboardingStateModel(
      currentStepId: OnboardingStepId.welcome.wireValue,
      schemaVersion: onboardingSchemaVersion,
      extra: {
        'started_at': DateTime.now().toIso8601String(),
      },
    );
  }

  OnboardingStateModel _requireState() {
    final current = state.valueOrNull;
    if (current == null) {
      throw StateError('Onboarding state is not ready.');
    }
    return current;
  }

  String get _currentUserId {
    return ref.read(authSessionProvider)?.userId ?? _localUserId;
  }

  OnboardingStepId _nextStepAfter(OnboardingStepId step) {
    final index = _stepIndex(step);
    if (index >= OnboardingStepId.values.length - 1) {
      return OnboardingStepId.coachSummary;
    }
    return OnboardingStepId.values[index + 1];
  }

  OnboardingStepId _previousStepBefore(OnboardingStepId step) {
    final index = _stepIndex(step);
    if (index <= 0) {
      return OnboardingStepId.welcome;
    }
    return OnboardingStepId.values[index - 1];
  }

  int _stepIndex(OnboardingStepId step) {
    return OnboardingStepId.values.indexOf(step);
  }

  OnboardingValidationResult _validateAvailableTime(
    OnboardingAnswersDto answers,
  ) {
    final value = answers.availableTimeMin;
    if (value == null) {
      return OnboardingValidationResult.invalid(
        _validationMessageForStep(OnboardingStepId.availableTime),
      );
    }
    if (value < 10 || value > 180) {
      return const OnboardingValidationResult.invalid(
        'Choose a realistic amount of time for one workout.',
      );
    }
    return const OnboardingValidationResult.valid();
  }

  OnboardingValidationResult _validateAge(OnboardingAnswersDto answers) {
    final value = answers.age;
    if (value == null) {
      return OnboardingValidationResult.invalid(
        _validationMessageForStep(OnboardingStepId.age),
      );
    }
    if (value < 13 || value > 100) {
      return const OnboardingValidationResult.invalid(
        'Enter an age between 13 and 100.',
      );
    }
    return const OnboardingValidationResult.valid();
  }

  OnboardingValidationResult _validateHeight(OnboardingAnswersDto answers) {
    final value = answers.heightCm;
    if (value == null) {
      return OnboardingValidationResult.invalid(
        _validationMessageForStep(OnboardingStepId.height),
      );
    }
    if (value < 90 || value > 250) {
      return const OnboardingValidationResult.invalid(
        'Enter a height in centimeters that looks right.',
      );
    }
    return const OnboardingValidationResult.valid();
  }

  OnboardingValidationResult _validateWeight(OnboardingAnswersDto answers) {
    final value = answers.weightKg;
    if (value == null) {
      return OnboardingValidationResult.invalid(
        _validationMessageForStep(OnboardingStepId.weight),
      );
    }
    if (value < 30 || value > 300) {
      return const OnboardingValidationResult.invalid(
        'Enter a weight in kilograms that looks right.',
      );
    }
    return const OnboardingValidationResult.valid();
  }

  String _validationMessageForStep(OnboardingStepId step) {
    return switch (step) {
      OnboardingStepId.welcome => '',
      OnboardingStepId.goal => 'Choose the goal Jim should coach toward.',
      OnboardingStepId.motivation => 'Choose what is driving you right now.',
      OnboardingStepId.experience =>
        'Choose the starting point that feels most true.',
      OnboardingStepId.goalInsight =>
        'Finish the first few answers so Jim can reflect them back.',
      OnboardingStepId.activityLevel => 'Choose how active a normal day feels.',
      OnboardingStepId.availableTime =>
        'Choose how much time you can usually give a workout.',
      OnboardingStepId.trainingPreference =>
        'Choose where you would like to start training.',
      OnboardingStepId.lifestyleInsight =>
        'Finish your lifestyle answers so Jim can shape a realistic path.',
      OnboardingStepId.dietaryPreference =>
        'Choose how Jim should support your food habits.',
      OnboardingStepId.age => 'Enter your age.',
      OnboardingStepId.sex => 'Choose the option Jim should use for estimates.',
      OnboardingStepId.height => 'Enter your height.',
      OnboardingStepId.weight => 'Enter your weight.',
      OnboardingStepId.coachSummary =>
        'Finish the setup so Jim can build your summary.',
    };
  }
}

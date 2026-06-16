enum OnboardingFitnessGoal {
  buildMuscle('build_muscle'),
  getStronger('get_stronger'),
  loseWeight('lose_weight'),
  feelFitter('feel_fitter'),
  stayConsistent('stay_consistent');

  const OnboardingFitnessGoal(this.wireValue);

  final String wireValue;

  static OnboardingFitnessGoal? fromWireValue(Object? value) {
    return _enumFromWireValue(values, value, (entry) => entry.wireValue);
  }
}

enum OnboardingMotivation {
  feelBetter('feel_better'),
  moreEnergy('more_energy'),
  lookDifferent('look_different'),
  moreDiscipline('more_discipline'),
  eventOrMilestone('event_or_milestone');

  const OnboardingMotivation(this.wireValue);

  final String wireValue;

  static OnboardingMotivation? fromWireValue(Object? value) {
    return _enumFromWireValue(values, value, (entry) => entry.wireValue);
  }
}

enum OnboardingExperienceLevel {
  justStarting('just_starting'),
  inconsistent('inconsistent'),
  regular('regular'),
  established('established');

  const OnboardingExperienceLevel(this.wireValue);

  final String wireValue;

  static OnboardingExperienceLevel? fromWireValue(Object? value) {
    return _enumFromWireValue(values, value, (entry) => entry.wireValue);
  }
}

enum OnboardingActivityLevel {
  mostlySitting('mostly_sitting'),
  lightlyActive('lightly_active'),
  moderatelyActive('moderately_active'),
  veryActive('very_active'),
  changesALot('changes_a_lot');

  const OnboardingActivityLevel(this.wireValue);

  final String wireValue;

  static OnboardingActivityLevel? fromWireValue(Object? value) {
    return _enumFromWireValue(values, value, (entry) => entry.wireValue);
  }
}

enum OnboardingTrainingPreference {
  gym('gym'),
  home('home'),
  bodyweight('bodyweight'),
  mixed('mixed'),
  unsure('unsure');

  const OnboardingTrainingPreference(this.wireValue);

  final String wireValue;

  static OnboardingTrainingPreference? fromWireValue(Object? value) {
    return _enumFromWireValue(values, value, (entry) => entry.wireValue);
  }
}

enum OnboardingDietaryPreference {
  simple('simple'),
  protein('protein'),
  calories('calories'),
  mealPlanning('meal_planning'),
  notNow('not_now');

  const OnboardingDietaryPreference(this.wireValue);

  final String wireValue;

  static OnboardingDietaryPreference? fromWireValue(Object? value) {
    return _enumFromWireValue(values, value, (entry) => entry.wireValue);
  }
}

enum OnboardingSex {
  female('female'),
  male('male'),
  preferNotToSay('prefer_not_to_say');

  const OnboardingSex(this.wireValue);

  final String wireValue;

  static OnboardingSex? fromWireValue(Object? value) {
    return _enumFromWireValue(values, value, (entry) => entry.wireValue);
  }
}

enum OnboardingPersistenceStatus {
  notStarted('not_started'),
  inProgress('in_progress'),
  completed('completed');

  const OnboardingPersistenceStatus(this.wireValue);

  final String wireValue;

  static OnboardingPersistenceStatus fromWireValue(Object? value) {
    return _enumFromWireValue(values, value, (entry) => entry.wireValue) ??
        OnboardingPersistenceStatus.notStarted;
  }
}

const Object _unset = Object();

class OnboardingAnswersDto {
  const OnboardingAnswersDto({
    this.age,
    this.sex,
    this.heightCm,
    this.weightKg,
    this.fitnessGoal,
    this.motivation,
    this.experienceLevel,
    this.activityLevel,
    this.availableTimeMin,
    this.trainingPreference,
    this.dietaryPreference,
    this.extra = const <String, Object?>{},
  });

  final int? age;
  final OnboardingSex? sex;
  final double? heightCm;
  final double? weightKg;
  final OnboardingFitnessGoal? fitnessGoal;
  final OnboardingMotivation? motivation;
  final OnboardingExperienceLevel? experienceLevel;
  final OnboardingActivityLevel? activityLevel;
  final int? availableTimeMin;
  final OnboardingTrainingPreference? trainingPreference;
  final OnboardingDietaryPreference? dietaryPreference;
  final Map<String, Object?> extra;

  factory OnboardingAnswersDto.fromJson(Map<String, Object?> json) {
    return OnboardingAnswersDto(
      age: _toInt(json['age']),
      sex: OnboardingSex.fromWireValue(json['sex']),
      heightCm: _toDouble(json['height_cm']),
      weightKg: _toDouble(json['weight_kg']),
      fitnessGoal: OnboardingFitnessGoal.fromWireValue(json['fitness_goal']),
      motivation: OnboardingMotivation.fromWireValue(json['motivation']),
      experienceLevel:
          OnboardingExperienceLevel.fromWireValue(json['experience_level']),
      activityLevel:
          OnboardingActivityLevel.fromWireValue(json['activity_level']),
      availableTimeMin: _toInt(json['available_time_min']),
      trainingPreference: OnboardingTrainingPreference.fromWireValue(
        json['training_preference'],
      ),
      dietaryPreference: OnboardingDietaryPreference.fromWireValue(
        json['dietary_preference'],
      ),
      extra: _toMap(json['extra']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'age': age,
      'sex': sex?.wireValue,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'fitness_goal': fitnessGoal?.wireValue,
      'motivation': motivation?.wireValue,
      'experience_level': experienceLevel?.wireValue,
      'activity_level': activityLevel?.wireValue,
      'available_time_min': availableTimeMin,
      'training_preference': trainingPreference?.wireValue,
      'dietary_preference': dietaryPreference?.wireValue,
      'extra': extra,
    };
  }

  OnboardingAnswersDto copyWith({
    Object? age = _unset,
    Object? sex = _unset,
    Object? heightCm = _unset,
    Object? weightKg = _unset,
    Object? fitnessGoal = _unset,
    Object? motivation = _unset,
    Object? experienceLevel = _unset,
    Object? activityLevel = _unset,
    Object? availableTimeMin = _unset,
    Object? trainingPreference = _unset,
    Object? dietaryPreference = _unset,
    Map<String, Object?>? extra,
  }) {
    return OnboardingAnswersDto(
      age: identical(age, _unset) ? this.age : age as int?,
      sex: identical(sex, _unset) ? this.sex : sex as OnboardingSex?,
      heightCm:
          identical(heightCm, _unset) ? this.heightCm : heightCm as double?,
      weightKg:
          identical(weightKg, _unset) ? this.weightKg : weightKg as double?,
      fitnessGoal: identical(fitnessGoal, _unset)
          ? this.fitnessGoal
          : fitnessGoal as OnboardingFitnessGoal?,
      motivation: identical(motivation, _unset)
          ? this.motivation
          : motivation as OnboardingMotivation?,
      experienceLevel: identical(experienceLevel, _unset)
          ? this.experienceLevel
          : experienceLevel as OnboardingExperienceLevel?,
      activityLevel: identical(activityLevel, _unset)
          ? this.activityLevel
          : activityLevel as OnboardingActivityLevel?,
      availableTimeMin: identical(availableTimeMin, _unset)
          ? this.availableTimeMin
          : availableTimeMin as int?,
      trainingPreference: identical(trainingPreference, _unset)
          ? this.trainingPreference
          : trainingPreference as OnboardingTrainingPreference?,
      dietaryPreference: identical(dietaryPreference, _unset)
          ? this.dietaryPreference
          : dietaryPreference as OnboardingDietaryPreference?,
      extra: extra ?? this.extra,
    );
  }
}

class OnboardingInferenceResultDto {
  const OnboardingInferenceResultDto({
    this.recommendedFrequency,
    this.adherenceScore,
    this.extra = const <String, Object?>{},
  });

  final String? recommendedFrequency;
  final int? adherenceScore;
  final Map<String, Object?> extra;

  factory OnboardingInferenceResultDto.fromJson(Map<String, Object?> json) {
    return OnboardingInferenceResultDto(
      recommendedFrequency: json['recommended_frequency']?.toString(),
      adherenceScore: _toInt(json['adherence_score']),
      extra: _toMap(json['extra']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'recommended_frequency': recommendedFrequency,
      'adherence_score': adherenceScore,
      'extra': extra,
    };
  }

  OnboardingInferenceResultDto copyWith({
    Object? recommendedFrequency = _unset,
    Object? adherenceScore = _unset,
    Map<String, Object?>? extra,
  }) {
    return OnboardingInferenceResultDto(
      recommendedFrequency: identical(recommendedFrequency, _unset)
          ? this.recommendedFrequency
          : recommendedFrequency as String?,
      adherenceScore: identical(adherenceScore, _unset)
          ? this.adherenceScore
          : adherenceScore as int?,
      extra: extra ?? this.extra,
    );
  }
}

class OnboardingStateModel {
  const OnboardingStateModel({
    required this.currentStepId,
    this.completedStepIds = const <String>[],
    this.answers = const OnboardingAnswersDto(),
    this.inference = const OnboardingInferenceResultDto(),
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.schemaVersion = 1,
    this.extra = const <String, Object?>{},
  });

  final String currentStepId;
  final List<String> completedStepIds;
  final OnboardingAnswersDto answers;
  final OnboardingInferenceResultDto inference;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final int schemaVersion;
  final Map<String, Object?> extra;

  bool get hasRequiredInferenceInputs {
    return answers.fitnessGoal != null &&
        answers.motivation != null &&
        answers.experienceLevel != null &&
        answers.activityLevel != null &&
        answers.availableTimeMin != null &&
        answers.trainingPreference != null &&
        answers.dietaryPreference != null &&
        answers.age != null &&
        answers.sex != null &&
        answers.heightCm != null &&
        answers.weightKg != null;
  }

  bool get hasInferenceOutput {
    return inference.recommendedFrequency != null &&
        inference.adherenceScore != null;
  }

  OnboardingStateModel copyWith({
    String? currentStepId,
    List<String>? completedStepIds,
    OnboardingAnswersDto? answers,
    OnboardingInferenceResultDto? inference,
    bool? isLoading,
    bool? isSaving,
    Object? errorMessage = _unset,
    int? schemaVersion,
    Map<String, Object?>? extra,
  }) {
    return OnboardingStateModel(
      currentStepId: currentStepId ?? this.currentStepId,
      completedStepIds: completedStepIds ?? this.completedStepIds,
      answers: answers ?? this.answers,
      inference: inference ?? this.inference,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      extra: extra ?? this.extra,
    );
  }
}

class OnboardingPersistenceModel {
  const OnboardingPersistenceModel({
    required this.userId,
    required this.status,
    required this.currentStepId,
    required this.answers,
    required this.inference,
    required this.startedAt,
    required this.updatedAt,
    this.completedStepIds = const <String>[],
    this.completedAt,
    this.schemaVersion = 1,
    this.extra = const <String, Object?>{},
  });

  final String userId;
  final OnboardingPersistenceStatus status;
  final String currentStepId;
  final List<String> completedStepIds;
  final OnboardingAnswersDto answers;
  final OnboardingInferenceResultDto inference;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final int schemaVersion;
  final Map<String, Object?> extra;

  factory OnboardingPersistenceModel.fromJson(Map<String, Object?> json) {
    return OnboardingPersistenceModel(
      userId: json['user_id']?.toString() ?? '',
      status: OnboardingPersistenceStatus.fromWireValue(json['status']),
      currentStepId: json['current_step_id']?.toString() ?? 'welcome',
      completedStepIds: _toStringList(json['completed_step_ids']),
      answers: OnboardingAnswersDto.fromJson(_toMap(json['answers'])),
      inference: OnboardingInferenceResultDto.fromJson(
        _toMap(json['inference']),
      ),
      startedAt: _toDateTime(json['started_at']) ?? DateTime.now(),
      updatedAt: _toDateTime(json['updated_at']) ?? DateTime.now(),
      completedAt: _toDateTime(json['completed_at']),
      schemaVersion: _toInt(json['schema_version']) ?? 1,
      extra: _toMap(json['extra']),
    );
  }

  factory OnboardingPersistenceModel.fromState({
    required String userId,
    required OnboardingPersistenceStatus status,
    required OnboardingStateModel state,
    required DateTime startedAt,
    required DateTime updatedAt,
    DateTime? completedAt,
  }) {
    return OnboardingPersistenceModel(
      userId: userId,
      status: status,
      currentStepId: state.currentStepId,
      completedStepIds: state.completedStepIds,
      answers: state.answers,
      inference: state.inference,
      startedAt: startedAt,
      updatedAt: updatedAt,
      completedAt: completedAt,
      schemaVersion: state.schemaVersion,
      extra: state.extra,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'user_id': userId,
      'status': status.wireValue,
      'current_step_id': currentStepId,
      'completed_step_ids': completedStepIds,
      'answers': answers.toJson(),
      'inference': inference.toJson(),
      'started_at': startedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'schema_version': schemaVersion,
      'extra': extra,
    };
  }

  OnboardingStateModel toStateModel() {
    return OnboardingStateModel(
      currentStepId: currentStepId,
      completedStepIds: completedStepIds,
      answers: answers,
      inference: inference,
      schemaVersion: schemaVersion,
      extra: extra,
    );
  }

  OnboardingPersistenceModel copyWith({
    String? userId,
    OnboardingPersistenceStatus? status,
    String? currentStepId,
    List<String>? completedStepIds,
    OnboardingAnswersDto? answers,
    OnboardingInferenceResultDto? inference,
    DateTime? startedAt,
    DateTime? updatedAt,
    Object? completedAt = _unset,
    int? schemaVersion,
    Map<String, Object?>? extra,
  }) {
    return OnboardingPersistenceModel(
      userId: userId ?? this.userId,
      status: status ?? this.status,
      currentStepId: currentStepId ?? this.currentStepId,
      completedStepIds: completedStepIds ?? this.completedStepIds,
      answers: answers ?? this.answers,
      inference: inference ?? this.inference,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      extra: extra ?? this.extra,
    );
  }
}

T? _enumFromWireValue<T extends Enum>(
  List<T> values,
  Object? value,
  String Function(T entry) wireValue,
) {
  if (value == null) {
    return null;
  }
  final text = value.toString();
  for (final entry in values) {
    if (wireValue(entry) == text || entry.name == text) {
      return entry;
    }
  }
  return null;
}

int? _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double? _toDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

DateTime? _toDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

Map<String, Object?> _toMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(value);
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
  return const <String, Object?>{};
}

List<String> _toStringList(Object? value) {
  if (value is List) {
    return List<String>.unmodifiable(value.map((entry) => entry.toString()));
  }
  return const <String>[];
}

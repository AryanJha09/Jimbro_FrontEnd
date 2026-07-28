import '../../shared/models/app_models.dart';
import '../errors/profile_schema_exception.dart';

class ApiEnvelope<T> {
  const ApiEnvelope({
    required this.success,
    required this.data,
    required this.topLevelKeys,
  });

  final bool success;
  final T? data;
  final List<String> topLevelKeys;

  static ApiEnvelope<T> fromJson<T>(
    Object? raw,
    T Function(Map<String, Object?> data, List<String> topLevelKeys) parseData,
  ) {
    final stackTrace = StackTrace.current;
    if (raw is! Map) {
      throw ProfileSchemaException(
        stage: ProfileProcessingStage.envelopeExtraction,
        sanitizedMessage: 'The profile response envelope is not an object.',
        exceptionType: raw.runtimeType.toString(),
        stackTrace: stackTrace,
      );
    }
    final envelope = Map<String, Object?>.from(raw);
    final topLevelKeys = envelope.keys.toList(growable: false)..sort();
    final success = envelope['success'];
    if (success is! bool) {
      throw ProfileSchemaException(
        stage: ProfileProcessingStage.envelopeExtraction,
        sanitizedMessage:
            'The profile response success field is not a boolean.',
        exceptionType: success.runtimeType.toString(),
        stackTrace: stackTrace,
        topLevelKeys: topLevelKeys,
      );
    }

    final rawData = envelope['data'];
    if (rawData == null) {
      return ApiEnvelope<T>(
        success: success,
        data: null,
        topLevelKeys: topLevelKeys,
      );
    }
    if (rawData is! Map) {
      throw ProfileSchemaException(
        stage: ProfileProcessingStage.envelopeExtraction,
        sanitizedMessage: 'The profile response data field is not an object.',
        exceptionType: rawData.runtimeType.toString(),
        stackTrace: stackTrace,
        topLevelKeys: topLevelKeys,
      );
    }
    final data = Map<String, Object?>.from(rawData);
    return ApiEnvelope<T>(
      success: success,
      data: parseData(data, topLevelKeys),
      topLevelKeys: topLevelKeys,
    );
  }
}

enum ProfileSex {
  male('male'),
  female('female');

  const ProfileSex(this.wireValue);
  final String wireValue;
}

enum ProfileActivityLevel {
  sedentary('sedentary'),
  lightlyActive('lightly_active'),
  moderatelyActive('moderately_active'),
  veryActive('very_active'),
  extremelyActive('extremely_active');

  const ProfileActivityLevel(this.wireValue);
  final String wireValue;
}

enum ProfileFitnessGoal {
  loseFat('lose_fat'),
  maintain('maintain'),
  gainMuscle('gain_muscle'),
  athleticPerformance('athletic_performance'),
  recomp('recomp');

  const ProfileFitnessGoal(this.wireValue);
  final String wireValue;
}

enum ProfileExperienceLevel {
  novice('novice'),
  advancedBeginner('advanced_beginner'),
  intermediate('intermediate'),
  expert('expert');

  const ProfileExperienceLevel(this.wireValue);
  final String wireValue;
}

enum ProfileEquipmentAccess {
  fullGym('full_gym'),
  dumbbellsBench('dumbbells_bench'),
  homeGym('home_gym'),
  bodyweightOnly('bodyweight_only');

  const ProfileEquipmentAccess(this.wireValue);
  final String wireValue;
}

enum ProfileDietaryPreference {
  omnivore('omnivore'),
  vegetarian('vegetarian'),
  vegan('vegan'),
  keto('keto'),
  other('other');

  const ProfileDietaryPreference(this.wireValue);
  final String wireValue;
}

class ProfileApiDto {
  const ProfileApiDto({
    required this.userId,
    required this.onboardingCompleted,
    this.id,
    this.authUserId,
    this.email,
    this.username,
    this.age,
    this.heightCm,
    this.weightKg,
    this.sex,
    this.activityLevel,
    this.fitnessGoal,
    this.experienceLevel,
    this.availableTimeMin,
    this.equipmentAccess,
    this.dietaryPreference,
    this.allergies,
    this.foodAvailability,
    this.budget,
    this.hostelMess,
    this.gymAccess,
    this.timeOfDay,
    this.sleepQuality,
    this.steps,
    this.stressLevel,
    this.constraintsJson,
    this.profileStatus,
    this.createdAt,
    this.updatedAt,
    this.reconciled = false,
    this.coachingPreference,
    this.goalTimeframe,
    this.weeksActive,
    this.prefersVoiceLogging,
  });

  final String userId;
  final String? id;
  final String? authUserId;
  final String? email;
  final String? username;
  final int? age;
  final double? heightCm;
  final double? weightKg;
  final ProfileSex? sex;
  final ProfileActivityLevel? activityLevel;
  final ProfileFitnessGoal? fitnessGoal;
  final ProfileExperienceLevel? experienceLevel;
  final int? availableTimeMin;
  final ProfileEquipmentAccess? equipmentAccess;
  final ProfileDietaryPreference? dietaryPreference;
  final List<String>? allergies;
  final List<String>? foodAvailability;
  final double? budget;
  final bool? hostelMess;
  final bool? gymAccess;
  final String? timeOfDay;
  final String? sleepQuality;
  final int? steps;
  final String? stressLevel;
  final List<String>? constraintsJson;
  final bool? onboardingCompleted;
  final String? profileStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool reconciled;
  final String? coachingPreference;
  final String? goalTimeframe;
  final int? weeksActive;
  final bool? prefersVoiceLogging;

  bool get isOnboardingComplete => onboardingCompleted == true;

  factory ProfileApiDto.fromJson(
    Map<String, Object?> json, {
    List<String> topLevelKeys = const <String>[],
  }) {
    final dataKeys = json.keys.toList(growable: false)..sort();
    final fieldShapes = profileFieldShapes(json);
    ProfileSchemaException schemaError(
      String message,
      Object? cause,
      StackTrace stackTrace,
    ) {
      return ProfileSchemaException(
        stage: ProfileProcessingStage.dtoParsing,
        sanitizedMessage: message,
        exceptionType: cause.runtimeType.toString(),
        stackTrace: stackTrace,
        topLevelKeys: topLevelKeys,
        dataKeys: dataKeys,
        fieldShapes: fieldShapes,
      );
    }

    try {
      if (json.containsKey('profile') || json.containsKey('user')) {
        throw const FormatException(
          'Nested profile objects are not part of the profile contract.',
        );
      }
      final userId = _requiredIdentifier(json['user_id'], 'user_id');
      return ProfileApiDto(
        userId: userId,
        id: _nullableIdentifier(json['id'], 'id'),
        authUserId: _nullableString(json['auth_user_id'], 'auth_user_id'),
        email: _nullableString(json['email'], 'email'),
        username: _nullableString(json['username'], 'username'),
        age: _nullableInt(json['age'], 'age'),
        heightCm: _nullableDouble(json['height_cm'], 'height_cm'),
        weightKg: _nullableDouble(json['weight_kg'], 'weight_kg'),
        sex: _nullableEnum(ProfileSex.values, json['sex'], 'sex'),
        activityLevel: _nullableEnum(
          ProfileActivityLevel.values,
          json['activity_level'],
          'activity_level',
        ),
        fitnessGoal: _nullableEnum(
          ProfileFitnessGoal.values,
          json['fitness_goal'],
          'fitness_goal',
        ),
        experienceLevel: _nullableEnum(
          ProfileExperienceLevel.values,
          json['experience_level'],
          'experience_level',
        ),
        availableTimeMin:
            _nullableInt(json['available_time_min'], 'available_time_min'),
        equipmentAccess: _nullableEnum(
          ProfileEquipmentAccess.values,
          json['equipment_access'],
          'equipment_access',
        ),
        dietaryPreference: _nullableEnum(
          ProfileDietaryPreference.values,
          json['dietary_preference'],
          'dietary_preference',
        ),
        allergies: _nullableStringList(json['allergies'], 'allergies'),
        foodAvailability: _nullableStringList(
          json['food_availability'],
          'food_availability',
        ),
        budget: _nullableDouble(json['budget'], 'budget'),
        hostelMess: _nullableBool(json['hostel_mess'], 'hostel_mess'),
        gymAccess: _nullableBool(json['gym_access'], 'gym_access'),
        timeOfDay: _nullableString(json['time_of_day'], 'time_of_day'),
        sleepQuality: _nullableString(json['sleep_quality'], 'sleep_quality'),
        steps: _nullableInt(json['steps'], 'steps'),
        stressLevel: _nullableString(json['stress_level'], 'stress_level'),
        constraintsJson: _nullableStringList(
          json['constraints_json'],
          'constraints_json',
        ),
        onboardingCompleted: _nullableBool(
          json['onboarding_completed'],
          'onboarding_completed',
        ),
        profileStatus:
            _nullableString(json['profile_status'], 'profile_status'),
        createdAt: _nullableDateTime(json['created_at'], 'created_at'),
        updatedAt: _nullableDateTime(json['updated_at'], 'updated_at'),
        reconciled: _nullableBool(json['reconciled'], 'reconciled') == true ||
            _nullableBool(
                  json['auth_user_reconciled'],
                  'auth_user_reconciled',
                ) ==
                true,
        coachingPreference: _nullableString(
          json['coaching_preference'],
          'coaching_preference',
        ),
        goalTimeframe:
            _nullableString(json['goal_timeframe'], 'goal_timeframe'),
        weeksActive: _nullableInt(json['weeks_active'], 'weeks_active'),
        prefersVoiceLogging: _nullableBool(
          json['prefers_voice_logging'],
          'prefers_voice_logging',
        ),
      );
    } on ProfileSchemaException {
      rethrow;
    } catch (error, stackTrace) {
      throw schemaError(
        error is FormatException
            ? error.message
            : 'The profile contains a field with an unsupported type.',
        error,
        stackTrace,
      );
    }
  }

  UserProfile toDomain({required String fallbackName}) {
    try {
      return UserProfile(
        name: _nonEmpty(username) ?? fallbackName,
        goal: _fitnessGoalLabel(fitnessGoal),
        coachingPreference: coachingPreference,
        userLevel: _userLevel(experienceLevel),
        age: age,
        heightCm: heightCm,
        weightKg: weightKg,
        sex: sex?.wireValue,
        availableTimeMinutes: availableTimeMin,
        trainingPreference: _equipmentLabel(equipmentAccess),
        activityLevel: _activityLabel(activityLevel),
        dietaryPreference: dietaryPreference?.wireValue,
        goalTimeframe: goalTimeframe,
        weeksActive: weeksActive,
        prefersVoiceLogging: prefersVoiceLogging,
      );
    } catch (error, stackTrace) {
      throw ProfileSchemaException(
        stage: ProfileProcessingStage.domainMapping,
        sanitizedMessage:
            'The decoded profile could not be mapped to the app profile.',
        exceptionType: error.runtimeType.toString(),
        stackTrace: stackTrace,
      );
    }
  }
}

Map<String, String> profileFieldShapes(Map<String, Object?> data) {
  return {
    for (final entry in data.entries) entry.key: _shapeOf(entry.value),
  };
}

String _shapeOf(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is List) {
    return 'List<dynamic>';
  }
  if (value is Map) {
    return 'Map<dynamic, dynamic>';
  }
  return value.runtimeType.toString();
}

String _requiredIdentifier(Object? value, String field) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is int) {
    return value.toString();
  }
  throw FormatException(
      'Mandatory profile field $field is missing or invalid.');
}

String? _nullableIdentifier(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is int) {
    return value.toString();
  }
  throw FormatException('Profile field $field is invalid.');
}

String? _nullableString(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Profile field $field must be a string or null.');
  }
  return _nonEmpty(value);
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

int? _nullableInt(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw FormatException('Profile field $field must be an integer or null.');
}

double? _nullableDouble(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  throw FormatException('Profile field $field must be numeric or null.');
}

bool? _nullableBool(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('Profile field $field must be a boolean or null.');
}

List<String>? _nullableStringList(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! List || value.any((entry) => entry is! String)) {
    throw FormatException(
      'Profile field $field must be a string list or null.',
    );
  }
  return List<String>.unmodifiable(value.cast<String>());
}

DateTime? _nullableDateTime(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException(
      'Profile field $field must be an ISO-8601 string or null.',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException(
      'Profile field $field must be an ISO-8601 string or null.',
    );
  }
  return parsed;
}

T? _nullableEnum<T extends Enum>(
  List<T> values,
  Object? value,
  String field,
) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Profile field $field must be a string or null.');
  }
  for (final entry in values) {
    final wireValue = (entry as dynamic).wireValue as String;
    if (wireValue == value) {
      return entry;
    }
  }
  throw FormatException('Profile field $field has an unsupported value.');
}

String? _fitnessGoalLabel(ProfileFitnessGoal? value) {
  return switch (value) {
    ProfileFitnessGoal.loseFat => 'Lose fat',
    ProfileFitnessGoal.maintain => 'Maintain',
    ProfileFitnessGoal.gainMuscle => 'Build muscle',
    ProfileFitnessGoal.athleticPerformance => 'Get stronger',
    ProfileFitnessGoal.recomp => 'Recomp',
    null => null,
  };
}

String? _activityLabel(ProfileActivityLevel? value) {
  return switch (value) {
    ProfileActivityLevel.sedentary => 'Mostly sitting',
    ProfileActivityLevel.lightlyActive => 'Lightly active',
    ProfileActivityLevel.moderatelyActive => 'Moderately active',
    ProfileActivityLevel.veryActive => 'Very active',
    ProfileActivityLevel.extremelyActive => 'Extremely active',
    null => null,
  };
}

String? _equipmentLabel(ProfileEquipmentAccess? value) {
  return switch (value) {
    ProfileEquipmentAccess.fullGym => 'Gym workouts',
    ProfileEquipmentAccess.dumbbellsBench => 'A flexible mix',
    ProfileEquipmentAccess.homeGym => 'Home workouts',
    ProfileEquipmentAccess.bodyweightOnly => 'Bodyweight',
    null => null,
  };
}

UserLevel? _userLevel(ProfileExperienceLevel? value) {
  return switch (value) {
    ProfileExperienceLevel.novice => UserLevel.beginner,
    ProfileExperienceLevel.advancedBeginner => UserLevel.beginner,
    ProfileExperienceLevel.intermediate => UserLevel.intermediate,
    ProfileExperienceLevel.expert => UserLevel.advanced,
    null => null,
  };
}

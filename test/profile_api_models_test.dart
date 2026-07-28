import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/core/errors/profile_schema_exception.dart';
import 'package:jimbro/core/models/profile_api_models.dart';

void main() {
  test('flat success/data response parses a complete canonical profile', () {
    final envelope = ApiEnvelope.fromJson<ProfileApiDto>(
      {
        'success': true,
        'data': {
          'user_id': 'app-user-1',
          'auth_user_id': 'auth-user-1',
          'email': 'person@example.com',
          'username': 'Athlete',
          'age': 30,
          'height_cm': '180.5',
          'weight_kg': 80,
          'sex': 'male',
          'activity_level': 'moderately_active',
          'fitness_goal': 'gain_muscle',
          'experience_level': 'intermediate',
          'available_time_min': 45,
          'equipment_access': 'full_gym',
          'dietary_preference': 'vegetarian',
          'constraints_json': ['knee_sensitive'],
          'onboarding_completed': true,
          'created_at': '2026-07-28T18:36:22.123587Z',
          'updated_at': null,
        },
      },
      (data, keys) => ProfileApiDto.fromJson(
        data,
        topLevelKeys: keys,
      ),
    );

    expect(envelope.success, isTrue);
    expect(envelope.topLevelKeys, ['data', 'success']);
    expect(envelope.data?.userId, 'app-user-1');
    expect(envelope.data?.heightCm, 180.5);
    expect(
      envelope.data?.dietaryPreference,
      ProfileDietaryPreference.vegetarian,
    );
    expect(envelope.data?.constraintsJson, ['knee_sensitive']);
    expect(envelope.data?.isOnboardingComplete, isTrue);
    expect(envelope.data?.createdAt?.isUtc, isTrue);
  });

  test('partial profile preserves nullable onboarding fields', () {
    final dto = _profile({
      'age': null,
      'activity_level': null,
      'dietary_preference': null,
      'constraints_json': null,
      'onboarding_completed': false,
    });
    final domain = dto.toDomain(fallbackName: 'Signed-in user');

    expect(dto.age, isNull);
    expect(dto.activityLevel, isNull);
    expect(dto.dietaryPreference, isNull);
    expect(dto.constraintsJson, isNull);
    expect(dto.isOnboardingComplete, isFalse);
    expect(domain.age, isNull);
    expect(domain.activityLevel, isNull);
    expect(domain.dietaryPreference, isNull);
  });

  test('null onboarding flag means incomplete rather than malformed', () {
    final dto = _profile({'onboarding_completed': null});

    expect(dto.onboardingCompleted, isNull);
    expect(dto.isOnboardingComplete, isFalse);
  });

  test('every documented profile enum wire value decodes centrally', () {
    for (final value in ProfileSex.values) {
      expect(_profile({'sex': value.wireValue}).sex, value);
    }
    for (final value in ProfileActivityLevel.values) {
      expect(
        _profile({'activity_level': value.wireValue}).activityLevel,
        value,
      );
    }
    for (final value in ProfileFitnessGoal.values) {
      expect(_profile({'fitness_goal': value.wireValue}).fitnessGoal, value);
    }
    for (final value in ProfileExperienceLevel.values) {
      expect(
        _profile({'experience_level': value.wireValue}).experienceLevel,
        value,
      );
    }
    for (final value in ProfileEquipmentAccess.values) {
      expect(
        _profile({'equipment_access': value.wireValue}).equipmentAccess,
        value,
      );
    }
    for (final value in ProfileDietaryPreference.values) {
      expect(
        _profile({'dietary_preference': value.wireValue}).dietaryPreference,
        value,
      );
    }
  });

  test('unsupported enum value produces a controlled schema error', () {
    expect(
      () => _profile({'activity_level': 'sometimes_active'}),
      throwsA(
        isA<ProfileSchemaException>()
            .having(
              (error) => error.stage,
              'stage',
              ProfileProcessingStage.dtoParsing,
            )
            .having(
              (error) => error.exceptionType,
              'exception type',
              'FormatException',
            ),
      ),
    );
  });

  test('missing mandatory user_id produces a controlled schema error', () {
    expect(
      () => ProfileApiDto.fromJson(const {}),
      throwsA(
        isA<ProfileSchemaException>().having(
          (error) => error.sanitizedMessage,
          'message',
          contains('user_id'),
        ),
      ),
    );
  });

  test('nested data.profile is explicitly unsupported', () {
    expect(
      () => ProfileApiDto.fromJson({
        'profile': {'user_id': 'app-user-1'},
      }),
      throwsA(
        isA<ProfileSchemaException>().having(
          (error) => error.sanitizedMessage,
          'message',
          contains('Nested profile objects'),
        ),
      ),
    );
  });

  test('constraints_json rejects a non-list contract violation', () {
    expect(
      () => _profile({
        'constraints_json': {'kind': 'knee_sensitive'}
      }),
      throwsA(isA<ProfileSchemaException>()),
    );
  });
}

ProfileApiDto _profile(Map<String, Object?> fields) {
  return ProfileApiDto.fromJson({
    'user_id': 'app-user-1',
    ...fields,
  });
}

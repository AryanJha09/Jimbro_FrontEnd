import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/app_models.dart';
import '../../shared/models/atlas_insight.dart';
import '../config/app_config.dart';
import '../network/jim_api_client.dart';

abstract class AuthRepository {
  Future<AuthSession?> currentSession();
  Future<AuthSession> signInWithMockProvider(String provider);
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  });
  Future<void> signOut();
}

abstract class ProfileRepository {
  Future<UserProfile> loadProfile(AuthSession? session);
  Future<UserStaticMetrics> loadMetrics(AuthSession? session);
  Future<UserProfile> saveProfile(AuthSession? session, UserProfile profile);
  Future<UserStaticMetrics> saveMetrics(
    AuthSession? session,
    UserStaticMetrics metrics,
  );
}

abstract class WorkoutRepository {
  Future<WorkoutTemplateDraft> loadTemplate(AuthSession? session);
  Future<WorkoutLogDraft> loadWorkoutLog(AuthSession? session);
  Future<List<ExerciseSuggestion>> searchExercises(String query);
  Future<WorkoutTemplateDraft> saveTemplate(
    AuthSession? session,
    WorkoutTemplateDraft template,
  );
  Future<WorkoutLogDraft> saveWorkoutLog(
    AuthSession? session,
    WorkoutLogDraft log,
  );
}

abstract class NutritionRepository {
  Future<List<FoodLogDraft>> loadFoodLogs(AuthSession? session);
  Future<DailyNutritionSummary> loadSummary(AuthSession? session);
  Future<List<FoodSuggestion>> searchFoods(String query);
  Future<List<FoodLogDraft>> saveFoodLogs(
    AuthSession? session,
    List<FoodLogDraft> logs,
  );
}

abstract class ConsistencyRepository {
  Future<ConsistencyState> loadConsistency(AuthSession? session);
  Future<ConsistencyState> saveConsistency(
    AuthSession? session,
    ConsistencyState consistency,
  );
}

abstract class AtlasRepository {
  Future<List<AtlasInsight>> loadHomeInsights(
    AuthSession? session,
    UserProfile profile,
  );
  Future<AtlasInsight> loadHistoryInsight(AuthSession? session);
  Future<AtlasInsight> loadNutritionInsight(
    AuthSession? session,
    DailyNutritionSummary summary,
  );
  Future<AtlasInsight> loadRecoveryInsight(
    AuthSession? session,
    ConsistencyState consistency,
  );
  Future<AtlasInsight> previewPrompt(AuthSession? session, String prompt);
}

abstract class SearchRepository {
  SearchState emptyState();
  Future<List<SearchResultGroup>> search(AuthSession? session, String query);
}

class MockAuthRepository implements AuthRepository {
  AuthSession? _session;

  @override
  Future<AuthSession?> currentSession() async => _session;

  @override
  Future<AuthSession> signInWithMockProvider(String provider) async {
    _session = AuthSession(
      userId: 'mock-user-1',
      displayName: provider == 'email' ? 'Email user' : 'Aryan',
      email: 'aryan@example.com',
      accessToken: 'mock-supabase-access-token',
      refreshToken: 'mock-refresh-token',
      provider: provider,
    );
    return _session!;
  }

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return signInWithMockProvider('email');
  }

  @override
  Future<void> signOut() async {
    _session = null;
  }
}

class FastApiAuthRepository implements AuthRepository {
  FastApiAuthRepository(this._dio);

  final Dio _dio;
  AuthSession? _session;

  @override
  Future<AuthSession?> currentSession() async => _session;

  @override
  Future<AuthSession> signInWithMockProvider(String provider) async {
    throw UnsupportedError('Mock social auth is unavailable in live mode.');
  }

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final requestUrl = '${_dio.options.baseUrl}/auth/login';
    const requestPayloadShape =
        '{"email":"user@example.com","password":"string"}';
    final requestBody = {
      'email': email.trim(),
      'password': password,
    };
    try {
      final response = await _dio.post<dynamic>(
        '/auth/login',
        data: jsonEncode(requestBody),
        options: Options(
          contentType: 'application/json',
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );
      final rawBody = response.data;
      final payload = _asMap(_unwrapData(rawBody));
      final rawMap = _asMap(rawBody);
      final token = payload['access_token']?.toString() ??
          payload['token']?.toString() ??
          rawMap['access_token']?.toString() ??
          rawMap['token']?.toString() ??
          '';
      final refreshToken = payload['refresh_token']?.toString() ??
          rawMap['refresh_token']?.toString();
      if (response.statusCode != null && response.statusCode! >= 400) {
        throw Exception(
          _buildAuthDiagnosticMessage(
            source:
                'lib/core/repositories/app_repositories.dart -> FastApiAuthRepository.signInWithEmailPassword',
            requestUrl: requestUrl,
            statusCode: response.statusCode,
            responseHeaders: response.headers.map,
            responseBody: rawBody,
            fallback: 'Authentication request failed.',
            requestPayloadShape: requestPayloadShape,
          ),
        );
      }
      if (token.isEmpty) {
        throw Exception(
          _buildAuthDiagnosticMessage(
            source:
                'lib/core/repositories/app_repositories.dart -> FastApiAuthRepository.signInWithEmailPassword',
            requestUrl: requestUrl,
            statusCode: response.statusCode,
            responseHeaders: response.headers.map,
            responseBody: rawBody,
            fallback:
                'Login succeeded without an access token in the response body.',
            requestPayloadShape: requestPayloadShape,
          ),
        );
      }

      final jwtPayload = _decodeJwtPayload(token);
      final userPayload = _asMap(payload['user']);
      final userId = jwtPayload['sub']?.toString() ??
          userPayload['id']?.toString() ??
          userPayload['user_id']?.toString() ??
          email;
      final tokenEmail = jwtPayload['email']?.toString() ??
          userPayload['email']?.toString() ??
          email;
      final displayName = userPayload['username']?.toString() ??
          userPayload['name']?.toString() ??
          jwtPayload['preferred_username']?.toString() ??
          tokenEmail.split('@').first;
      _session = AuthSession(
        userId: userId,
        displayName: displayName,
        email: tokenEmail,
        accessToken: token,
        refreshToken: refreshToken,
        provider: 'fastapi',
      );
      return _session!;
    } on DioException catch (error) {
      throw Exception(
        _buildAuthDiagnosticMessage(
          source:
              'lib/core/repositories/app_repositories.dart -> FastApiAuthRepository.signInWithEmailPassword',
          requestUrl: requestUrl,
          statusCode: error.response?.statusCode,
          responseHeaders: error.response?.headers.map,
          responseBody: error.response?.data,
          fallback: _networkFallbackMessage(error),
          requestPayloadShape: requestPayloadShape,
        ),
      );
    }
  }

  @override
  Future<void> signOut() async {
    _session = null;
  }
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AuthSession?> currentSession() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      return null;
    }
    return _mapSession(session);
  }

  @override
  Future<AuthSession> signInWithMockProvider(String provider) {
    throw UnsupportedError('Mock social auth is unavailable in Supabase mode.');
  }

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final session = response.session;
      if (session == null) {
        final userEmail = response.user?.email ?? email.trim();
        throw Exception(
          'Supabase sign-in did not return a session.\n'
          'source: lib/core/repositories/app_repositories.dart -> SupabaseAuthRepository.signInWithEmailPassword\n'
          'provider: supabase\n'
          'email: $userEmail',
        );
      }
      return _mapSession(session);
    } on AuthException catch (error) {
      throw Exception(
        'Supabase auth error: ${error.message}\n'
        'source: lib/core/repositories/app_repositories.dart -> SupabaseAuthRepository.signInWithEmailPassword\n'
        'provider: supabase\n'
        'status: ${error.statusCode ?? 'unknown'}',
      );
    } catch (error) {
      throw Exception(
        'Supabase sign-in failed.\n'
        'source: lib/core/repositories/app_repositories.dart -> SupabaseAuthRepository.signInWithEmailPassword\n'
        'provider: supabase\n'
        'details: $error',
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  AuthSession _mapSession(Session session) {
    final user = session.user;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final displayName = metadata['full_name']?.toString() ??
        metadata['name']?.toString() ??
        user.email?.split('@').first ??
        'JimBro User';
    return AuthSession(
      userId: user.id,
      displayName: displayName,
      email: user.email ?? '',
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      provider: 'supabase',
    );
  }
}

class MockProfileRepository implements ProfileRepository {
  UserProfile _profile = const UserProfile(
    name: 'Aryan',
    goal: 'Lean muscle gain',
    coachingPreference: 'Contextual + concise',
    userLevel: UserLevel.intermediate,
    age: 22,
    heightCm: 181,
    weightKg: 78,
    weeksActive: 10,
    prefersVoiceLogging: true,
  );

  UserStaticMetrics _metrics = const UserStaticMetrics(
    bmr: 1980,
    tdee: 2740,
    maintenanceCalories: 2740,
    cutCalories: 2280,
    bulkCalories: 3020,
    proteinG: 170,
    carbsG: 290,
    fatG: 72,
    hydrationL: 3.8,
    cutIntensity: 'Moderate',
  );

  @override
  Future<UserProfile> loadProfile(AuthSession? session) async => _profile;

  @override
  Future<UserStaticMetrics> loadMetrics(AuthSession? session) async => _metrics;

  @override
  Future<UserProfile> saveProfile(
    AuthSession? session,
    UserProfile profile,
  ) async {
    _profile = profile;
    return _profile;
  }

  @override
  Future<UserStaticMetrics> saveMetrics(
    AuthSession? session,
    UserStaticMetrics metrics,
  ) async {
    _metrics = metrics;
    return _metrics;
  }
}

class FastApiProfileRepository implements ProfileRepository {
  FastApiProfileRepository(this._dio, this._fallback);

  final Dio _dio;
  final ProfileRepository _fallback;

  @override
  Future<UserProfile> loadProfile(AuthSession? session) async {
    if (session == null) {
      return _fallback.loadProfile(session);
    }
    try {
      final response = await _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.get<dynamic>(
          '/supabase/profile',
          options: Options(headers: headers),
        ),
      );
      final data = _unwrapData(response.data);
      if (data is! Map<String, dynamic>) {
        return _fallback.loadProfile(session);
      }
      return UserProfile(
        name: data['username']?.toString() ??
            data['name']?.toString() ??
            session.displayName,
        goal: data['goal']?.toString() ?? 'Lean muscle gain',
        coachingPreference:
            data['coaching_preference']?.toString() ?? 'Contextual + concise',
        userLevel: _parseUserLevel(data['user_level']?.toString()),
        age: _toInt(data['age'], 22),
        heightCm: _toDouble(data['height_cm'], 181),
        weightKg: _toDouble(data['weight_kg'], 78),
        weeksActive: _toInt(data['weeks_active'], 1),
        prefersVoiceLogging: data['prefers_voice_logging'] == true,
      );
    } catch (_) {
      return _fallback.loadProfile(session);
    }
  }

  @override
  Future<UserStaticMetrics> loadMetrics(AuthSession? session) async {
    return _fallback.loadMetrics(session);
  }

  @override
  Future<UserProfile> saveProfile(
    AuthSession? session,
    UserProfile profile,
  ) async {
    if (session == null) {
      return _fallback.saveProfile(session, profile);
    }
    try {
      await _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.post<dynamic>(
          '/supabase/profile',
          data: {
            'username': profile.name,
            'age': profile.age,
            'height_cm': profile.heightCm,
            'weight_kg': profile.weightKg,
          },
          options: Options(headers: headers),
        ),
      );
      return profile;
    } catch (_) {
      return _fallback.saveProfile(session, profile);
    }
  }

  @override
  Future<UserStaticMetrics> saveMetrics(
    AuthSession? session,
    UserStaticMetrics metrics,
  ) async {
    return _fallback.saveMetrics(session, metrics);
  }
}

class MockWorkoutRepository implements WorkoutRepository {
  late WorkoutTemplateDraft _template = WorkoutTemplateDraft(
    name: 'Push I / Upper',
    description:
        'Bench focus with chest, delts, and triceps arranged for a repeatable high-quality session.',
    durationMinutes: 62,
    goal: 'Hypertrophy',
    exercises: [
      WorkoutExerciseDraft(
        exerciseName: 'Bench Press',
        notes: 'Own the top set, keep one rep in reserve.',
        targetSets: 4,
        targetReps: 6,
        sets: const [
          SetDraft(
            setNumber: 1,
            weightKg: 72.5,
            reps: 6,
            isWarmup: false,
            isCompleted: true,
            rpe: 8,
          ),
          SetDraft(
            setNumber: 2,
            weightKg: 72.5,
            reps: 6,
            isWarmup: false,
            isCompleted: true,
            rpe: 8.5,
          ),
        ],
      ),
      WorkoutExerciseDraft(
        exerciseName: 'Incline Dumbbell Press',
        notes: 'Slow eccentric, smooth lockout.',
        targetSets: 3,
        targetReps: 10,
        sets: const [
          SetDraft(
            setNumber: 1,
            weightKg: 28,
            reps: 10,
            isWarmup: false,
            isCompleted: true,
            rpe: 8,
          ),
        ],
      ),
    ],
  );

  late WorkoutLogDraft _workoutLog = WorkoutLogDraft(
    name: 'Today\'s Push Session',
    notes: 'Energy is solid. Prioritize clean bar path.',
    startedAtLabel: '7:15 PM',
    exercises: _template.exercises,
  );

  @override
  Future<WorkoutTemplateDraft> loadTemplate(AuthSession? session) async =>
      _template;

  @override
  Future<WorkoutLogDraft> loadWorkoutLog(AuthSession? session) async =>
      _workoutLog;

  @override
  Future<List<ExerciseSuggestion>> searchExercises(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      return const [];
    }
    return _mockExerciseSuggestions
        .where((exercise) => exercise.name.toLowerCase().contains(normalized))
        .toList();
  }

  @override
  Future<WorkoutTemplateDraft> saveTemplate(
    AuthSession? session,
    WorkoutTemplateDraft template,
  ) async {
    _template = template;
    _workoutLog = _workoutLog.copyWith(
      name: template.name,
      exercises: template.exercises,
    );
    return _template;
  }

  @override
  Future<WorkoutLogDraft> saveWorkoutLog(
    AuthSession? session,
    WorkoutLogDraft log,
  ) async {
    _workoutLog = log;
    return _workoutLog;
  }
}

class FastApiWorkoutRepository implements WorkoutRepository {
  FastApiWorkoutRepository(this._dio);

  final Dio _dio;
  final _exerciseSearchCache =
      <String, _CacheEntry<List<ExerciseSuggestion>>>{};

  @override
  Future<WorkoutTemplateDraft> loadTemplate(AuthSession? session) async {
    if (session == null) {
      return WorkoutTemplateDraft.empty;
    }
    final response = await _recoverableLoadRequest(
      () => _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.get<dynamic>(
          '/workout-templates',
          options: Options(headers: headers),
        ),
      ),
    );
    if (response == null) {
      return WorkoutTemplateDraft.empty;
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.loadTemplate',
      allowUnauthorizedAsEmpty: true,
    );
    if (response.statusCode == 401) {
      return WorkoutTemplateDraft.empty;
    }
    final data = _unwrapData(response.data);
    if (data is! List || data.isEmpty) {
      return WorkoutTemplateDraft.empty;
    }
    final template = _pickMostRecentMap(data, 'updated_at');
    return _mapWorkoutTemplate(template);
  }

  @override
  Future<WorkoutLogDraft> loadWorkoutLog(AuthSession? session) async {
    if (session == null) {
      return WorkoutLogDraft.empty;
    }
    final response = await _recoverableLoadRequest(
      () => _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.get<dynamic>(
          '/workout-logs',
          options: Options(headers: headers),
        ),
      ),
    );
    if (response == null) {
      return WorkoutLogDraft.empty;
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.loadWorkoutLog',
      allowUnauthorizedAsEmpty: true,
    );
    if (response.statusCode == 401) {
      return WorkoutLogDraft.empty;
    }
    final data = _unwrapData(response.data);
    if (data is! List || data.isEmpty) {
      return WorkoutLogDraft.empty;
    }
    final log = _pickMostRecentMap(data, 'created_at');
    return _mapWorkoutLog(log);
  }

  @override
  Future<List<ExerciseSuggestion>> searchExercises(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      return const [];
    }
    final local = _localExerciseSuggestions(normalized);
    final cached = _exerciseSearchCache[normalized];
    if (cached != null && cached.isFresh) {
      return _mergeExerciseSuggestions(cached.value, local);
    }
    try {
      final response = await _dio.get<dynamic>(
        '/exercises/search',
        queryParameters: {'q': normalized},
      ).timeout(const Duration(milliseconds: 1500));
      if (response.statusCode == null || response.statusCode! >= 400) {
        return cached?.value ?? local;
      }
      final data = _unwrapData(response.data);
      if (data is! List) {
        return cached?.value ?? local;
      }
      final suggestions = data
          .map<ExerciseSuggestion?>((item) {
            final map = _asMap(item);
            final id = _toNullableInt(map['exercise_id']);
            final name = map['name']?.toString() ?? '';
            if (id == null || name.trim().isEmpty) {
              return null;
            }
            final muscle = map['primary_muscle']?.toString() ?? '';
            final category = map['category']?.toString() ?? '';
            final subtitle = [category, muscle]
                .where((value) => value.trim().isNotEmpty)
                .join(' • ');
            return ExerciseSuggestion(
              exerciseId: id,
              name: name,
              subtitle: subtitle.isEmpty ? 'Exercise catalog' : subtitle,
            );
          })
          .whereType<ExerciseSuggestion>()
          .toList();
      _exerciseSearchCache[normalized] = _CacheEntry(suggestions);
      return _mergeExerciseSuggestions(suggestions, local);
    } catch (_) {
      return cached?.value ?? local;
    }
  }

  @override
  Future<WorkoutTemplateDraft> saveTemplate(
    AuthSession? session,
    WorkoutTemplateDraft template,
  ) async {
    if (session == null) {
      throw Exception('You must be signed in to save workout templates.');
    }
    final normalized = _validateWorkoutTemplateDraft(template);
    final resolvedExercises = <WorkoutExerciseDraft>[];
    for (final exercise in normalized.exercises) {
      resolvedExercises.add(
        exercise.copyWith(
          exerciseId: await _resolveExerciseId(_dio, session, exercise),
        ),
      );
    }
    final payload = {
      'name': normalized.name,
      'description':
          normalized.description.isEmpty ? null : normalized.description,
      'exercises': resolvedExercises.asMap().entries.map((entry) {
        final exercise = entry.value;
        return {
          'exercise_id': exercise.exerciseId,
          'order_index': entry.key + 1,
          'notes': exercise.notes.isEmpty ? null : exercise.notes,
        };
      }).toList(),
    };
    final response = normalized.templateId == null
        ? await _requestWithSessionRetry(
            _dio,
            session,
            (headers) => _dio.post<dynamic>(
              '/workout-templates',
              data: payload,
              options: Options(headers: headers),
            ),
          )
        : await _requestWithSessionRetry(
            _dio,
            session,
            (headers) => _dio.patch<dynamic>(
              '/workout-templates/${normalized.templateId}',
              data: payload,
              options: Options(headers: headers),
            ),
          );
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.saveTemplate',
    );
    return _mapWorkoutTemplate(_unwrapData(response.data));
  }

  @override
  Future<WorkoutLogDraft> saveWorkoutLog(
    AuthSession? session,
    WorkoutLogDraft log,
  ) async {
    if (session == null) {
      throw Exception('You must be signed in to log workouts.');
    }
    final normalized = _validateWorkoutLogDraft(log);
    final resolvedExercises = <WorkoutExerciseDraft>[];
    for (final exercise in normalized.exercises) {
      resolvedExercises.add(
        exercise.copyWith(
          exerciseId: await _resolveExerciseId(_dio, session, exercise),
        ),
      );
    }
    if (normalized.workoutLogId != null) {
      final response = await _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.patch<dynamic>(
          '/workout-logs/${normalized.workoutLogId}',
          data: {
            'name': normalized.name,
            'notes': normalized.notes.isEmpty ? null : normalized.notes,
          },
          options: Options(headers: headers),
        ),
      );
      _throwIfRequestFailed(
        response,
        source:
            'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.saveWorkoutLog.patch',
      );
      return _mapWorkoutLog(_unwrapData(response.data));
    }
    final response = await _requestWithSessionRetry(
      _dio,
      session,
      (headers) => _dio.post<dynamic>(
        '/workout-logs',
        data: {
          'name': normalized.name,
          'template_id': normalized.templateId,
          'notes': normalized.notes.isEmpty ? null : normalized.notes,
          'exercises': resolvedExercises.asMap().entries.map((entry) {
            final exercise = entry.value;
            return {
              'exercise_id': exercise.exerciseId,
              'order_index': entry.key + 1,
              'notes': exercise.notes.isEmpty ? null : exercise.notes,
              'sets': exercise.sets.map((setDraft) {
                return {
                  'set_number': setDraft.setNumber,
                  'reps': setDraft.reps,
                  'weight_kg': setDraft.weightKg,
                  'is_warmup': setDraft.isWarmup,
                  if (setDraft.rpe > 0) 'rpe': setDraft.rpe,
                };
              }).toList(),
            };
          }).toList(),
        },
        options: Options(headers: headers),
      ),
    );
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.saveWorkoutLog.post',
    );
    return _mapWorkoutLog(_unwrapData(response.data));
  }
}

class MockNutritionRepository implements NutritionRepository {
  List<FoodLogDraft> _foodLogs = const [
    FoodLogDraft(
      foodName: 'Eggs',
      quantityGrams: 150,
      mealType: MealType.breakfast,
      calories: 215,
      protein: 18,
      carbs: 2,
      fat: 15,
    ),
    FoodLogDraft(
      foodName: 'Sourdough toast',
      quantityGrams: 70,
      mealType: MealType.breakfast,
      calories: 180,
      protein: 6,
      carbs: 34,
      fat: 2,
    ),
    FoodLogDraft(
      foodName: 'Chicken rice bowl',
      quantityGrams: 420,
      mealType: MealType.lunch,
      calories: 640,
      protein: 48,
      carbs: 66,
      fat: 16,
    ),
  ];

  @override
  Future<List<FoodLogDraft>> loadFoodLogs(AuthSession? session) async =>
      _foodLogs;

  @override
  Future<DailyNutritionSummary> loadSummary(AuthSession? session) async =>
      _summaryFor(_foodLogs);

  @override
  Future<List<FoodSuggestion>> searchFoods(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      return const [];
    }
    return _mockFoodSuggestions
        .where((food) => food.name.toLowerCase().contains(normalized))
        .toList();
  }

  @override
  Future<List<FoodLogDraft>> saveFoodLogs(
    AuthSession? session,
    List<FoodLogDraft> logs,
  ) async {
    _foodLogs = logs;
    return _foodLogs;
  }

  DailyNutritionSummary _summaryFor(List<FoodLogDraft> logs) {
    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fat = 0;
    for (final log in logs) {
      calories += log.calories;
      protein += log.protein;
      carbs += log.carbs;
      fat += log.fat;
    }

    return DailyNutritionSummary(
      targetCalories: 2740,
      consumedCalories: calories,
      proteinTarget: 170,
      proteinConsumed: protein,
      carbsTarget: 290,
      carbsConsumed: carbs,
      fatTarget: 72,
      fatConsumed: fat,
      hydrationTargetLiters: 3.8,
      hydrationConsumedLiters: 2.7,
    );
  }
}

class FastApiNutritionRepository implements NutritionRepository {
  FastApiNutritionRepository(this._dio);

  final Dio _dio;
  final _foodSearchCache = <String, _CacheEntry<List<FoodSuggestion>>>{};

  @override
  Future<List<FoodLogDraft>> loadFoodLogs(AuthSession? session) async {
    if (session == null) {
      return const [];
    }
    final response = await _recoverableLoadRequest(
      () => _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.get<dynamic>(
          '/food-log',
          queryParameters: {'log_date': _todayIso(), 'limit': 100},
          options: Options(headers: headers),
        ),
      ),
    );
    if (response == null) {
      return const [];
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiNutritionRepository.loadFoodLogs',
      allowUnauthorizedAsEmpty: true,
    );
    if (response.statusCode == 401) {
      return const [];
    }
    final data = _unwrapData(response.data);
    if (data is! List) {
      return const [];
    }
    return data.map<FoodLogDraft>((item) => _mapFoodLog(item)).toList();
  }

  @override
  Future<DailyNutritionSummary> loadSummary(AuthSession? session) async {
    if (session == null) {
      return DailyNutritionSummary.empty;
    }
    final response = await _recoverableLoadRequest(
      () => _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.get<dynamic>(
          '/food-log/summary/${_todayIso()}',
          options: Options(headers: headers),
        ),
      ),
    );
    if (response == null) {
      return DailyNutritionSummary.empty;
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiNutritionRepository.loadSummary',
      allowNotFoundAsEmpty: true,
      allowUnauthorizedAsEmpty: true,
    );
    if (response.statusCode == 401) {
      return DailyNutritionSummary.empty;
    }
    final data = _unwrapData(response.data);
    if (data is! Map<String, dynamic>) {
      return DailyNutritionSummary.empty;
    }
    return DailyNutritionSummary(
      targetCalories:
          _toNutritionDouble(data['target_calories'], 0, max: 20000),
      consumedCalories:
          _toNutritionDouble(data['total_calories'], 0, max: 20000),
      proteinTarget: _toNutritionDouble(data['protein_target'], 0, max: 1000),
      proteinConsumed: _toNutritionDouble(data['total_protein'], 0, max: 1000),
      carbsTarget: _toNutritionDouble(data['carbs_target'], 0, max: 2000),
      carbsConsumed: _toNutritionDouble(data['total_carbs'], 0, max: 2000),
      fatTarget: _toNutritionDouble(data['fat_target'], 0, max: 1000),
      fatConsumed: _toNutritionDouble(data['total_fat'], 0, max: 1000),
      hydrationTargetLiters:
          _toNutritionDouble(data['hydration_target'], 0, max: 20),
      hydrationConsumedLiters:
          _toNutritionDouble(data['hydration_consumed'], 0, max: 20),
    );
  }

  @override
  Future<List<FoodSuggestion>> searchFoods(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      return const [];
    }
    final cached = _foodSearchCache[normalized];
    if (cached != null && cached.isFresh) {
      return cached.value;
    }
    try {
      final response = await _dio.get<dynamic>(
        '/food/search',
        queryParameters: {'q': normalized},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == null || response.statusCode! >= 400) {
        return cached?.value ?? _localFoodSuggestions(normalized);
      }
      final data = _unwrapData(response.data);
      if (data is! List) {
        return cached?.value ?? _localFoodSuggestions(normalized);
      }
      final suggestions = data
          .map<FoodSuggestion?>((item) {
            final map = _asMap(item);
            final id = map['food_id']?.toString() ?? '';
            final name = map['name']?.toString() ?? '';
            if (id.trim().isEmpty || name.trim().isEmpty) {
              return null;
            }
            return FoodSuggestion(
              foodId: id,
              name: name,
              caloriesPer100g: _toNutritionDouble(
                map['calories_per_100g'],
                0,
                max: 2000,
              ),
              proteinPer100g: _toNutritionDouble(
                map['protein_per_100g'],
                0,
                max: 200,
              ),
              carbsPer100g: _toNutritionDouble(
                map['carbs_per_100g'],
                0,
                max: 200,
              ),
              fatPer100g: _toNutritionDouble(
                map['fat_per_100g'],
                0,
                max: 200,
              ),
              source: map['source']?.toString() ?? 'Food catalog',
            );
          })
          .whereType<FoodSuggestion>()
          .toList();
      _foodSearchCache[normalized] = _CacheEntry(suggestions);
      return suggestions.isEmpty
          ? _localFoodSuggestions(normalized)
          : suggestions;
    } catch (_) {
      return cached?.value ?? _localFoodSuggestions(normalized);
    }
  }

  @override
  Future<List<FoodLogDraft>> saveFoodLogs(
    AuthSession? session,
    List<FoodLogDraft> logs,
  ) async {
    if (session == null) {
      throw Exception('You must be signed in to save nutrition logs.');
    }
    final existingLogs = await loadFoodLogs(session);
    final existingById = {
      for (final log in existingLogs)
        if (log.foodLogId != null) log.foodLogId!: log,
    };
    final keptIds =
        logs.map((log) => log.foodLogId).whereType<String>().toSet();
    for (final existing in existingLogs) {
      final id = existing.foodLogId;
      if (id != null && !keptIds.contains(id)) {
        final response = await _requestWithSessionRetry(
          _dio,
          session,
          (headers) => _dio.delete<dynamic>(
            '/food-log/$id',
            options: Options(headers: headers),
          ),
        );
        _throwIfRequestFailed(
          response,
          source:
              'lib/core/repositories/app_repositories.dart -> FastApiNutritionRepository.saveFoodLogs.delete',
        );
      }
    }

    final saved = <FoodLogDraft>[];
    for (final log in logs) {
      final normalized = _validateFoodLogDraft(log);
      final previous = normalized.foodLogId == null
          ? null
          : existingById[normalized.foodLogId!];
      final requiresNewFood = previous == null ||
          normalized.foodId == null ||
          previous.foodName != normalized.foodName ||
          !_sameNumber(previous.calories, normalized.calories) ||
          !_sameNumber(previous.protein, normalized.protein) ||
          !_sameNumber(previous.carbs, normalized.carbs) ||
          !_sameNumber(previous.fat, normalized.fat);
      final foodId = requiresNewFood
          ? await _createFoodForLog(session, normalized)
          : (normalized.foodId ?? previous.foodId);
      if (foodId == null || foodId.isEmpty) {
        throw Exception(
            'Could not resolve a food_id for ${normalized.foodName}.');
      }
      final date = _formatDate(normalized.logDate ?? DateTime.now());
      final canPatchExisting = normalized.foodLogId != null &&
          previous != null &&
          previous.foodId == foodId &&
          previous.mealType == normalized.mealType &&
          _sameDay(previous.logDate, normalized.logDate);

      if (canPatchExisting) {
        final response = await _requestWithSessionRetry(
          _dio,
          session,
          (headers) => _dio.patch<dynamic>(
            '/food-log/${normalized.foodLogId}',
            data: {
              'quantity_grams': normalized.quantityGrams,
            },
            options: Options(headers: headers),
          ),
        );
        _throwIfRequestFailed(
          response,
          source:
              'lib/core/repositories/app_repositories.dart -> FastApiNutritionRepository.saveFoodLogs.patch',
        );
        saved.add(_mapFoodLog(_unwrapData(response.data)));
        continue;
      }

      if (normalized.foodLogId != null) {
        final deleteResponse = await _requestWithSessionRetry(
          _dio,
          session,
          (headers) => _dio.delete<dynamic>(
            '/food-log/${normalized.foodLogId}',
            options: Options(headers: headers),
          ),
        );
        _throwIfRequestFailed(
          deleteResponse,
          source:
              'lib/core/repositories/app_repositories.dart -> FastApiNutritionRepository.saveFoodLogs.recreateDelete',
        );
      }

      final createResponse = await _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.post<dynamic>(
          '/food-log',
          data: {
            'food_id': foodId,
            'quantity_grams': normalized.quantityGrams,
            'date': date,
            'meal_type': normalized.mealType.name,
          },
          options: Options(headers: headers),
        ),
      );
      _throwIfRequestFailed(
        createResponse,
        source:
            'lib/core/repositories/app_repositories.dart -> FastApiNutritionRepository.saveFoodLogs.create',
      );
      saved.add(_mapFoodLog(_unwrapData(createResponse.data)));
    }
    return saved;
  }

  Future<String?> _createFoodForLog(
    AuthSession session,
    FoodLogDraft log,
  ) async {
    final existingFoodId = await _resolveFoodId(_dio, log);
    if (existingFoodId != null) {
      return existingFoodId;
    }
    if (log.calories <= 0 &&
        log.protein <= 0 &&
        log.carbs <= 0 &&
        log.fat <= 0) {
      throw Exception(
        'Select a food suggestion or enter calories/macros before saving "${log.foodName}".',
      );
    }
    final quantity = log.quantityGrams <= 0 ? 100 : log.quantityGrams;
    final factor = 100 / quantity;
    final response = await _requestWithSessionRetry(
      _dio,
      session,
      (headers) => _dio.post<dynamic>(
        '/food',
        data: {
          'name': log.foodName,
          'calories_per_100g': (log.calories * factor).toStringAsFixed(2),
          'protein_per_100g': (log.protein * factor).toStringAsFixed(2),
          'carbs_per_100g': (log.carbs * factor).toStringAsFixed(2),
          'fat_per_100g': (log.fat * factor).toStringAsFixed(2),
          'source': 'JimBro',
        },
        options: Options(headers: headers),
      ),
    );
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiNutritionRepository._createFoodForLog',
    );
    final data = _asMap(_unwrapData(response.data));
    return data['food_id']?.toString();
  }
}

class MockConsistencyRepository implements ConsistencyRepository {
  ConsistencyState _consistency = const ConsistencyState(
    currentStreak: 12,
    longestStreak: 18,
    weeklyCheckins: 5,
    totalLogs: 46,
  );

  @override
  Future<ConsistencyState> loadConsistency(AuthSession? session) async =>
      _consistency;

  @override
  Future<ConsistencyState> saveConsistency(
    AuthSession? session,
    ConsistencyState consistency,
  ) async {
    _consistency = consistency;
    return _consistency;
  }
}

class MockAtlasRepository implements AtlasRepository {
  @override
  Future<List<AtlasInsight>> loadHomeInsights(
    AuthSession? session,
    UserProfile profile,
  ) async {
    return [
      AtlasInsight(
        title: 'Recovery note',
        mainText:
            'Your recent training load and sleep pattern suggest a strong pressing day. Start controlled, then let the session build.',
        confidence: AtlasConfidence.high,
        actionItems: const ['Bench focus today', 'Stop first set at RPE 8'],
      ),
      const AtlasInsight(
        title: 'Soreness is not the score',
        mainText:
            'Feeling wrecked can come from novelty or fatigue, but progress comes from quality work repeated over time. Trend lines beat soreness.',
        confidence: AtlasConfidence.medium,
        isMythBust: true,
        actionItems: ['Track progression weekly'],
        learnMoreKey: 'doms-vs-growth',
      ),
    ];
  }

  @override
  Future<AtlasInsight> loadHistoryInsight(AuthSession? session) async {
    return const AtlasInsight(
      title: 'Steady pattern, slight plateau',
      mainText:
          'Your estimated top set has climbed well across the cycle, but the last two exposures flattened. A small load jump and more rest should restart momentum.',
      confidence: AtlasConfidence.high,
      actionItems: ['Add 2.5kg next session', 'Rest 3 minutes on top sets'],
    );
  }

  @override
  Future<AtlasInsight> loadNutritionInsight(
    AuthSession? session,
    DailyNutritionSummary summary,
  ) async {
    final shortfall = (summary.proteinTarget - summary.proteinConsumed).round();
    return AtlasInsight(
      title: 'Protein timing stays flexible',
      mainText:
          'You are still $shortfall g short today. Hitting the day total matters more than forcing a perfect post-workout window.',
      confidence: AtlasConfidence.high,
      actionItems: const ['Add a high-protein evening meal'],
      learnMoreKey: 'protein-timing',
    );
  }

  @override
  Future<AtlasInsight> loadRecoveryInsight(
    AuthSession? session,
    ConsistencyState consistency,
  ) async {
    return AtlasInsight(
      title: 'Recovery outlook',
      mainText:
          'A ${consistency.currentStreak}-day consistency run is excellent. Keep tomorrow lighter if fatigue feels sticky so your streak stays sustainable.',
      confidence: AtlasConfidence.medium,
      actionItems: const ['Prioritize sleep', 'Keep tomorrow easier if needed'],
    );
  }

  @override
  Future<AtlasInsight> previewPrompt(
    AuthSession? session,
    String prompt,
  ) async {
    final trimmed = prompt.trim();
    return AtlasInsight(
      title: trimmed.isEmpty ? 'Prompt preview' : 'Jim would answer',
      mainText: trimmed.isEmpty
          ? 'Start typing and Jim will answer with short, contextual coaching here once the backend AI route is wired.'
          : 'For "$trimmed", Jim would return a concise coaching response, confidence cue, and next step.',
      confidence: AtlasConfidence.medium,
      actionItems: const ['Route later through FastAPI / ATLAS'],
    );
  }
}

class MockSearchRepository implements SearchRepository {
  static const _items = [
    SearchResultItem(
      label: 'Bench Press',
      subtitle: 'Compound press: chest, shoulders, triceps',
      category: SearchCategory.exercises,
    ),
    SearchResultItem(
      label: 'Romanian Deadlift',
      subtitle: 'Hinge pattern: glutes, hamstrings',
      category: SearchCategory.exercises,
    ),
    SearchResultItem(
      label: 'Chicken Breast',
      subtitle: '31g protein per 100g',
      category: SearchCategory.foods,
    ),
    SearchResultItem(
      label: 'Greek Yogurt',
      subtitle: 'High-protein dairy option',
      category: SearchCategory.foods,
    ),
    SearchResultItem(
      label: 'RPE',
      subtitle: 'How hard a set felt on a 1-10 scale',
      category: SearchCategory.metrics,
    ),
    SearchResultItem(
      label: 'Protein timing',
      subtitle: 'Education note: daily totals matter most',
      category: SearchCategory.insights,
    ),
  ];

  @override
  SearchState emptyState() => const SearchState(query: '', groups: []);

  @override
  Future<List<SearchResultGroup>> search(
    AuthSession? session,
    String query,
  ) async {
    final lowered = query.trim().toLowerCase();
    final results = lowered.isEmpty
        ? _items
        : _items
            .where(
              (item) =>
                  item.label.toLowerCase().contains(lowered) ||
                  item.subtitle.toLowerCase().contains(lowered),
            )
            .toList();

    final groups = <SearchResultGroup>[];
    for (final category in SearchCategory.values) {
      final items = results.where((item) => item.category == category).toList();
      if (items.isEmpty) {
        continue;
      }
      groups.add(
        SearchResultGroup(
          title: switch (category) {
            SearchCategory.exercises => 'Exercises',
            SearchCategory.foods => 'Foods',
            SearchCategory.metrics => 'Metrics',
            SearchCategory.insights => 'Insights',
          },
          items: items,
        ),
      );
    }
    return groups;
  }
}

const _mockExerciseSuggestions = [
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
    exerciseId: 112,
    name: 'Bench Press (Cable)',
    subtitle: 'Cable • chest',
  ),
  ExerciseSuggestion(
    exerciseId: 114,
    name: 'Bench Press (Smith Machine)',
    subtitle: 'Machine • chest',
  ),
  ExerciseSuggestion(
    exerciseId: 349,
    name: 'Bench Dip',
    subtitle: 'Bodyweight • triceps',
  ),
];

List<ExerciseSuggestion> _localExerciseSuggestions(String query) {
  return _mockExerciseSuggestions
      .where((exercise) => exercise.name.toLowerCase().contains(query))
      .toList();
}

List<ExerciseSuggestion> _mergeExerciseSuggestions(
  List<ExerciseSuggestion> primary,
  List<ExerciseSuggestion> fallback,
) {
  final byId = <int, ExerciseSuggestion>{};
  for (final suggestion in [...primary, ...fallback]) {
    byId.putIfAbsent(suggestion.exerciseId, () => suggestion);
  }
  return byId.values.toList();
}

const _mockFoodSuggestions = [
  FoodSuggestion(
    foodId: 'mock-chicken-breast',
    name: 'Chicken Breast',
    caloriesPer100g: 165,
    proteinPer100g: 31,
    carbsPer100g: 0,
    fatPer100g: 3.6,
    source: 'JimBro seed',
  ),
  FoodSuggestion(
    foodId: 'mock-eggs',
    name: 'Eggs',
    caloriesPer100g: 143,
    proteinPer100g: 12.6,
    carbsPer100g: 0.7,
    fatPer100g: 9.5,
    source: 'JimBro seed',
  ),
  FoodSuggestion(
    foodId: 'mock-greek-yogurt',
    name: 'Greek Yogurt',
    caloriesPer100g: 59,
    proteinPer100g: 10,
    carbsPer100g: 3.6,
    fatPer100g: 0.4,
    source: 'JimBro seed',
  ),
  FoodSuggestion(
    foodId: 'mock-rice',
    name: 'Cooked Rice',
    caloriesPer100g: 130,
    proteinPer100g: 2.7,
    carbsPer100g: 28,
    fatPer100g: 0.3,
    source: 'JimBro seed',
  ),
  FoodSuggestion(
    foodId: 'mock-oats',
    name: 'Oats',
    caloriesPer100g: 389,
    proteinPer100g: 16.9,
    carbsPer100g: 66.3,
    fatPer100g: 6.9,
    source: 'JimBro seed',
  ),
];

List<FoodSuggestion> _localFoodSuggestions(String query) {
  return _localFoodEstimateSuggestions
      .where((food) => food.name.toLowerCase().contains(query))
      .toList();
}

const _localFoodEstimateSuggestions = [
  FoodSuggestion(
    name: 'Chicken Breast',
    caloriesPer100g: 165,
    proteinPer100g: 31,
    carbsPer100g: 0,
    fatPer100g: 3.6,
    source: 'Local macro estimate',
  ),
  FoodSuggestion(
    name: 'Eggs',
    caloriesPer100g: 143,
    proteinPer100g: 12.6,
    carbsPer100g: 0.7,
    fatPer100g: 9.5,
    source: 'Local macro estimate',
  ),
  FoodSuggestion(
    name: 'Greek Yogurt',
    caloriesPer100g: 59,
    proteinPer100g: 10,
    carbsPer100g: 3.6,
    fatPer100g: 0.4,
    source: 'Local macro estimate',
  ),
  FoodSuggestion(
    name: 'Cooked Rice',
    caloriesPer100g: 130,
    proteinPer100g: 2.7,
    carbsPer100g: 28,
    fatPer100g: 0.3,
    source: 'Local macro estimate',
  ),
  FoodSuggestion(
    name: 'Oats',
    caloriesPer100g: 389,
    proteinPer100g: 16.9,
    carbsPer100g: 66.3,
    fatPer100g: 6.9,
    source: 'Local macro estimate',
  ),
];

class _CacheEntry<T> {
  _CacheEntry(this.value) : createdAt = DateTime.now();

  final T value;
  final DateTime createdAt;

  bool get isFresh =>
      DateTime.now().difference(createdAt) < const Duration(minutes: 5);
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.useLiveBackend) {
    return MockAuthRepository();
  }
  if (config.useSupabaseDirectAuth) {
    return SupabaseAuthRepository(Supabase.instance.client);
  }
  return FastApiAuthRepository(ref.watch(dioProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final fallback = MockProfileRepository();
  final config = ref.watch(appConfigProvider);
  if (!config.useLiveBackend) {
    return fallback;
  }
  return FastApiProfileRepository(ref.watch(dioProvider), fallback);
});

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.useLiveBackend) {
    return MockWorkoutRepository();
  }
  return FastApiWorkoutRepository(ref.watch(dioProvider));
});

final nutritionRepositoryProvider = Provider<NutritionRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.useLiveBackend) {
    return MockNutritionRepository();
  }
  return FastApiNutritionRepository(ref.watch(dioProvider));
});

final consistencyRepositoryProvider = Provider<ConsistencyRepository>(
  (ref) => MockConsistencyRepository(),
);

final atlasRepositoryProvider = Provider<AtlasRepository>(
  (ref) => MockAtlasRepository(),
);

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => MockSearchRepository(),
);

Future<String?> _getValidToken() async {
  final refreshed = await Supabase.instance.client.auth.refreshSession();
  return refreshed.session?.accessToken;
}

Map<String, String> _tokenDiagnostics(String? token) {
  if (token == null || token.isEmpty) {
    return const {'token_state': 'missing'};
  }
  final parts = token.split('.');
  final payload = parts.length >= 2 ? _decodeJwtPayload(token) : const {};
  final exp = _toNullableInt(payload['exp']);
  final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final expiresIn = exp == null ? null : exp - nowSeconds;
  return {
    'token_state': 'present',
    'token_parts': '${parts.length}',
    'token_prefix': token.substring(0, token.length < 12 ? token.length : 12),
    if (payload['iss'] != null) 'jwt_iss': payload['iss'].toString(),
    if (payload['aud'] != null) 'jwt_aud': payload['aud'].toString(),
    if (payload['sub'] != null) 'jwt_sub': payload['sub'].toString(),
    if (payload['email'] != null) 'jwt_email': payload['email'].toString(),
    if (exp != null) 'jwt_exp': '$exp',
    if (expiresIn != null) 'jwt_expires_in_seconds': '$expiresIn',
  };
}

Future<Map<String, String>> _authHeaders(AuthSession session) async {
  try {
    final token = await _getValidToken();
    if (token != null && token.isNotEmpty) {
      return {'Authorization': 'Bearer $token'};
    }
  } catch (_) {
    if (Supabase.instance.client.auth.currentSession != null) {
      throw Exception(
        'Supabase session exists but refreshSession() failed. Sign out and sign in again to get a valid access token.',
      );
    }
  }

  if (session.provider == 'supabase' ||
      Supabase.instance.client.auth.currentSession != null) {
    throw Exception(
      'Supabase session refresh did not return a usable access token. Sign out and sign in again; the app refused to send a stale token to FastAPI.',
    );
  }
  return session.fastApiHeaders;
}

Future<Response<dynamic>> _requestWithSessionRetry(
  Dio dio,
  AuthSession session,
  Future<Response<dynamic>> Function(Map<String, String> headers) send,
) async {
  Response<dynamic> response;
  try {
    response = await send(await _authHeaders(session));
  } on DioException catch (error) {
    final failedResponse = error.response;
    if (failedResponse == null) {
      rethrow;
    }
    response = failedResponse;
  }
  if (response.statusCode == 401 && session.provider == 'supabase') {
    try {
      final refreshedToken = await _getValidToken();
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        try {
          response = await send({'Authorization': 'Bearer $refreshedToken'});
        } on DioException catch (error) {
          final failedResponse = error.response;
          if (failedResponse == null) {
            rethrow;
          }
          response = failedResponse;
        }
      }
    } catch (_) {
      return response;
    }
  }
  return response;
}

Future<Response<dynamic>?> _recoverableLoadRequest(
  Future<Response<dynamic>> Function() request,
) async {
  try {
    return await request().timeout(const Duration(seconds: 9));
  } on TimeoutException {
    return null;
  } on DioException catch (error) {
    if (_isRecoverableLoadFailure(error)) {
      return null;
    }
    rethrow;
  }
}

bool _isRecoverableLoadFailure(DioException error) {
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError =>
      true,
    DioExceptionType.badResponse => (error.response?.statusCode ?? 0) >= 500,
    DioExceptionType.badCertificate ||
    DioExceptionType.cancel ||
    DioExceptionType.unknown =>
      false,
  };
}

void _throwIfRequestFailed(
  Response<dynamic> response, {
  required String source,
  AuthSession? session,
  bool allowNotFoundAsEmpty = false,
  bool allowUnauthorizedAsEmpty = false,
}) {
  final statusCode = response.statusCode;
  final body = _asMap(response.data);
  final backendMarkedFailure = body['success'] == false;
  final htmlErrorBody = _looksLikeHtmlError(response.data);
  if ((statusCode == null || statusCode < 400) &&
      !backendMarkedFailure &&
      !htmlErrorBody) {
    return;
  }
  if (allowNotFoundAsEmpty && statusCode == 404) {
    return;
  }
  if (allowUnauthorizedAsEmpty && statusCode == 401) {
    return;
  }
  final errorMap = _asMap(body['error']);
  final errorCode =
      errorMap['code']?.toString() ?? body['code']?.toString() ?? '';
  final fallback = statusCode == 401 && errorCode == 'AUTH_INVALID_CREDENTIALS'
      ? 'Backend rejected the Supabase bearer token.'
      : 'Backend request failed.';
  throw Exception(
    _buildAuthDiagnosticMessage(
      source: source,
      requestUrl:
          '${response.requestOptions.baseUrl}${response.requestOptions.path}',
      requestMethod: response.requestOptions.method,
      fallback: fallback,
      requestPayloadShape: response.requestOptions.data?.toString() ?? 'n/a',
      statusCode: statusCode,
      responseHeaders: response.headers.map,
      responseBody: response.data,
      tokenDiagnostics: _tokenDiagnostics(
        response.requestOptions.headers['Authorization']
            ?.toString()
            .replaceFirst(RegExp(r'^Bearer\s+'), ''),
      ),
      sessionDiagnostics: {
        if (session != null) 'session_provider': session.provider,
        if (session != null) 'session_user_id': session.userId,
        if (session != null) 'session_email': session.email,
      },
    ),
  );
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, dynamic mapValue) => MapEntry(key.toString(), mapValue),
    );
  }
  return {};
}

dynamic _unwrapData(dynamic raw) {
  final map = _asMap(raw);
  if (map.containsKey('data')) {
    return map['data'];
  }
  return raw;
}

String _extractErrorMessage(
  dynamic body, {
  int? statusCode,
  String fallback = 'Authentication failed',
}) {
  if (_looksLikeHtmlError(body)) {
    final text = body.toString();
    if (text.contains('ERR_NGROK_3200') || text.contains('is offline')) {
      return 'The ngrok backend endpoint is offline.';
    }
    return 'Backend returned an HTML error page instead of JSON.';
  }
  final map = _asMap(body);
  final unwrapped = _asMap(_unwrapData(body));
  final error = _asMap(map['error']);
  final detail = map['detail'] ?? unwrapped['detail'];
  final candidates = <String?>[
    error['message']?.toString(),
    error['detail']?.toString(),
    map['message']?.toString(),
    unwrapped['message']?.toString(),
    map['error_description']?.toString(),
    unwrapped['error_description']?.toString(),
    detail is String ? detail : null,
    _stringifyDetailList(detail),
  ];

  for (final candidate in candidates) {
    final trimmed = candidate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }

  if (statusCode == 401) {
    return 'Invalid email or password.';
  }
  if (statusCode == 422) {
    return 'Login request validation failed (422 Unprocessable Entity). The backend rejected the request body schema.';
  }
  return fallback;
}

bool _looksLikeHtmlError(dynamic body) {
  if (body is! String) {
    return false;
  }
  final trimmed = body.trimLeft().toLowerCase();
  return trimmed.startsWith('<!doctype html') || trimmed.startsWith('<html');
}

String _buildAuthDiagnosticMessage({
  required String source,
  required String requestUrl,
  String requestMethod = 'POST',
  required String fallback,
  required String requestPayloadShape,
  int? statusCode,
  Map<String, List<String>>? responseHeaders,
  dynamic responseBody,
  Map<String, String> tokenDiagnostics = const {},
  Map<String, String> sessionDiagnostics = const {},
}) {
  final ngrokCode = responseHeaders?['ngrok-error-code']?.first;
  final extracted = _extractErrorMessage(
    responseBody,
    statusCode: statusCode,
    fallback: fallback,
  );
  final snippet = _responseSnippet(responseBody);
  final lines = <String>[
    extracted,
    'source: $source',
    'request: $requestMethod $requestUrl',
    'expected_payload: $requestPayloadShape',
    if (statusCode != null) 'status: $statusCode',
    if (ngrokCode != null && ngrokCode.isNotEmpty)
      'ngrok_error_code: $ngrokCode',
    ...sessionDiagnostics.entries
        .map((entry) => '${entry.key}: ${entry.value}'),
    ...tokenDiagnostics.entries.map((entry) => '${entry.key}: ${entry.value}'),
  ];

  if (ngrokCode == 'ERR_NGROK_3200' ||
      responseBody.toString().contains('ERR_NGROK_3200')) {
    lines.add(
      'problem: The ngrok tunnel is offline, so Flutter cannot reach FastAPI.',
    );
    lines.add(
      'fix: Restart the backend tunnel or replace FASTAPI_BASE_URL with the current live URL.',
    );
  } else if (statusCode == 401) {
    lines.add(
      'problem: FastAPI rejected the bearer token before payload validation. This is not a workout/template payload error.',
    );
    lines.add(
      'fix: Check the backend detail above, confirm the live FastAPI process is running the patched auth_service.py, and verify the token issuer/email matches the backend user row.',
    );
    if (snippet != null) {
      lines.add('response_snippet: $snippet');
    }
  } else if (snippet != null) {
    lines.add('response_snippet: $snippet');
  }

  return lines.join('\n');
}

String? _stringifyDetailList(dynamic detail) {
  if (detail is List) {
    final parts = detail
        .map((item) {
          final entry = _asMap(item);
          return entry['msg']?.toString() ?? item.toString();
        })
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (parts.isNotEmpty) {
      return parts.join('\n');
    }
  }
  return null;
}

String _networkFallbackMessage(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'The server took too long to respond.';
    case DioExceptionType.connectionError:
      return 'Could not reach the backend. Check the API URL, tunnel, or server status.';
    case DioExceptionType.badCertificate:
      return 'The backend SSL certificate was rejected.';
    case DioExceptionType.cancel:
      return 'The login request was cancelled.';
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      return 'Authentication failed.';
  }
}

String? _responseSnippet(dynamic body) {
  if (body == null) {
    return null;
  }
  final asString = body.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (asString.isEmpty) {
    return null;
  }
  if (asString.length <= 220) {
    return asString;
  }
  return '${asString.substring(0, 220)}...';
}

Map<String, dynamic> _decodeJwtPayload(String token) {
  try {
    final parts = token.split('.');
    if (parts.length < 2) {
      return {};
    }
    final normalized = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return _asMap(jsonDecode(decoded));
  } catch (_) {
    return {};
  }
}

UserLevel _parseUserLevel(String? raw) {
  return switch (raw) {
    'beginner' => UserLevel.beginner,
    'advanced' => UserLevel.advanced,
    _ => UserLevel.intermediate,
  };
}

MealType _parseMealType(String? raw) {
  return switch (raw) {
    'breakfast' => MealType.breakfast,
    'lunch' => MealType.lunch,
    'dinner' => MealType.dinner,
    _ => MealType.snack,
  };
}

double _toDouble(dynamic value, double fallback) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().trim() ?? '');
  if (parsed == null || !parsed.isFinite) {
    return fallback;
  }
  return parsed;
}

double _toNutritionDouble(
  dynamic value,
  double fallback, {
  required double max,
}) {
  final parsed = _toDouble(value, fallback);
  if (parsed < 0) {
    return fallback;
  }
  if (parsed > max) {
    return max;
  }
  return parsed;
}

int _toInt(dynamic value, int fallback) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int _toNonNegativeInt(dynamic value, int fallback, {required int max}) {
  final parsed = _toInt(value, fallback);
  if (parsed < 0) {
    return fallback;
  }
  if (parsed > max) {
    return max;
  }
  return parsed;
}

Map<String, dynamic> _pickMostRecentMap(List<dynamic> raw, String field) {
  if (raw.isEmpty) {
    return {};
  }
  final maps = raw.map(_asMap).toList();
  maps.sort((a, b) {
    final left = DateTime.tryParse(a[field]?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final right = DateTime.tryParse(b[field]?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return right.compareTo(left);
  });
  return maps.first;
}

WorkoutTemplateDraft _mapWorkoutTemplate(dynamic raw) {
  final template = _asMap(raw);
  return WorkoutTemplateDraft(
    templateId: _toNullableInt(template['template_id']),
    name: template['name']?.toString() ?? '',
    description: template['description']?.toString() ?? '',
    durationMinutes: _toInt(template['duration_minutes'], 0),
    goal: template['goal']?.toString() ?? '',
    exercises: _mapTemplateExercises(
      template['template_exercises'] ?? template['exercises'],
    ),
  );
}

WorkoutLogDraft _mapWorkoutLog(dynamic raw) {
  final log = _asMap(raw);
  final startedAt = log['started_at']?.toString() ?? '';
  return WorkoutLogDraft(
    workoutLogId: _toNullableInt(log['workout_log_id']),
    templateId: _toNullableInt(log['template_id']),
    name: log['name']?.toString() ?? '',
    notes: log['notes']?.toString() ?? '',
    startedAtLabel: startedAt.isEmpty ? '' : startedAt,
    exercises: _mapLoggedExercises(
      log['workout_exercises'] ?? log['exercises'],
    ),
  );
}

FoodLogDraft _mapFoodLog(dynamic raw) {
  final map = _asMap(raw);
  final quantity = _toNutritionDouble(map['quantity_grams'], 0, max: 50000);
  final calories = _toNutritionDouble(map['calories_snapshot'], 0, max: 20000);
  final protein = _toNutritionDouble(map['protein_snapshot'], 0, max: 1000);
  final carbs = _toNutritionDouble(map['carbs_snapshot'], 0, max: 2000);
  final fat = _toNutritionDouble(map['fat_snapshot'], 0, max: 1000);
  final multiplier = quantity <= 0 ? 0 : 100 / quantity;
  return FoodLogDraft(
    foodLogId: map['food_log_id']?.toString(),
    foodId: map['food_id']?.toString(),
    logDate: DateTime.tryParse(map['date']?.toString() ?? ''),
    foodName: map['food_name']?.toString() ?? map['name']?.toString() ?? '',
    quantityGrams: quantity,
    mealType: _parseMealType(map['meal_type']?.toString()),
    calories: calories,
    protein: protein,
    carbs: carbs,
    fat: fat,
    caloriesPer100g: multiplier == 0 ? null : calories * multiplier,
    proteinPer100g: multiplier == 0 ? null : protein * multiplier,
    carbsPer100g: multiplier == 0 ? null : carbs * multiplier,
    fatPer100g: multiplier == 0 ? null : fat * multiplier,
  );
}

WorkoutTemplateDraft _validateWorkoutTemplateDraft(
    WorkoutTemplateDraft template) {
  final name = template.name.trim();
  final exercises = template.exercises
      .where((exercise) => exercise.exerciseName.trim().isNotEmpty)
      .toList();
  if (name.isEmpty) {
    throw Exception('Workout template name is required.');
  }
  if (exercises.isEmpty) {
    throw Exception(
        'Add at least one exercise before saving the workout template.');
  }
  return template.copyWith(
    name: name,
    exercises: exercises,
  );
}

WorkoutLogDraft _validateWorkoutLogDraft(WorkoutLogDraft log) {
  final name = log.name.trim().isEmpty ? 'Workout Session' : log.name.trim();
  final exercises = log.exercises
      .where((exercise) => exercise.exerciseName.trim().isNotEmpty)
      .map((exercise) {
    final sets = exercise.sets.where((setDraft) {
      return setDraft.reps > 0 || setDraft.weightKg > 0 || setDraft.rpe > 0;
    }).toList();
    return exercise.copyWith(sets: sets.isEmpty ? exercise.sets : sets);
  }).toList();
  if (exercises.isEmpty) {
    throw Exception('Add at least one exercise before logging the workout.');
  }
  return log.copyWith(
    name: name,
    exercises: exercises,
  );
}

FoodLogDraft _validateFoodLogDraft(FoodLogDraft log) {
  final name = log.foodName.trim();
  if (name.isEmpty) {
    throw Exception('Food name is required before saving nutrition logs.');
  }
  if (log.quantityGrams <= 0) {
    throw Exception('Food quantity must be greater than 0 grams.');
  }
  return log.copyWith(
    foodName: name,
    logDate: log.logDate ?? DateTime.now(),
  );
}

Future<int> _resolveExerciseId(
  Dio dio,
  AuthSession session,
  WorkoutExerciseDraft exercise,
) async {
  if (exercise.exerciseId != null) {
    return exercise.exerciseId!;
  }
  final exactName = exercise.exerciseName.trim();
  try {
    final searchResponse = await dio.get<dynamic>(
      '/exercises/search',
      queryParameters: {'q': exactName},
    ).timeout(const Duration(seconds: 5));
    if (searchResponse.statusCode != null && searchResponse.statusCode! < 400) {
      final data = _unwrapData(searchResponse.data);
      if (data is List) {
        final bestResultId = _pickBestExerciseId(data, exactName);
        if (bestResultId != null) {
          return bestResultId;
        }
      }
    }
  } catch (_) {
    // If catalog lookup is slow/down, fall through to creating a custom
    // exercise. The save action still uses authenticated retry semantics.
  }
  final createResponse = await _requestWithSessionRetry(
    dio,
    session,
    (headers) => dio.post<dynamic>(
      '/exercises',
      data: {
        'name': exactName,
        'description': exercise.notes.isEmpty ? null : exercise.notes,
        'category': 'Custom',
      },
      options: Options(headers: headers),
    ),
  );
  _throwIfRequestFailed(
    createResponse,
    source: 'lib/core/repositories/app_repositories.dart -> _resolveExerciseId',
  );
  final created = _asMap(_unwrapData(createResponse.data));
  final id = _toNullableInt(created['exercise_id']);
  if (id == null) {
    throw Exception(
        'The backend did not return an exercise_id for ${exercise.exerciseName}.');
  }
  return id;
}

int? _pickBestExerciseId(List<dynamic> items, String query) {
  int? bestResultId;
  var bestScore = -1;
  for (final item in items) {
    final map = _asMap(item);
    final name = map['name']?.toString() ?? '';
    final id = _toNullableInt(map['exercise_id']);
    if (id == null || name.trim().isEmpty) {
      continue;
    }
    final score = _exerciseNameScore(query, name);
    if (score > bestScore) {
      bestScore = score;
      bestResultId = id;
    }
  }
  return bestScore >= 70 ? bestResultId : null;
}

int _exerciseNameScore(String query, String candidate) {
  final normalizedQuery = _normalizeExerciseName(query);
  final normalizedCandidate = _normalizeExerciseName(candidate);
  if (normalizedCandidate == normalizedQuery) {
    return 1200;
  }
  final withParentheticalRemoved =
      candidate.toLowerCase().replaceAll(RegExp(r'[^a-z0-9()]+'), ' ').trim();
  final parentheticalQuery =
      RegExp('^${RegExp.escape(normalizedQuery)} \\([a-z0-9 ]+\\)\$');
  if (parentheticalQuery.hasMatch(withParentheticalRemoved)) {
    return 1100;
  }
  if (normalizedCandidate.startsWith(normalizedQuery)) {
    return 900;
  }
  if (normalizedCandidate.contains(normalizedQuery)) {
    return 700;
  }
  final queryTokens =
      normalizedQuery.split(' ').where((token) => token.length > 2);
  final candidateTokens = normalizedCandidate.split(' ').toSet();
  final matches = queryTokens.where(candidateTokens.contains).length;
  return matches * 100;
}

String _normalizeExerciseName(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

Future<String?> _resolveFoodId(Dio dio, FoodLogDraft log) async {
  if (log.foodId != null && log.foodId!.isNotEmpty) {
    return log.foodId;
  }
  final name = log.foodName.trim();
  if (name.length < 2) {
    return null;
  }
  try {
    final response = await dio.get<dynamic>(
      '/food/search',
      queryParameters: {'q': name},
    ).timeout(const Duration(seconds: 5));
    if (response.statusCode == null || response.statusCode! >= 400) {
      return null;
    }
    final data = _unwrapData(response.data);
    if (data is! List) {
      return null;
    }
    String? firstResultId;
    for (final item in data) {
      final map = _asMap(item);
      final foodId = map['food_id']?.toString();
      final foodName = map['name']?.toString() ?? '';
      firstResultId ??= foodId;
      if (foodId != null &&
          foodId.isNotEmpty &&
          foodName.toLowerCase() == name.toLowerCase()) {
        return foodId;
      }
    }
    return firstResultId;
  } catch (_) {
    return null;
  }
}

String _todayIso() => _formatDate(DateTime.now());

String _formatDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

bool _sameDay(DateTime? left, DateTime? right) {
  if (left == null || right == null) {
    return false;
  }
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

bool _sameNumber(double left, double right) => (left - right).abs() < 0.001;

int? _toNullableInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}

List<WorkoutExerciseDraft> _mapTemplateExercises(dynamic raw) {
  if (raw is! List) {
    return const [];
  }
  return raw.map<WorkoutExerciseDraft>((item) {
    final map = _asMap(item);
    return WorkoutExerciseDraft(
      exerciseId: _toNullableInt(map['exercise_id']),
      exerciseName:
          map['exercise_name']?.toString() ?? map['name']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      targetSets: _toNonNegativeInt(map['target_sets'], 3, max: 100),
      targetReps: _toNonNegativeInt(map['target_reps'], 10, max: 1000),
      sets: const [],
    );
  }).toList();
}

List<WorkoutExerciseDraft> _mapLoggedExercises(dynamic raw) {
  if (raw is! List) {
    return const [];
  }
  return raw.map<WorkoutExerciseDraft>((item) {
    final map = _asMap(item);
    final rawSets = map['sets'];
    final sets = rawSets is List
        ? rawSets.map<SetDraft>((setItem) {
            final setMap = _asMap(setItem);
            return SetDraft(
              setNumber: _toNonNegativeInt(
                setMap['set_number'],
                1,
                max: 1000,
              ),
              weightKg: _toNutritionDouble(
                setMap['weight_kg'],
                0,
                max: 10000,
              ),
              reps: _toNonNegativeInt(setMap['reps'], 0, max: 1000),
              isWarmup: setMap['is_warmup'] == true,
              isCompleted: setMap['is_completed'] != false,
              rpe: _toNutritionDouble(setMap['rpe'], 0, max: 10),
            );
          }).toList()
        : const <SetDraft>[];
    return WorkoutExerciseDraft(
      exerciseId: _toNullableInt(map['exercise_id']),
      exerciseName:
          map['exercise_name']?.toString() ?? map['name']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      targetSets: sets.length,
      targetReps: sets.isNotEmpty ? sets.first.reps : 10,
      sets: sets,
    );
  }).toList();
}

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/app_models.dart';
import '../../shared/models/atlas_insight.dart';
import '../../shared/models/jim_chat_models.dart';
import '../../shared/models/onboarding_models.dart';
import '../config/app_config.dart';
import '../network/jim_api_client.dart';
import '../nutrition/nutrition_targets.dart';

abstract class AuthRepository {
  Future<AuthSession?> currentSession();
  Future<AuthSession> signInWithMockProvider(String provider);
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  });
  Future<void> signOut();
}

class AuthSessionExpiredException implements Exception {
  const AuthSessionExpiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AtlasProfileSyncException implements Exception {
  const AtlasProfileSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AtlasOnboardingCredentialException implements Exception {
  const AtlasOnboardingCredentialException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AtlasOnboardingAccount {
  const AtlasOnboardingAccount({
    required this.username,
    required this.email,
    required this.password,
  });

  final String username;
  final String email;
  final String password;
}

abstract class ProfileRepository {
  Future<UserProfile> loadProfile(AuthSession? session);
  Future<UserStaticMetrics> loadMetrics(AuthSession? session);
  Future<UserProfile> saveProfile(AuthSession? session, UserProfile profile);
  Future<UserStaticMetrics> saveMetrics(
    AuthSession? session,
    UserStaticMetrics metrics,
  );
  Future<UserStaticMetrics> submitAtlasOnboarding(
    AuthSession? session,
    UserProfile profile,
    OnboardingAnswersDto answers,
    AtlasOnboardingAccount? account,
  );
  Future<UserStaticMetrics> loadAtlasMetrics(AuthSession? session);
  Future<UserStaticMetrics> patchAtlasProfile(
    AuthSession? session, {
    required UserProfile previous,
    required UserProfile next,
  });
}

abstract class WorkoutRepository {
  Future<List<WorkoutTemplateDraft>> loadTemplates(AuthSession? session);
  Future<WorkoutTemplateDraft> loadTemplate(AuthSession? session);
  Future<List<WorkoutScheduleEntry>> loadSchedule(AuthSession? session);
  Future<WorkoutLogDraft> loadWorkoutLog(AuthSession? session);
  Future<List<ExerciseSuggestion>> searchExercises(String query);
  Future<WorkoutTemplateDraft> saveTemplate(
    AuthSession? session,
    WorkoutTemplateDraft template,
  );
  Future<void> deleteTemplate(AuthSession? session, int templateId);
  Future<WorkoutScheduleEntry> saveScheduleEntry(
    AuthSession? session,
    WorkoutScheduleEntry entry,
  );
  Future<void> deleteScheduleEntry(
    AuthSession? session,
    WorkoutScheduleEntry entry,
  );
  Future<WorkoutLogDraft> saveWorkoutLog(
    AuthSession? session,
    WorkoutLogDraft log,
  );
  Future<void> flushPending(AuthSession? session);
}

abstract class NutritionRepository {
  Future<List<FoodLogDraft>> loadFoodLogs(AuthSession? session);
  Future<DailyNutritionSummary> loadSummary(AuthSession? session);
  Future<List<FoodSuggestion>> searchFoods(String query);
  Future<List<FoodLogDraft>> saveFoodLogs(
    AuthSession? session,
    List<FoodLogDraft> logs,
  );
  Future<void> flushPending(AuthSession? session);
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

abstract class AgentContextRepository {
  Future<AgentContextSnapshot> load(AuthSession? session);
}

class ProgramGenerationResult {
  const ProgramGenerationResult._({
    required this.isSuccess,
    this.message,
  });

  const ProgramGenerationResult.success([String? message])
      : this._(isSuccess: true, message: message);

  const ProgramGenerationResult.failure(String message)
      : this._(isSuccess: false, message: message);

  final bool isSuccess;
  final String? message;
}

abstract class ProgramRepository {
  Future<ProgramGenerationResult> generateProgram(AuthSession? session);
}

abstract class JimChatRepository {
  Future<JimChatResponse> send(
    AuthSession? session, {
    required String sessionId,
    required String message,
    required JimChatMode mode,
    String? selectedOption,
  });
  Stream<JimChatStreamEvent> stream(
    AuthSession? session, {
    required String sessionId,
    required String message,
    required JimChatMode mode,
  });
  Future<void> endSession(AuthSession? session, String sessionId);
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
      displayName: 'JimBro User',
      email: 'user@example.com',
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
    name: 'JimBro User',
    goal: '',
    coachingPreference: '',
    userLevel: UserLevel.beginner,
    age: 0,
    heightCm: 0,
    weightKg: 0,
    sex: '',
    availableTimeMinutes: 0,
    trainingPreference: '',
    activityLevel: '',
    dietaryPreference: '',
    goalTimeframe: '',
    weeksActive: 0,
    prefersVoiceLogging: false,
  );

  UserStaticMetrics _metrics = const UserStaticMetrics(
    bmr: 0,
    tdee: 0,
    targetCalories: 0,
    maintenanceCalories: 0,
    cutCalories: 0,
    bulkCalories: 0,
    proteinG: 0,
    carbsG: 0,
    fatG: 0,
    hydrationL: 0,
    cutIntensity: '',
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

  @override
  Future<UserStaticMetrics> submitAtlasOnboarding(
    AuthSession? session,
    UserProfile profile,
    OnboardingAnswersDto answers,
    AtlasOnboardingAccount? account,
  ) async {
    _profile = profile;
    _metrics = _localMetricsForProfile(profile);
    return _metrics;
  }

  @override
  Future<UserStaticMetrics> loadAtlasMetrics(AuthSession? session) async {
    return _metrics;
  }

  @override
  Future<UserStaticMetrics> patchAtlasProfile(
    AuthSession? session, {
    required UserProfile previous,
    required UserProfile next,
  }) async {
    _profile = next;
    _metrics = _localMetricsForProfile(next);
    return _metrics;
  }
}

class FastApiProfileRepository implements ProfileRepository {
  FastApiProfileRepository(this._dio, this._fallback);

  final Dio _dio;
  final ProfileRepository _fallback;
  final _profileCache = <String, _CacheEntry<UserProfile>>{};

  @override
  Future<UserProfile> loadProfile(AuthSession? session) async {
    if (session == null) {
      return _fallback.loadProfile(session);
    }
    final cached = _profileCache[session.userId];
    if (cached != null && cached.isFresh) {
      return cached.value;
    }
    final response = await _requestWithSessionRetry(
      _dio,
      session,
      (headers) => _dio.get<dynamic>(
        '/supabase/profile',
        options: Options(headers: headers),
      ),
    );
    if (_isMissingBackendSupabaseServiceKey(response)) {
      return cached?.value ?? await _fallback.loadProfile(session);
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiProfileRepository.loadProfile',
      session: session,
      allowNotFoundAsEmpty: true,
    );
    if (response.statusCode == 404) {
      return cached?.value ?? await _fallback.loadProfile(session);
    }
    final data = _unwrapData(response.data);
    if (data is! Map<String, dynamic>) {
      throw Exception(
        'Profile response shape mismatch.\n'
        'source: lib/core/repositories/app_repositories.dart -> FastApiProfileRepository.loadProfile\n'
        'request: GET ${_dio.options.baseUrl}/supabase/profile\n'
        'expected_payload: {"success":true,"data":{...profile fields...}}\n'
        'actual_response: ${_responseSnippet(response.data) ?? 'empty'}',
      );
    }
    final backendUpdatedAt = DateTime.tryParse(
      data['updated_at']?.toString() ?? '',
    );
    if (cached != null &&
        (backendUpdatedAt == null ||
            !backendUpdatedAt.isAfter(cached.createdAt))) {
      return cached.value;
    }
    final profile = UserProfile(
      name: data['username']?.toString() ??
          data['name']?.toString() ??
          session.displayName,
      goal: _profileGoalLabel(
        data['goal'] ?? data['fitness_goal'] ?? 'Build muscle',
      ),
      coachingPreference:
          data['coaching_preference']?.toString() ?? 'Contextual + concise',
      userLevel: _parseUserLevel(
        (data['user_level'] ?? data['experience_level'])?.toString(),
      ),
      age: _toInt(data['age'], 0),
      heightCm: _toDouble(data['height_cm'], 0),
      weightKg: _toDouble(data['weight_kg'], 0),
      sex: data['sex']?.toString() ?? '',
      availableTimeMinutes: _toInt(
        data['available_time_min'] ?? data['available_time_minutes'],
        0,
      ),
      trainingPreference: _profileEquipmentLabel(
        data['training_preference'] ?? data['equipment_access'],
      ),
      activityLevel: _profileActivityLabel(data['activity_level']),
      dietaryPreference: data['dietary_preference']?.toString() ?? '',
      goalTimeframe: data['goal_timeframe']?.toString() ?? '',
      weeksActive: _toInt(data['weeks_active'], 0),
      prefersVoiceLogging: data['prefers_voice_logging'] == true,
    );
    _profileCache[session.userId] = _CacheEntry(
      profile,
      ttl: FrontendCachePolicy.profile,
    );
    return profile;
  }

  @override
  Future<UserStaticMetrics> loadMetrics(AuthSession? session) async {
    return loadAtlasMetrics(session);
  }

  @override
  Future<UserProfile> saveProfile(
    AuthSession? session,
    UserProfile profile,
  ) async {
    if (session == null) {
      return _fallback.saveProfile(session, profile);
    }
    final payload = profileBackendPayload(profile);
    final response = await _requestWithSessionRetry(
      _dio,
      session,
      (headers) => _dio.post<dynamic>(
        '/supabase/profile',
        data: payload,
        options: Options(headers: headers),
      ),
    );
    if (_isMissingBackendSupabaseServiceKey(response)) {
      final saved = await _fallback.saveProfile(session, profile);
      _profileCache[session.userId] = _CacheEntry(
        saved,
        ttl: FrontendCachePolicy.profile,
      );
      return saved;
    }
    if (response.statusCode == 400 || response.statusCode == 422) {
      final legacyResponse = await _requestWithSessionRetry(
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
      if (_isMissingBackendSupabaseServiceKey(legacyResponse)) {
        final saved = await _fallback.saveProfile(session, profile);
        _profileCache[session.userId] = _CacheEntry(
          saved,
          ttl: FrontendCachePolicy.profile,
        );
        return saved;
      }
      _throwIfRequestFailed(
        legacyResponse,
        source:
            'lib/core/repositories/app_repositories.dart -> FastApiProfileRepository.saveProfile legacy retry',
        session: session,
      );
      _profileCache[session.userId] = _CacheEntry(
        profile,
        ttl: FrontendCachePolicy.profile,
      );
      return profile;
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiProfileRepository.saveProfile',
      session: session,
    );
    _profileCache[session.userId] = _CacheEntry(
      profile,
      ttl: FrontendCachePolicy.profile,
    );
    return profile;
  }

  @override
  Future<UserStaticMetrics> saveMetrics(
    AuthSession? session,
    UserStaticMetrics metrics,
  ) async {
    return _fallback.saveMetrics(session, metrics);
  }

  @override
  Future<UserStaticMetrics> submitAtlasOnboarding(
    AuthSession? session,
    UserProfile profile,
    OnboardingAnswersDto answers,
    AtlasOnboardingAccount? account,
  ) async {
    if (session == null) {
      return _fallback.submitAtlasOnboarding(
        session,
        profile,
        answers,
        account,
      );
    }
    if (account == null) {
      throw const AtlasOnboardingCredentialException(
        'Your setup is saved on this device. Jim will sync it when the coaching service is available.',
      );
    }
    final payload = atlasOnboardingPayloadFromProfile(
      profile,
      answers: answers,
      account: account,
    );
    _validateAtlasPayloadCanSync(payload);
    final response = await _requestWithSessionRetry(
      _dio,
      session,
      (headers) => _dio.post<dynamic>(
        '/atlas/onboard',
        data: payload,
        options: Options(headers: headers),
      ),
    );
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiProfileRepository.submitAtlasOnboarding',
      session: session,
    );
    final metrics = _mapAtlasMetrics(response.data);
    if (_metricsAreUsable(metrics)) {
      return metrics;
    }
    return loadAtlasMetrics(session);
  }

  @override
  Future<UserStaticMetrics> loadAtlasMetrics(AuthSession? session) async {
    if (session == null) {
      return _fallback.loadAtlasMetrics(session);
    }
    final response = await _recoverableLoadRequest(
      () => _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.get<dynamic>(
          '/atlas/metrics',
          options: Options(headers: headers),
        ),
      ),
    );
    if (response == null || _routeLooksUnsupported(response)) {
      return _fallback.loadAtlasMetrics(session);
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiProfileRepository.loadAtlasMetrics',
      session: session,
    );
    return _mapAtlasMetrics(response.data);
  }

  @override
  Future<UserStaticMetrics> patchAtlasProfile(
    AuthSession? session, {
    required UserProfile previous,
    required UserProfile next,
  }) async {
    if (session == null) {
      return _fallback.patchAtlasProfile(
        session,
        previous: previous,
        next: next,
      );
    }
    final payload = atlasProfilePatchPayload(
      previous: previous,
      next: next,
    );
    if (payload.isEmpty) {
      return loadAtlasMetrics(session);
    }
    final response = await _requestWithSessionRetry(
      _dio,
      session,
      (headers) => _dio.patch<dynamic>(
        '/atlas/profile',
        data: payload,
        options: Options(headers: headers),
      ),
    );
    if (_routeLooksUnsupported(response)) {
      return _fallback.patchAtlasProfile(
        session,
        previous: previous,
        next: next,
      );
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiProfileRepository.patchAtlasProfile',
      session: session,
    );
    final metrics = _mapAtlasMetrics(response.data);
    if (_metricsAreUsable(metrics)) {
      return metrics;
    }
    return loadAtlasMetrics(session);
  }
}

class MockWorkoutRepository implements WorkoutRepository {
  final List<WorkoutTemplateDraft> _templates = [];
  final List<WorkoutScheduleEntry> _schedule = [];
  WorkoutLogDraft _workoutLog = WorkoutLogDraft.empty;
  int _nextTemplateId = 1;
  int _nextScheduleId = 1;

  @override
  Future<List<WorkoutTemplateDraft>> loadTemplates(
          AuthSession? session) async =>
      List.unmodifiable(_templates);

  @override
  Future<WorkoutTemplateDraft> loadTemplate(AuthSession? session) async {
    return _templates.isEmpty ? WorkoutTemplateDraft.empty : _templates.last;
  }

  @override
  Future<List<WorkoutScheduleEntry>> loadSchedule(AuthSession? session) async =>
      List.unmodifiable(_schedule);

  @override
  Future<WorkoutLogDraft> loadWorkoutLog(AuthSession? session) async =>
      _workoutLog;

  @override
  Future<List<ExerciseSuggestion>> searchExercises(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const [];
    }
    return _mockExerciseSuggestions.where((exercise) {
      final name = exercise.name.toLowerCase();
      return normalized.length < 3
          ? name.startsWith(normalized)
          : name.contains(normalized);
    }).toList();
  }

  @override
  Future<WorkoutTemplateDraft> saveTemplate(
    AuthSession? session,
    WorkoutTemplateDraft template,
  ) async {
    final saved = template.copyWith(
      templateId: template.templateId ?? _nextTemplateId++,
    );
    final existingIndex = _templates.indexWhere(
      (item) => item.templateId == saved.templateId,
    );
    if (existingIndex == -1) {
      _templates.add(saved);
    } else {
      _templates[existingIndex] = saved;
    }
    _workoutLog = _workoutLog.copyWith(
      templateId: saved.templateId,
      name: saved.name,
      exercises: saved.exercises,
    );
    return saved;
  }

  @override
  Future<void> deleteTemplate(AuthSession? session, int templateId) async {
    _templates.removeWhere((template) => template.templateId == templateId);
    _schedule.removeWhere((entry) => entry.templateId == templateId);
    if (_workoutLog.templateId == templateId) {
      _workoutLog = _workoutLog.copyWith(templateId: null);
    }
  }

  @override
  Future<WorkoutScheduleEntry> saveScheduleEntry(
    AuthSession? session,
    WorkoutScheduleEntry entry,
  ) async {
    final saved = entry.copyWith(
      scheduleId: entry.scheduleId ?? 'local-${_nextScheduleId++}',
      userId: entry.userId ?? session?.userId,
    );
    final existingIndex = _schedule.indexWhere(
      (item) =>
          item.scheduleId == saved.scheduleId || item.weekday == saved.weekday,
    );
    if (existingIndex == -1) {
      _schedule.add(saved);
    } else {
      _schedule[existingIndex] = saved;
    }
    return saved;
  }

  @override
  Future<void> deleteScheduleEntry(
    AuthSession? session,
    WorkoutScheduleEntry entry,
  ) async {
    _schedule.removeWhere(
      (item) =>
          item.scheduleId == entry.scheduleId || item.weekday == entry.weekday,
    );
  }

  @override
  Future<WorkoutLogDraft> saveWorkoutLog(
    AuthSession? session,
    WorkoutLogDraft log,
  ) async {
    _workoutLog = log;
    return _workoutLog;
  }

  @override
  Future<void> flushPending(AuthSession? session) async {}
}

class FastApiWorkoutRepository implements WorkoutRepository {
  FastApiWorkoutRepository(
    this._dio, {
    LocalWorkoutScheduleStore? scheduleFallback,
    OfflineOutboxStore? outbox,
  })  : _scheduleFallback =
            scheduleFallback ?? const LocalWorkoutScheduleStore(),
        _outbox = outbox ?? const OfflineOutboxStore();

  final Dio _dio;
  final LocalWorkoutScheduleStore _scheduleFallback;
  final OfflineOutboxStore _outbox;
  final _exerciseSearchCache =
      <String, _CacheEntry<List<ExerciseSuggestion>>>{};
  final _templatesCache = <String, _CacheEntry<List<WorkoutTemplateDraft>>>{};
  static bool? _workoutScheduleBackendSupported;

  @override
  Future<List<WorkoutTemplateDraft>> loadTemplates(AuthSession? session) async {
    if (session == null) {
      return const [];
    }
    final cached = _templatesCache[session.userId];
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
      return cached?.value ?? const [];
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.loadTemplates',
    );
    final data = _unwrapData(response.data);
    if (data is! List || data.isEmpty) {
      return cached?.value ?? const [];
    }
    final templates = data.map(_mapWorkoutTemplate).toList();
    _templatesCache[session.userId] = _CacheEntry(
      templates,
      ttl: FrontendCachePolicy.templates,
    );
    return templates;
  }

  @override
  Future<WorkoutTemplateDraft> loadTemplate(AuthSession? session) async {
    final templates = await loadTemplates(session);
    if (templates.isEmpty) {
      return WorkoutTemplateDraft.empty;
    }
    return _pickMostRecentTemplate(templates);
  }

  @override
  Future<List<WorkoutScheduleEntry>> loadSchedule(AuthSession? session) async {
    final local = await _scheduleFallback.load(session);
    if (session == null || _workoutScheduleBackendSupported == false) {
      return local;
    }
    final response = await _recoverableLoadRequest(
      () => _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.get<dynamic>(
          '/workout-schedule',
          options: Options(headers: headers),
        ),
      ),
    );
    if (response == null) {
      return local;
    }
    if (_routeLooksUnsupported(response)) {
      _markWorkoutScheduleUnsupported(response);
      return local;
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.loadSchedule',
    );
    final data = _unwrapData(response.data);
    if (data is! List) {
      return local;
    }
    _workoutScheduleBackendSupported = true;
    final remote = data.map(_mapWorkoutScheduleEntry).toList();
    await _scheduleFallback.replace(session, remote);
    return remote;
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
    );
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
    if (normalized.isEmpty) {
      return const [];
    }
    final cached = _exerciseSearchCache[normalized];
    if (cached != null && cached.isFresh) {
      return cached.value;
    }
    try {
      final response = await _dio.get<dynamic>(
        '/exercises/search',
        queryParameters: {'q': normalized},
      ).timeout(const Duration(milliseconds: 1500));
      if (response.statusCode == null || response.statusCode! >= 400) {
        return cached?.value ?? const [];
      }
      final data = _unwrapData(response.data);
      if (data is! List) {
        return cached?.value ?? const [];
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
      _exerciseSearchCache[normalized] = _CacheEntry(
        suggestions,
        ttl: FrontendCachePolicy.exerciseSearch,
      );
      return suggestions;
    } catch (_) {
      return cached?.value ?? const [];
    }
  }

  @override
  Future<WorkoutTemplateDraft> saveTemplate(
    AuthSession? session,
    WorkoutTemplateDraft template,
  ) async {
    if (session == null) {
      throw Exception(
        'Authentication session missing in workout template repository.\n'
        'source: lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.saveTemplate\n'
        'problem: saveTemplate received session == null, so no Authorization header could be created.\n'
        'backend_request_sent: false\n'
        'expected: AppDraftController should resolve AuthSession before calling this repository.\n'
        'fix: Verify authSessionProvider and AuthRepository.currentSession() both contain the Supabase session after login.',
      );
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
    final richPayload = workoutTemplateRichPayload(
      normalized,
      resolvedExercises,
    );
    final response = await _sendWorkoutTemplatePayload(
      session,
      normalized.templateId,
      richPayload,
    );
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.saveTemplate',
    );
    final mapped = _mapWorkoutTemplate(_unwrapData(response.data));
    final responseTemplateId =
        _toNullableInt(_asMap(_unwrapData(response.data))['template_id']);
    final saved = mapped.name.trim().isEmpty
        ? normalized.copyWith(
            templateId: responseTemplateId ?? normalized.templateId,
          )
        : mapped;
    final readBack = await _readBackTemplateIfSupported(session, saved);
    _cacheSavedTemplate(session, readBack);
    return readBack;
  }

  Future<Response<dynamic>> _sendWorkoutTemplatePayload(
    AuthSession session,
    int? templateId,
    Map<String, Object?> payload,
  ) {
    return templateId == null
        ? _requestWithSessionRetry(
            _dio,
            session,
            (headers) => _dio.post<dynamic>(
              '/workout-templates',
              data: payload,
              options: Options(headers: headers),
            ),
          )
        : _requestWithSessionRetry(
            _dio,
            session,
            (headers) => _dio.patch<dynamic>(
              '/workout-templates/$templateId',
              data: payload,
              options: Options(headers: headers),
            ),
          );
  }

  Future<WorkoutTemplateDraft> _readBackTemplateIfSupported(
    AuthSession session,
    WorkoutTemplateDraft saved,
  ) async {
    final templateId = saved.templateId;
    if (templateId == null) {
      return saved;
    }
    final response = await _recoverableLoadRequest(
      () => _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.get<dynamic>(
          '/workout-templates/$templateId',
          options: Options(headers: headers),
        ),
      ),
    );
    if (response == null || _routeLooksUnsupported(response)) {
      return saved;
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository._readBackTemplateIfSupported',
    );
    final mapped = _mapWorkoutTemplate(_unwrapData(response.data));
    return mapped.name.trim().isEmpty ? saved : mapped;
  }

  @override
  Future<void> deleteTemplate(AuthSession? session, int templateId) async {
    if (session == null) {
      throw Exception(
        'Authentication session missing in workout template repository.\n'
        'source: lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.deleteTemplate\n'
        'problem: deleteTemplate received session == null, so no Authorization header could be created.\n'
        'backend_request_sent: false',
      );
    }
    final response = await _requestWithSessionRetry(
      _dio,
      session,
      (headers) => _dio.delete<dynamic>(
        '/workout-templates/$templateId',
        options: Options(headers: headers),
      ),
    );
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.deleteTemplate',
    );
    final cached = _templatesCache[session.userId]?.value;
    if (cached != null) {
      _templatesCache[session.userId] = _CacheEntry(
        cached
            .where((template) => template.templateId != templateId)
            .toList(growable: false),
        ttl: FrontendCachePolicy.templates,
      );
    }
  }

  void _cacheSavedTemplate(
    AuthSession session,
    WorkoutTemplateDraft saved,
  ) {
    final current = _templatesCache[session.userId]?.value ?? const [];
    final index = current.indexWhere(
      (template) => template.templateId == saved.templateId,
    );
    final updated = [...current];
    if (index == -1) {
      updated.add(saved);
    } else {
      updated[index] = saved;
    }
    _templatesCache[session.userId] = _CacheEntry(
      updated,
      ttl: FrontendCachePolicy.templates,
    );
  }

  @override
  Future<WorkoutScheduleEntry> saveScheduleEntry(
    AuthSession? session,
    WorkoutScheduleEntry entry,
  ) async {
    if (session == null) {
      return _scheduleFallback.save(session, entry);
    }
    if (_workoutScheduleBackendSupported == false) {
      return _scheduleFallback.save(session, entry);
    }
    final payload = _workoutSchedulePayload(session, entry);
    final scheduleId = entry.scheduleId;
    try {
      final response = scheduleId == null || scheduleId.startsWith('local-')
          ? await _requestWithSessionRetry(
              _dio,
              session,
              (headers) => _dio.post<dynamic>(
                '/workout-schedule',
                data: payload,
                options: Options(headers: headers),
              ),
            )
          : await _requestWithSessionRetry(
              _dio,
              session,
              (headers) => _dio.patch<dynamic>(
                '/workout-schedule/$scheduleId',
                data: payload,
                options: Options(headers: headers),
              ),
            );
      if (_routeLooksUnsupported(response)) {
        _markWorkoutScheduleUnsupported(response);
        return _scheduleFallback.save(session, entry);
      }
      _throwIfRequestFailed(
        response,
        source:
            'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.saveScheduleEntry',
      );
      final saved = _mapWorkoutScheduleEntry(_unwrapData(response.data));
      await _scheduleFallback.save(session, saved);
      _workoutScheduleBackendSupported = true;
      return saved;
    } on DioException catch (error) {
      if (_isRecoverableLoadFailure(error) ||
          _routeLooksUnsupported(error.response)) {
        if (_routeLooksUnsupported(error.response)) {
          _markWorkoutScheduleUnsupported(error.response);
        }
        return _scheduleFallback.save(session, entry);
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteScheduleEntry(
    AuthSession? session,
    WorkoutScheduleEntry entry,
  ) async {
    if (session == null) {
      await _scheduleFallback.delete(session, entry);
      return;
    }
    if (_workoutScheduleBackendSupported == false) {
      await _scheduleFallback.delete(session, entry);
      return;
    }
    final scheduleId = entry.scheduleId;
    if (scheduleId == null || scheduleId.startsWith('local-')) {
      await _scheduleFallback.delete(session, entry);
      return;
    }
    try {
      final response = await _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.delete<dynamic>(
          '/workout-schedule/$scheduleId',
          options: Options(headers: headers),
        ),
      );
      if (!_routeLooksUnsupported(response)) {
        _throwIfRequestFailed(
          response,
          source:
              'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.deleteScheduleEntry',
        );
        _workoutScheduleBackendSupported = true;
      } else {
        _markWorkoutScheduleUnsupported(response);
      }
    } on DioException catch (error) {
      if (!_isRecoverableLoadFailure(error) &&
          !_routeLooksUnsupported(error.response)) {
        rethrow;
      }
      if (_routeLooksUnsupported(error.response)) {
        _markWorkoutScheduleUnsupported(error.response);
      }
    }
    await _scheduleFallback.delete(session, entry);
  }

  void _markWorkoutScheduleUnsupported(Response<dynamic>? response) {
    _workoutScheduleBackendSupported = false;
    if (kDebugMode) {
      debugPrint(
        'JimBro schedule backend unsupported status=${response?.statusCode ?? 'unknown'} route=/workout-schedule; using local schedule store.',
      );
    }
  }

  @override
  Future<WorkoutLogDraft> saveWorkoutLog(
    AuthSession? session,
    WorkoutLogDraft log,
  ) async {
    if (session == null) {
      throw Exception(
        'Authentication session missing in workout log repository.\n'
        'source: lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.saveWorkoutLog\n'
        'problem: saveWorkoutLog received session == null, so no Authorization header could be created.\n'
        'backend_request_sent: false\n'
        'expected: AppDraftController should resolve AuthSession before calling this repository.\n'
        'fix: Verify authSessionProvider and AuthRepository.currentSession() both contain the Supabase session after login.',
      );
    }
    try {
      final saved = await _saveWorkoutLogOnline(session, log);
      await flushPending(session);
      return saved;
    } on DioException catch (error) {
      if (_shouldQueueOffline(error)) {
        final normalized = _validateWorkoutLogDraft(log);
        await _outbox.enqueue(
          session,
          OfflineOutboxItem(
            localId: _localMutationId('workout-log'),
            operationType: 'workout_log_create',
            payload: workoutLogDraftToJson(normalized),
            createdAt: DateTime.now(),
            retryCount: 0,
            lastErrorCode: _dioErrorCode(error),
            lastErrorMessage: _safeErrorSummary(error),
          ),
        );
        return normalized;
      }
      rethrow;
    }
  }

  Future<WorkoutLogDraft> _saveWorkoutLogOnline(
    AuthSession session,
    WorkoutLogDraft log,
  ) async {
    final normalized = _validateWorkoutLogDraft(log);
    final resolvedExercises = <WorkoutExerciseDraft>[];
    for (final exercise in normalized.exercises) {
      resolvedExercises.add(
        exercise.copyWith(
          exerciseId: await _resolveExerciseId(_dio, session, exercise),
        ),
      );
    }
    final richPayload = workoutLogRichPayload(normalized, resolvedExercises);
    if (normalized.workoutLogId != null) {
      final response = await _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.patch<dynamic>(
          '/workout-logs/${normalized.workoutLogId}',
          data: workoutLogMetadataPatchPayload(normalized),
          options: Options(headers: headers),
        ),
      );
      _throwIfRequestFailed(
        response,
        source:
            'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.saveWorkoutLog.patch',
      );
      final mapped = _mapWorkoutLog(_unwrapData(response.data));
      return mapped.exercises.isEmpty ? normalized : mapped;
    }
    final response = await _requestWithSessionRetry(
      _dio,
      session,
      (headers) => _dio.post<dynamic>(
        '/workout-logs',
        data: richPayload,
        options: Options(headers: headers),
      ),
    );
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository.saveWorkoutLog.post',
    );
    final mapped = _mapWorkoutLog(_unwrapData(response.data));
    final responseLogId =
        _toNullableInt(_asMap(_unwrapData(response.data))['workout_log_id']);
    final saved = mapped.exercises.isEmpty
        ? normalized.copyWith(workoutLogId: responseLogId)
        : mapped;
    return _readBackWorkoutLogIfSupported(session, saved);
  }

  @override
  Future<void> flushPending(AuthSession? session) async {
    if (session == null) {
      return;
    }
    final items = await _outbox.load(session);
    for (final item in items) {
      if (item.needsReview || item.operationType != 'workout_log_create') {
        continue;
      }
      try {
        await _saveWorkoutLogOnline(
            session, workoutLogDraftFromJson(item.payload));
        await _outbox.remove(session, item.localId);
      } on AuthSessionExpiredException {
        return;
      } on DioException catch (error) {
        final status = error.response?.statusCode ?? 0;
        if (status == 401) {
          return;
        }
        await _outbox.update(
          session,
          item.copyWith(
            retryCount: item.retryCount + 1,
            lastErrorCode: _dioErrorCode(error),
            lastErrorMessage: _safeErrorSummary(error),
            needsReview: status == 400 || status == 422,
          ),
        );
        if (!_shouldQueueOffline(error)) {
          continue;
        }
      }
    }
  }

  Future<WorkoutLogDraft> _readBackWorkoutLogIfSupported(
    AuthSession session,
    WorkoutLogDraft saved,
  ) async {
    final logId = saved.workoutLogId;
    if (logId == null) {
      return saved;
    }
    final response = await _recoverableLoadRequest(
      () => _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.get<dynamic>(
          '/workout-logs/$logId',
          options: Options(headers: headers),
        ),
      ),
    );
    if (response == null || _routeLooksUnsupported(response)) {
      return saved;
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiWorkoutRepository._readBackWorkoutLogIfSupported',
    );
    final mapped = _mapWorkoutLog(_unwrapData(response.data));
    return mapped.exercises.isEmpty ? saved : mapped;
  }
}

class MockNutritionRepository implements NutritionRepository {
  List<FoodLogDraft> _foodLogs = const [];

  @override
  Future<List<FoodLogDraft>> loadFoodLogs(AuthSession? session) async =>
      _foodLogs;

  @override
  Future<DailyNutritionSummary> loadSummary(AuthSession? session) async =>
      _summaryFor(_foodLogs);

  @override
  Future<List<FoodSuggestion>> searchFoods(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const [];
    }
    return _localFoodSuggestions(normalized);
  }

  @override
  Future<List<FoodLogDraft>> saveFoodLogs(
    AuthSession? session,
    List<FoodLogDraft> logs,
  ) async {
    _foodLogs = logs;
    return _foodLogs;
  }

  @override
  Future<void> flushPending(AuthSession? session) async {}

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
      targetCalories: 0,
      consumedCalories: calories,
      proteinTarget: 0,
      proteinConsumed: protein,
      carbsTarget: 0,
      carbsConsumed: carbs,
      fatTarget: 0,
      fatConsumed: fat,
      hydrationTargetLiters: 0,
      hydrationConsumedLiters: 0,
    );
  }
}

class FastApiNutritionRepository implements NutritionRepository {
  FastApiNutritionRepository(
    this._dio, {
    OfflineOutboxStore? outbox,
  }) : _outbox = outbox ?? const OfflineOutboxStore();

  final Dio _dio;
  final OfflineOutboxStore _outbox;
  final _foodSearchCache = <String, _CacheEntry<List<FoodSuggestion>>>{};
  final _todayFoodLogCache = <String, _CacheEntry<List<FoodLogDraft>>>{};
  final _summaryCache = <String, _CacheEntry<DailyNutritionSummary>>{};

  @override
  Future<List<FoodLogDraft>> loadFoodLogs(AuthSession? session) async {
    if (session == null) {
      return const [];
    }
    final cacheKey = '${session.userId}:${_todayIso()}';
    final cached = _todayFoodLogCache[cacheKey];
    final response = await _recoverableLoadRequest(
      () => _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.get<dynamic>(
          '/food-log',
          queryParameters: {'date': _todayIso(), 'limit': 100},
          options: Options(headers: headers),
        ),
      ),
    );
    if (response == null) {
      return cached?.value ?? const [];
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiNutritionRepository.loadFoodLogs',
    );
    final data = _unwrapData(response.data);
    if (data is! List) {
      return cached?.value ?? const [];
    }
    final logs = data.map<FoodLogDraft>((item) => _mapFoodLog(item)).toList();
    _todayFoodLogCache[cacheKey] = _CacheEntry(
      logs,
      ttl: FrontendCachePolicy.todayFoodLog,
    );
    return logs;
  }

  @override
  Future<DailyNutritionSummary> loadSummary(AuthSession? session) async {
    if (session == null) {
      return DailyNutritionSummary.empty;
    }
    final cacheKey = '${session.userId}:${_todayIso()}';
    final cached = _summaryCache[cacheKey];
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
      final logs = await loadFoodLogs(session);
      return cached?.value ?? nutritionSummaryFromFoodLogs(logs);
    }
    if (_routeLooksUnsupported(response)) {
      if (kDebugMode) {
        debugPrint(
          'JimBro food summary endpoint unavailable status=${response.statusCode ?? 'unknown'} route=/food-log/summary/YYYY-MM-DD; aggregating food-log rows.',
        );
      }
      final logs = await loadFoodLogs(session);
      return nutritionSummaryFromFoodLogs(logs);
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiNutritionRepository.loadSummary',
    );
    final data = _unwrapData(response.data);
    if (data is! Map<String, dynamic>) {
      return cached?.value ?? DailyNutritionSummary.empty;
    }
    final summary = dailyNutritionSummaryFromBackend(data);
    _summaryCache[cacheKey] = _CacheEntry(
      summary,
      ttl: FrontendCachePolicy.dashboard,
    );
    return summary;
  }

  @override
  Future<List<FoodSuggestion>> searchFoods(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
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
        return cached?.value ?? const [];
      }
      final data = _unwrapData(response.data);
      if (data is! List) {
        return cached?.value ?? const [];
      }
      final suggestions = data
          .map<FoodSuggestion?>((item) {
            final map = _asMap(item);
            final id = map['food_id']?.toString() ?? '';
            final name = map['name']?.toString() ?? '';
            if (id.trim().isEmpty || name.trim().isEmpty) {
              return null;
            }
            return foodSuggestionFromBackend(map);
          })
          .whereType<FoodSuggestion>()
          .toList();
      _foodSearchCache[normalized] = _CacheEntry(
        suggestions,
        ttl: FrontendCachePolicy.foodSearch,
      );
      return suggestions;
    } catch (_) {
      return cached?.value ?? const [];
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
    try {
      final saved = await _saveFoodLogsOnline(session, logs);
      await flushPending(session);
      return saved;
    } on DioException catch (error) {
      if (_shouldQueueOffline(error)) {
        final normalized = logs.map(_validateFoodLogDraft).toList();
        _cacheTodayFoodLogs(session, normalized);
        await _outbox.enqueue(
          session,
          OfflineOutboxItem(
            localId: _localMutationId('nutrition-batch'),
            operationType: 'nutrition_logs_replace',
            payload: {
              'logs': normalized.map(foodLogDraftToJson).toList(),
            },
            createdAt: DateTime.now(),
            retryCount: 0,
            lastErrorCode: _dioErrorCode(error),
            lastErrorMessage: _safeErrorSummary(error),
          ),
        );
        return normalized;
      }
      rethrow;
    }
  }

  Future<List<FoodLogDraft>> _saveFoodLogsOnline(
    AuthSession session,
    List<FoodLogDraft> logs,
  ) async {
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
          data: foodLogBackendPayload(normalized, foodId: foodId, date: date),
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
    _cacheTodayFoodLogs(session, saved);
    return saved;
  }

  void _cacheTodayFoodLogs(AuthSession session, List<FoodLogDraft> logs) {
    final cacheKey = '${session.userId}:${_todayIso()}';
    _todayFoodLogCache[cacheKey] = _CacheEntry(
      logs,
      ttl: FrontendCachePolicy.todayFoodLog,
    );
    _summaryCache[cacheKey] = _CacheEntry(
      nutritionSummaryFromFoodLogs(logs),
      ttl: FrontendCachePolicy.dashboard,
    );
  }

  @override
  Future<void> flushPending(AuthSession? session) async {
    if (session == null) {
      return;
    }
    final items = await _outbox.load(session);
    for (final item in items) {
      if (item.needsReview || item.operationType != 'nutrition_logs_replace') {
        continue;
      }
      try {
        final rawLogs = item.payload['logs'];
        final logs = rawLogs is List
            ? rawLogs.map(foodLogDraftFromJson).toList(growable: false)
            : const <FoodLogDraft>[];
        await _saveFoodLogsOnline(session, logs);
        await _outbox.remove(session, item.localId);
      } on AuthSessionExpiredException {
        return;
      } on DioException catch (error) {
        final status = error.response?.statusCode ?? 0;
        if (status == 401) {
          return;
        }
        await _outbox.update(
          session,
          item.copyWith(
            retryCount: item.retryCount + 1,
            lastErrorCode: _dioErrorCode(error),
            lastErrorMessage: _safeErrorSummary(error),
            needsReview: status == 400 || status == 422,
          ),
        );
      }
    }
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
        data: customFoodBackendPayload(log, factor: factor),
        options: Options(headers: headers),
      ),
    );
    if (_routeLooksUnsupported(response)) {
      throw Exception(
        'Custom food creation is not available on this backend yet. Select a catalog result from search or retry when /food is enabled.',
      );
    }
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiNutritionRepository._createFoodForLog',
    );
    final data = _asMap(_unwrapData(response.data));
    final foodId = data['food_id']?.toString();
    if (foodId == null || foodId.isEmpty) {
      throw Exception(
        'The backend created "${log.foodName}" but did not return a food_id.',
      );
    }
    return foodId;
  }
}

class MockAgentContextRepository implements AgentContextRepository {
  @override
  Future<AgentContextSnapshot> load(AuthSession? session) async {
    return AgentContextSnapshot.empty;
  }
}

class MockProgramRepository implements ProgramRepository {
  @override
  Future<ProgramGenerationResult> generateProgram(AuthSession? session) async {
    return const ProgramGenerationResult.success('Mock program generated.');
  }
}

class FastApiProgramRepository implements ProgramRepository {
  FastApiProgramRepository(this._dio);

  final Dio _dio;

  @override
  Future<ProgramGenerationResult> generateProgram(AuthSession? session) async {
    if (session == null || session.provider == 'mock') {
      return const ProgramGenerationResult.success();
    }
    try {
      final response = await _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.post<dynamic>(
          '/programs/generate',
          options: Options(headers: headers),
        ),
      );
      if ((response.statusCode ?? 0) >= 200 &&
          (response.statusCode ?? 0) < 300) {
        return ProgramGenerationResult.success(
          _programGenerationMessage(response.data),
        );
      }
      return const ProgramGenerationResult.failure(
        'Jim could not build your split yet. You can retry or skip for now.',
      );
    } on AuthSessionExpiredException {
      rethrow;
    } catch (_) {
      return const ProgramGenerationResult.failure(
        'Jim could not build your split yet. You can retry or skip for now.',
      );
    }
  }
}

class FastApiAgentContextRepository implements AgentContextRepository {
  FastApiAgentContextRepository(this._dio);

  final Dio _dio;

  @override
  Future<AgentContextSnapshot> load(AuthSession? session) async {
    if (session == null || session.provider == 'mock') {
      return AgentContextSnapshot.empty;
    }

    final contextResponse = await _get(session, '/agent/context');
    if (contextResponse != null &&
        contextResponse.statusCode != 404 &&
        contextResponse.statusCode != 405 &&
        (contextResponse.statusCode ?? 0) < 500) {
      _throwIfRequestFailed(
        contextResponse,
        source:
            'lib/core/repositories/app_repositories.dart -> FastApiAgentContextRepository.load',
        session: session,
      );
      return agentContextFromBackend(contextResponse.data);
    }

    final responses = await Future.wait<Response<dynamic>?>([
      _get(session, '/atlas/metrics'),
      _get(session, '/food-log/summary/${_todayIso()}'),
      _get(session, '/workout-logs/trends'),
      _get(session, '/workout-logs'),
      _get(session, '/workout-templates'),
    ]);
    for (final response in responses.whereType<Response<dynamic>>()) {
      if ((response.statusCode ?? 0) >= 500) {
        continue;
      }
      _throwIfRequestFailed(
        response,
        source:
            'lib/core/repositories/app_repositories.dart -> FastApiAgentContextRepository.load fallback',
        session: session,
        allowNotFoundAsEmpty: true,
      );
    }

    return AgentContextSnapshot(
      atlasMetrics: _successfulData(responses[0]) == null
          ? null
          : _mapAtlasMetrics(responses[0]!.data),
      todaysNutrition: _successfulData(responses[1]) == null
          ? null
          : dailyNutritionSummaryFromBackend(
              _asMap(_unwrapData(responses[1]!.data)),
            ),
      workoutTrends: _successfulData(responses[2]) == null
          ? WorkoutTrendSummary.empty
          : _mapWorkoutTrends(responses[2]!.data),
      recentWorkouts: _mapWorkoutLogList(_successfulData(responses[3])),
      activeTemplate: _mapActiveTemplate(_successfulData(responses[4])),
      usedFallbackEndpoints: true,
    );
  }

  Future<Response<dynamic>?> _get(AuthSession session, String path) {
    return _recoverableLoadRequest(
      () => _requestWithSessionRetry(
        _dio,
        session,
        (headers) => _dio.get<dynamic>(
          path,
          options: Options(headers: headers),
        ),
      ),
    );
  }

  dynamic _successfulData(Response<dynamic>? response) {
    final status = response?.statusCode ?? 0;
    return status >= 200 && status < 300 ? response?.data : null;
  }
}

class MockJimChatRepository implements JimChatRepository {
  @override
  Future<JimChatResponse> send(
    AuthSession? session, {
    required String sessionId,
    required String message,
    required JimChatMode mode,
    String? selectedOption,
  }) async {
    final response = selectedOption == null
        ? atlasMockResponseForChat(message)
        : 'Local mock selection received. No workout or food was logged.';
    return JimChatResponse(
      sessionId: sessionId,
      message: response,
    );
  }

  @override
  Stream<JimChatStreamEvent> stream(
    AuthSession? session, {
    required String sessionId,
    required String message,
    required JimChatMode mode,
  }) async* {
    final response = await send(
      session,
      sessionId: sessionId,
      message: message,
      mode: mode,
    );
    yield JimChatStreamEvent.textDelta(response.message);
    yield JimChatStreamEvent.done(response);
  }

  @override
  Future<void> endSession(AuthSession? session, String sessionId) async {}
}

class FastApiJimChatRepository implements JimChatRepository {
  FastApiJimChatRepository(this._dio);

  final Dio _dio;

  @override
  Future<JimChatResponse> send(
    AuthSession? session, {
    required String sessionId,
    required String message,
    required JimChatMode mode,
    String? selectedOption,
  }) async {
    final activeSession = _requireChatSession(session);
    final response = await _requestWithSessionRetry(
      _dio,
      activeSession,
      (headers) => _dio.post<dynamic>(
        '/chat/',
        data: jimChatRequestPayload(
          sessionId: sessionId,
          message: selectedOption == null ? message : '',
          mode: mode,
          selectedOption: selectedOption,
        ),
        options: Options(headers: headers),
      ),
    );
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiJimChatRepository.send',
      session: activeSession,
    );
    return jimChatResponseFromBackend(response.data);
  }

  @override
  Stream<JimChatStreamEvent> stream(
    AuthSession? session, {
    required String sessionId,
    required String message,
    required JimChatMode mode,
  }) async* {
    final activeSession = _requireChatSession(session);
    final response = await _requestWithSessionRetry(
      _dio,
      activeSession,
      (headers) => _dio.post<ResponseBody>(
        '/chat/stream',
        data: jimChatRequestPayload(
          sessionId: sessionId,
          message: message,
          mode: mode,
        ),
        options: Options(
          headers: {
            ...headers,
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
          },
          responseType: ResponseType.stream,
        ),
      ),
    );
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiJimChatRepository.stream',
      session: activeSession,
    );
    final body = response.data;
    if (body is! ResponseBody) {
      throw Exception('Chat stream returned no event stream.');
    }
    yield* parseJimChatSse(body.stream.map((chunk) => chunk.toList()));
  }

  @override
  Future<void> endSession(AuthSession? session, String sessionId) async {
    final activeSession = _requireChatSession(session);
    final response = await _requestWithSessionRetry(
      _dio,
      activeSession,
      (headers) => _dio.delete<dynamic>(
        '/chat/$sessionId',
        options: Options(headers: headers),
      ),
    );
    _throwIfRequestFailed(
      response,
      source:
          'lib/core/repositories/app_repositories.dart -> FastApiJimChatRepository.endSession',
      session: activeSession,
      allowNotFoundAsEmpty: true,
    );
  }
}

AuthSession _requireChatSession(AuthSession? session) {
  if (session == null) {
    throw Exception('Sign in before starting a live Jim chat.');
  }
  return session;
}

Map<String, Object?> jimChatRequestPayload({
  required String sessionId,
  required String message,
  required JimChatMode mode,
  String? selectedOption,
}) {
  return {
    'session_id': sessionId,
    'message': message,
    'mode': mode.wireName,
    if (selectedOption != null) 'selected_option': selectedOption,
  };
}

JimChatResponse jimChatResponseFromBackend(dynamic raw) {
  final data = _asMap(_unwrapData(raw));
  final options = data['options'] ?? data['clarification_options'];
  final responseType = data['type']?.toString().toLowerCase();
  return JimChatResponse(
    sessionId: data['session_id']?.toString() ?? '',
    message:
        (data['reply'] ?? data['message'] ?? data['response'] ?? data['text'])
                ?.toString() ??
            '',
    requiresClarification: data['requires_clarification'] == true ||
        responseType == 'clarification',
    clarificationPrompt:
        (data['prompt'] ?? data['clarification_prompt'])?.toString(),
    clarificationOptions: options is List
        ? options
            .map((rawOption) {
              final option = _asMap(rawOption);
              return JimClarificationOption(
                id: option['id']?.toString() ?? '',
                label: option['label']?.toString() ?? '',
              );
            })
            .where((option) => option.id.isNotEmpty && option.label.isNotEmpty)
            .toList(growable: false)
        : const [],
    actionsTaken: _stringList(data['actions_taken']),
  );
}

Stream<JimChatStreamEvent> parseJimChatSse(Stream<List<int>> bytes) async* {
  var eventName = '';
  final dataLines = <String>[];

  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (dataLines.isNotEmpty) {
        yield _jimChatEventFromSse(eventName, dataLines.join('\n'));
      }
      eventName = '';
      dataLines.clear();
      continue;
    }
    if (line.startsWith(':')) {
      continue;
    }
    if (line.startsWith('event:')) {
      eventName = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trimLeft());
    } else {
      // Some deployments stream plain text or JSON chunks without SSE fields.
      dataLines.add(line);
    }
  }
  if (dataLines.isNotEmpty) {
    yield _jimChatEventFromSse(eventName, dataLines.join('\n'));
  }
}

JimChatStreamEvent _jimChatEventFromSse(String eventName, String rawData) {
  if (rawData.trim() == '[DONE]') {
    return JimChatStreamEvent.done(
      const JimChatResponse(sessionId: '', message: ''),
    );
  }
  dynamic decoded;
  try {
    decoded = jsonDecode(rawData);
  } catch (_) {
    decoded = rawData;
  }
  final data = _asMap(decoded);
  final type = (eventName.isEmpty ? data['type'] : eventName)
          ?.toString()
          .toLowerCase() ??
      'text_delta';
  if (type == 'done' || type == 'complete' || type == 'completed') {
    return JimChatStreamEvent.done(jimChatResponseFromBackend(data));
  }
  if (type == 'error' || type == 'failed') {
    return JimChatStreamEvent.error(
      (data['error'] ?? data['message'] ?? rawData).toString(),
    );
  }
  return JimChatStreamEvent.textDelta(
    (data['text_delta'] ??
            data['delta'] ??
            data['text'] ??
            data['reply'] ??
            data['message'] ??
            decoded)
        .toString(),
  );
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) {
    return const [];
  }
  return raw
      .map((value) => value is Map
          ? (value['type'] ?? value['action'])?.toString() ?? ''
          : value.toString())
      .where((value) => value.trim().isNotEmpty)
      .toList(growable: false);
}

String atlasMockResponseForChat(String message) {
  final normalized = message.trim().toLowerCase();
  if (normalized.contains('supplement') || normalized.contains('creatine')) {
    return 'Local mock guidance: supplements are optional. Training, food, sleep, and recovery remain the foundation. This is general information, not medical advice.';
  }
  return 'Local mock response: Jim can discuss training, nutrition, and general fitness here. No backend action was performed.';
}

class MockConsistencyRepository implements ConsistencyRepository {
  ConsistencyState _consistency = const ConsistencyState(
    currentStreak: 0,
    longestStreak: 0,
    weeklyCheckins: 0,
    totalLogs: 0,
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
        title: 'Start with one useful action',
        mainText:
            'Log a workout or a meal today and Jim will have a stronger signal for the next coaching step.',
        confidence: AtlasConfidence.medium,
        actionItems: const ['Pick one workout', 'Log one meal'],
      ),
      const AtlasInsight(
        title: 'Build signal before complexity',
        mainText:
            'A few honest entries are more useful than a perfect plan you never update. Keep the first week simple.',
        confidence: AtlasConfidence.medium,
        actionItems: ['Repeat one template', 'Use simple meal logs'],
      ),
    ];
  }

  @override
  Future<AtlasInsight> loadHistoryInsight(AuthSession? session) async {
    return const AtlasInsight(
      title: 'Progress needs real logs',
      mainText:
          'Finish workouts with reps and weight so Jim can turn your history into truthful progression notes.',
      confidence: AtlasConfidence.medium,
      actionItems: ['Finish a workout', 'Enter reps and weight'],
    );
  }

  @override
  Future<AtlasInsight> loadNutritionInsight(
    AuthSession? session,
    DailyNutritionSummary summary,
  ) async {
    final shortfall = (summary.proteinTarget - summary.proteinConsumed).round();
    if (summary.proteinTarget <= 0) {
      return const AtlasInsight(
        title: 'Targets unlock after profile setup',
        mainText:
            'Add profile basics to estimate calories, protein, and hydration. Until then, logged totals still count.',
        confidence: AtlasConfidence.medium,
        actionItems: ['Finish profile basics', 'Log one meal'],
      );
    }
    if (shortfall <= 0) {
      return const AtlasInsight(
        title: 'Protein target covered',
        mainText:
            'You have reached today’s protein target. Keep the rest of the day simple and repeatable.',
        confidence: AtlasConfidence.medium,
        actionItems: ['Stay consistent', 'Log remaining meals'],
      );
    }
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

class FrontendCachePolicy {
  const FrontendCachePolicy._();

  static const profile = Duration(minutes: 30);
  static const templates = Duration(minutes: 10);
  static const exerciseSearch = Duration(minutes: 5);
  static const foodSearch = Duration(minutes: 5);
  static const todayFoodLog = Duration(minutes: 2);
  static const dashboard = Duration(minutes: 2);
}

class _CacheEntry<T> {
  _CacheEntry(
    this.value, {
    this.ttl = const Duration(minutes: 5),
  }) : createdAt = DateTime.now();

  final T value;
  final Duration ttl;
  final DateTime createdAt;

  bool get isFresh => DateTime.now().difference(createdAt) < ttl;
}

class OfflineOutboxItem {
  const OfflineOutboxItem({
    required this.localId,
    required this.operationType,
    required this.payload,
    required this.createdAt,
    required this.retryCount,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.dependencyId,
    this.needsReview = false,
  });

  final String localId;
  final String operationType;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final String? dependencyId;
  final bool needsReview;

  OfflineOutboxItem copyWith({
    int? retryCount,
    String? lastErrorCode,
    String? lastErrorMessage,
    bool? needsReview,
  }) {
    return OfflineOutboxItem(
      localId: localId,
      operationType: operationType,
      payload: payload,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
      dependencyId: dependencyId,
      needsReview: needsReview ?? this.needsReview,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'local_id': localId,
      'operation_type': operationType,
      'payload': payload,
      'created_at': createdAt.toIso8601String(),
      'retry_count': retryCount,
      'last_error_code': lastErrorCode,
      'last_error_message': lastErrorMessage,
      'dependency_id': dependencyId,
      'needs_review': needsReview,
    };
  }

  static OfflineOutboxItem? fromJson(dynamic raw) {
    final map = _asMap(raw);
    final localId = map['local_id']?.toString() ?? '';
    final operationType = map['operation_type']?.toString() ?? '';
    final payload = _asMap(map['payload']);
    final createdAt = DateTime.tryParse(
          map['created_at']?.toString() ?? '',
        ) ??
        DateTime.now();
    if (localId.isEmpty || operationType.isEmpty || payload.isEmpty) {
      return null;
    }
    return OfflineOutboxItem(
      localId: localId,
      operationType: operationType,
      payload: payload,
      createdAt: createdAt,
      retryCount: _toInt(map['retry_count'], 0),
      lastErrorCode: map['last_error_code']?.toString(),
      lastErrorMessage: map['last_error_message']?.toString(),
      dependencyId: map['dependency_id']?.toString(),
      needsReview: map['needs_review'] == true,
    );
  }
}

class OfflineOutboxStore {
  const OfflineOutboxStore();

  Future<List<OfflineOutboxItem>> load(AuthSession? session) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(session));
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .map(OfflineOutboxItem.fromJson)
          .whereType<OfflineOutboxItem>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> enqueue(AuthSession? session, OfflineOutboxItem item) async {
    final current = await load(session);
    if (current.any((existing) => existing.localId == item.localId)) {
      return;
    }
    await replace(session, [...current, item]);
  }

  Future<void> replace(
    AuthSession? session,
    List<OfflineOutboxItem> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(session),
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> remove(AuthSession? session, String localId) async {
    final current = await load(session);
    await replace(
      session,
      current.where((item) => item.localId != localId).toList(),
    );
  }

  Future<void> update(AuthSession? session, OfflineOutboxItem item) async {
    final current = await load(session);
    await replace(
      session,
      current
          .map((existing) => existing.localId == item.localId ? item : existing)
          .toList(),
    );
  }

  String _key(AuthSession? session) {
    return 'offline_outbox_${session?.userId ?? 'anonymous'}';
  }
}

class LocalWorkoutScheduleStore {
  const LocalWorkoutScheduleStore();

  Future<List<WorkoutScheduleEntry>> load(AuthSession? session) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(session));
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .map<WorkoutScheduleEntry?>((item) {
            final map = _asMap(item);
            if (map.isEmpty) {
              return null;
            }
            return WorkoutScheduleEntry.fromJson(map);
          })
          .whereType<WorkoutScheduleEntry>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> replace(
    AuthSession? session,
    List<WorkoutScheduleEntry> schedule,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(session),
      jsonEncode(schedule.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<WorkoutScheduleEntry> save(
    AuthSession? session,
    WorkoutScheduleEntry entry,
  ) async {
    final current = await load(session);
    final saved = entry.copyWith(
      scheduleId: entry.scheduleId ?? _localScheduleId(entry),
      userId: entry.userId ?? session?.userId,
    );
    final updated = _upsertLocalWorkoutSchedule(current, saved);
    await replace(session, updated);
    return saved;
  }

  Future<void> delete(
    AuthSession? session,
    WorkoutScheduleEntry entry,
  ) async {
    final current = await load(session);
    final updated = current
        .where(
          (item) =>
              item.scheduleId != entry.scheduleId &&
              item.weekday != entry.weekday,
        )
        .toList(growable: false);
    await replace(session, updated);
  }

  String _key(AuthSession? session) {
    final userId = session?.userId.trim();
    return 'jimbro.workout_schedule.${userId == null || userId.isEmpty ? 'local' : userId}';
  }

  String _localScheduleId(WorkoutScheduleEntry entry) {
    final templateKey = entry.templateId?.toString() ??
        entry.templateName
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return 'local-${entry.weekday}-$templateKey';
  }
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

final agentContextRepositoryProvider = Provider<AgentContextRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.useLiveBackend) {
    return MockAgentContextRepository();
  }
  return FastApiAgentContextRepository(ref.watch(dioProvider));
});

final programRepositoryProvider = Provider<ProgramRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.useLiveBackend) {
    return MockProgramRepository();
  }
  return FastApiProgramRepository(ref.watch(dioProvider));
});

final jimChatRepositoryProvider = Provider<JimChatRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.useLiveBackend) {
    return MockJimChatRepository();
  }
  return FastApiJimChatRepository(ref.watch(dioProvider));
});

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => MockSearchRepository(),
);

Future<String?> _getValidToken() async {
  final refreshed = await Supabase.instance.client.auth.refreshSession();
  return refreshed.session?.accessToken;
}

Session? _safeCurrentSupabaseSession() {
  try {
    return Supabase.instance.client.auth.currentSession;
  } catch (_) {
    return null;
  }
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
    if (payload['iss'] != null) 'jwt_iss': payload['iss'].toString(),
    if (payload['aud'] != null) 'jwt_aud': payload['aud'].toString(),
    if (exp != null) 'jwt_exp': '$exp',
    if (expiresIn != null) 'jwt_expires_in_seconds': '$expiresIn',
  };
}

Future<Map<String, String>> _authHeaders(AuthSession session) async {
  if (session.provider != 'supabase') {
    if (session.accessToken.trim().isEmpty) {
      throw Exception(
        'Authentication token missing before protected backend request.\n'
        'source: lib/core/repositories/app_repositories.dart -> _authHeaders\n'
        'provider: ${session.provider}\n'
        'backend_request_sent: false\n'
        'fix: Sign in again so the app can attach a bearer token.',
      );
    }
    return session.fastApiHeaders;
  }

  try {
    final token = await _getValidToken();
    if (token != null && token.isNotEmpty) {
      return {'Authorization': 'Bearer $token'};
    }
  } catch (error) {
    if (_safeCurrentSupabaseSession() != null) {
      throw Exception(
        'Supabase session refresh failed while creating auth headers.\n'
        'source: lib/core/repositories/app_repositories.dart -> _authHeaders\n'
        'provider: ${session.provider}\n'
        'problem: Supabase had a current session, but refreshSession() failed before the backend request.\n'
        'backend_request_sent: false\n'
        '${kDebugMode ? 'debug_error_type: ${error.runtimeType}\n' : ''}'
        'fix: Sign out/in once. If it repeats, verify Supabase.initialize() is called and .env has SUPABASE_ANON_KEY on one line.',
      );
    }
    throw Exception(
      'Supabase is not initialized while creating auth headers.\n'
      'source: lib/core/repositories/app_repositories.dart -> _authHeaders\n'
      'provider: ${session.provider}\n'
      'problem: The active session is marked supabase, but Supabase.instance is unavailable.\n'
      'backend_request_sent: false\n'
      'likely_cause: .env SUPABASE_ANON_KEY is missing/blank/malformed, so main.dart skipped Supabase.initialize().\n'
      'fix: Put SUPABASE_ANON_KEY=<anon key> on one line in Flutter .env, hot restart the app, then sign in again.\n'
      '${kDebugMode ? 'debug_error_type: ${error.runtimeType}' : ''}',
    );
  }

  throw Exception(
    'Supabase session refresh returned no usable access token.\n'
    'source: lib/core/repositories/app_repositories.dart -> _authHeaders\n'
    'provider: ${session.provider}\n'
    'backend_request_sent: false\n'
    'fix: Sign out and sign in again; the app refused to send a stale token to FastAPI.',
  );
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

bool _shouldQueueOffline(DioException error) {
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError =>
      true,
    DioExceptionType.badResponse ||
    DioExceptionType.badCertificate ||
    DioExceptionType.cancel ||
    DioExceptionType.unknown =>
      false,
  };
}

String _dioErrorCode(DioException error) {
  final statusCode = error.response?.statusCode;
  return statusCode == null ? error.type.name : 'http_$statusCode';
}

String _safeErrorSummary(DioException error) {
  final statusCode = error.response?.statusCode;
  if (statusCode != null) {
    return 'HTTP $statusCode';
  }
  return switch (error.type) {
    DioExceptionType.connectionTimeout => 'Connection timed out',
    DioExceptionType.sendTimeout => 'Send timed out',
    DioExceptionType.receiveTimeout => 'Receive timed out',
    DioExceptionType.connectionError => 'Connection unavailable',
    DioExceptionType.badCertificate => 'Bad TLS certificate',
    DioExceptionType.cancel => 'Request cancelled',
    DioExceptionType.badResponse => 'Backend rejected request',
    DioExceptionType.unknown => 'Network request failed',
  };
}

String _localMutationId(String prefix) {
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

bool _isMissingBackendSupabaseServiceKey(Response<dynamic> response) {
  final bodyText = response.data?.toString() ?? '';
  return response.statusCode != null &&
      response.statusCode! >= 500 &&
      bodyText.contains('SUPABASE_SERVICE_KEY') &&
      (bodyText.contains('ENVIRONMENT_CONFIGURATION_ERROR') ||
          bodyText.contains('missing_env_var'));
}

bool _routeLooksUnsupported(Response<dynamic>? response) {
  final statusCode = response?.statusCode;
  return statusCode == 404 || statusCode == 405;
}

Map<String, Object?> atlasOnboardingPayloadFromProfile(
  UserProfile profile, {
  required OnboardingAnswersDto answers,
  required AtlasOnboardingAccount account,
}) {
  final enums = BackendProfileEnums.fromOnboarding(profile, answers);
  final payload = <String, Object?>{
    'username': account.username,
    'email': account.email,
    'password': account.password,
    'age': answers.age ?? profile.age,
    'height_cm': answers.heightCm ?? profile.heightCm,
    'weight_kg': answers.weightKg ?? profile.weightKg,
    'activity_level': enums.activityLevel,
    'fitness_goal': enums.fitnessGoal,
    'experience_level': enums.experienceLevel,
    'available_time_min':
        answers.availableTimeMin ?? profile.availableTimeMinutes,
    'equipment_access': enums.equipmentAccess,
    'constraints_json': _atlasConstraints(answers),
  };
  final sex = _atlasSex(answers.sex?.wireValue ?? profile.sex);
  if (sex != null) {
    payload['sex'] = sex;
  }
  return payload;
}

Map<String, Object?> atlasProfilePatchPayload({
  required UserProfile previous,
  required UserProfile next,
}) {
  final payload = <String, Object?>{};
  final previousEnums = BackendProfileEnums.fromProfile(previous);
  final nextEnums = BackendProfileEnums.fromProfile(next);

  void putIfChanged(String key, Object? previousValue, Object? nextValue) {
    if (nextValue == null) {
      return;
    }
    if ('$previousValue' == '$nextValue') {
      return;
    }
    payload[key] = nextValue;
  }

  putIfChanged('age', previous.age, next.age);
  putIfChanged('height_cm', previous.heightCm, next.heightCm);
  putIfChanged('weight_kg', previous.weightKg, next.weightKg);
  putIfChanged(
    'activity_level',
    previousEnums.activityLevel,
    nextEnums.activityLevel,
  );
  putIfChanged(
    'fitness_goal',
    previousEnums.fitnessGoal,
    nextEnums.fitnessGoal,
  );
  putIfChanged(
    'experience_level',
    previousEnums.experienceLevel,
    nextEnums.experienceLevel,
  );
  putIfChanged(
    'available_time_min',
    previous.availableTimeMinutes,
    next.availableTimeMinutes,
  );
  putIfChanged(
    'equipment_access',
    previousEnums.equipmentAccess,
    nextEnums.equipmentAccess,
  );
  final nextSex = _atlasSex(next.sex);
  if (nextSex != null && _atlasSex(previous.sex) != nextSex) {
    payload['sex'] = nextSex;
  }
  return payload;
}

void _validateAtlasPayloadCanSync(Map<String, Object?> payload) {
  for (final key in const ['username', 'email', 'password']) {
    final value = payload[key]?.toString().trim();
    if (value == null || value.isEmpty) {
      throw const AtlasOnboardingCredentialException(
        'Your setup is saved on this device. Jim will sync it when the coaching service is available.',
      );
    }
  }
  final sex = payload['sex'];
  if (sex == null) {
    throw const AtlasProfileSyncException(
      'Atlas metrics need sex set to Male or Female. Keeping local estimates for now.',
    );
  }
}

String? _atlasSex(String value) {
  final normalized = _normalizeWire(value);
  if (normalized == 'male' || normalized == 'm') {
    return 'male';
  }
  if (normalized == 'female' || normalized == 'f') {
    return 'female';
  }
  return null;
}

class BackendProfileEnums {
  const BackendProfileEnums({
    required this.fitnessGoal,
    required this.activityLevel,
    required this.equipmentAccess,
    required this.experienceLevel,
  });

  final String fitnessGoal;
  final String activityLevel;
  final String equipmentAccess;
  final String experienceLevel;

  factory BackendProfileEnums.fromProfile(UserProfile profile) {
    return BackendProfileEnums.fromValues(
      goal: profile.goal,
      activityLevel: profile.activityLevel,
      equipmentAccess: profile.trainingPreference,
      experienceLevel: profile.userLevel.name,
    );
  }

  factory BackendProfileEnums.fromOnboarding(
    UserProfile profile,
    OnboardingAnswersDto answers,
  ) {
    return BackendProfileEnums.fromValues(
      goal: answers.fitnessGoal?.wireValue ?? profile.goal,
      activityLevel: answers.activityLevel?.wireValue ?? profile.activityLevel,
      equipmentAccess:
          answers.trainingPreference?.wireValue ?? profile.trainingPreference,
      experienceLevel:
          answers.experienceLevel?.wireValue ?? profile.userLevel.name,
    );
  }

  factory BackendProfileEnums.fromValues({
    required String goal,
    required String activityLevel,
    required String equipmentAccess,
    required String experienceLevel,
  }) {
    return BackendProfileEnums(
      fitnessGoal: _backendFitnessGoal(goal),
      activityLevel: _backendActivityLevel(activityLevel),
      equipmentAccess: _backendEquipmentAccess(equipmentAccess),
      experienceLevel: _backendExperienceLevel(experienceLevel),
    );
  }
}

String _backendActivityLevel(String value) {
  final normalized = _normalizeWire(value);
  if (normalized.contains('mostly_sitting') ||
      normalized.contains('sedentary') ||
      normalized.contains('mostly_sitting')) {
    return 'sedentary';
  }
  if (normalized.contains('light')) {
    return 'lightly_active';
  }
  if (normalized.contains('moderate')) {
    return 'moderately_active';
  }
  if (normalized.contains('very')) {
    return 'very_active';
  }
  return 'moderately_active';
}

String _backendFitnessGoal(String value) {
  final normalized = _normalizeWire(value);
  if (normalized.contains('recomp')) {
    return 'recomp';
  }
  if (normalized.contains('lose') ||
      normalized.contains('fat') ||
      normalized.contains('weight')) {
    return 'lose_fat';
  }
  if (normalized.contains('maintain') || normalized.contains('consistent')) {
    return 'maintain';
  }
  if (normalized.contains('muscle') || normalized.contains('build')) {
    return 'gain_muscle';
  }
  if (normalized.contains('strong') ||
      normalized.contains('fit') ||
      normalized.contains('athletic') ||
      normalized.contains('performance')) {
    return 'athletic_performance';
  }
  return 'maintain';
}

String _backendExperienceLevel(String value) {
  final normalized = _normalizeWire(value);
  if (normalized.contains('advanced_beginner') ||
      normalized.contains('inconsistent')) {
    return 'advanced_beginner';
  }
  if (normalized.contains('expert') ||
      normalized.contains('advanced') ||
      normalized.contains('established')) {
    return 'expert';
  }
  if (normalized.contains('intermediate') || normalized.contains('regular')) {
    return 'intermediate';
  }
  return 'novice';
}

String _backendEquipmentAccess(String value) {
  final normalized = _normalizeWire(value);
  if (normalized.contains('bodyweight')) {
    return 'bodyweight_only';
  }
  if (normalized.contains('dumbbell') ||
      normalized.contains('mixed') ||
      normalized.contains('flexible') ||
      normalized.contains('unsure')) {
    return 'dumbbells_bench';
  }
  if (normalized.contains('home')) {
    return 'home_gym';
  }
  if (normalized.contains('gym')) {
    return 'full_gym';
  }
  return 'bodyweight_only';
}

List<String> _atlasConstraints(OnboardingAnswersDto answers) {
  final constraints = <String>[];
  switch (answers.availableTimeMin) {
    case final minutes? when minutes <= 30:
      constraints.add('short_sessions');
  }
  switch (answers.trainingPreference) {
    case OnboardingTrainingPreference.home:
      constraints.add('home_equipment');
    case OnboardingTrainingPreference.bodyweight:
      constraints.add('bodyweight_only');
    case OnboardingTrainingPreference.unsure:
      constraints.add('needs_simple_start');
    case _:
      break;
  }
  switch (answers.dietaryPreference) {
    case OnboardingDietaryPreference.notNow:
      constraints.add('minimal_nutrition_tracking');
    case OnboardingDietaryPreference.simple:
      constraints.add('simple_meals');
    case _:
      break;
  }
  return constraints;
}

UserStaticMetrics _mapAtlasMetrics(dynamic raw) {
  final root = _asMap(_unwrapData(raw));
  final metrics =
      _asMap(root['metrics']).isNotEmpty ? _asMap(root['metrics']) : root;
  final macros = _asMap(metrics['macros']);
  final hydration = _asMap(metrics['hydration']);
  final targetCalories = _firstDouble(
    metrics,
    const ['target_calories', 'calorie_target', 'calories_target'],
    fallback: _firstDouble(metrics, const ['maintenance_calories', 'tdee']),
  );
  final tdee = _firstDouble(metrics, const ['tdee', 'total_daily_energy']);
  final maintenance = _firstDouble(
    metrics,
    const ['maintenance_calories', 'maintenance_kcal'],
    fallback: tdee,
  );
  return UserStaticMetrics(
    bmr: _firstDouble(metrics, const ['bmr', 'basal_metabolic_rate']),
    tdee: tdee,
    targetCalories: targetCalories,
    maintenanceCalories: maintenance,
    cutCalories: _firstDouble(
      metrics,
      const ['cut_calories', 'deficit_calories'],
      fallback: targetCalories,
    ),
    bulkCalories: _firstDouble(
      metrics,
      const ['bulk_calories', 'surplus_calories'],
      fallback: targetCalories,
    ),
    proteinG: _firstDouble(
      metrics,
      const ['protein_g', 'protein_target', 'protein'],
      fallback: _firstDouble(macros, const ['protein_g', 'protein']),
    ),
    carbsG: _firstDouble(
      metrics,
      const ['carbs_g', 'carbs_target', 'carbs'],
      fallback: _firstDouble(macros, const ['carbs_g', 'carbs']),
    ),
    fatG: _firstDouble(
      metrics,
      const ['fat_g', 'fat_target', 'fat'],
      fallback: _firstDouble(macros, const ['fat_g', 'fat']),
    ),
    hydrationL: _firstDouble(
      metrics,
      const ['hydration_l', 'hydration_target_l', 'hydration_target'],
      fallback: _firstDouble(hydration, const ['liters', 'target_liters']),
    ),
    cutIntensity: metrics['assumption_summary']?.toString() ??
        metrics['summary']?.toString() ??
        'Atlas metrics',
  );
}

bool _metricsAreUsable(UserStaticMetrics metrics) {
  return metrics.bmr > 0 ||
      metrics.tdee > 0 ||
      metrics.targetCalories > 0 ||
      metrics.proteinG > 0 ||
      metrics.hydrationL > 0;
}

UserStaticMetrics _localMetricsForProfile(UserProfile profile) {
  final estimate = NutritionTargetCalculator.estimate(profile);
  return estimate.hasRequiredProfile
      ? estimate.toMetrics()
      : const UserStaticMetrics(
          bmr: 0,
          tdee: 0,
          targetCalories: 0,
          maintenanceCalories: 0,
          cutCalories: 0,
          bulkCalories: 0,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          hydrationL: 0,
          cutIntensity: '',
        );
}

double _firstDouble(
  Map<String, dynamic> map,
  List<String> keys, {
  double fallback = 0,
}) {
  for (final key in keys) {
    final parsed = _toDouble(map[key], double.nan);
    if (parsed.isFinite) {
      return parsed;
    }
  }
  return fallback;
}

String _normalizeWire(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
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
  final message = _buildAuthDiagnosticMessage(
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
    },
  );
  if (statusCode == 401) {
    throw AuthSessionExpiredException(message);
  }
  throw Exception(message);
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

String? _programGenerationMessage(dynamic raw) {
  if (raw == null) {
    return null;
  }
  if (raw is String) {
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }
  final unwrapped = _unwrapData(raw);
  if (unwrapped is String) {
    final value = unwrapped.trim();
    return value.isEmpty ? null : value;
  }
  final map = _asMap(unwrapped).isEmpty ? _asMap(raw) : _asMap(unwrapped);
  final message =
      (map['message'] ?? map['status'] ?? map['result'])?.toString().trim();
  return message == null || message.isEmpty ? null : message;
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
          final loc = entry['loc'];
          final msg = entry['msg']?.toString();
          final type = entry['type']?.toString();
          if (entry.isNotEmpty && msg != null) {
            final locText = loc is List ? loc.join('.') : loc?.toString();
            return [
              if (locText != null && locText.isNotEmpty) 'loc=$locText',
              'msg=$msg',
              if (type != null && type.isNotEmpty) 'type=$type',
            ].join(' ');
          }
          return item.toString();
        })
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (parts.isNotEmpty) {
      return parts.join('\n');
    }
  }
  return null;
}

Map<String, Object?> workoutTemplateRichPayload(
  WorkoutTemplateDraft template,
  List<WorkoutExerciseDraft> exercises,
) {
  return ApiRequestDto(
    name: 'workout_template_rich',
    requiredFields: const ['name', 'exercises'],
    payload: {
      'name': template.name,
      'description': template.description.isEmpty ? null : template.description,
      'exercises': exercises.asMap().entries.map((entry) {
        final exercise = entry.value;
        return {
          'exercise_id': exercise.exerciseId,
          'order_index': entry.key + 1,
          'notes': exercise.notes.isEmpty ? null : exercise.notes,
        };
      }).toList(),
    },
  ).toJson();
}

Map<String, Object?> workoutTemplateDocumentedPayload(
  WorkoutTemplateDraft template,
  List<WorkoutExerciseDraft> exercises,
) {
  return ApiRequestDto(
    name: 'workout_template_documented',
    requiredFields: const ['name', 'exercises'],
    payload: {
      'name': template.name,
      'description': template.description.isEmpty ? null : template.description,
      'exercises': exercises.asMap().entries.map((entry) {
        final exercise = entry.value;
        return {
          'exercise_id': exercise.exerciseId,
          'order_index': entry.key + 1,
          'notes': exercise.notes.isEmpty ? null : exercise.notes,
        };
      }).toList(),
    },
  ).toJson();
}

Map<String, Object?> workoutLogRichPayload(
  WorkoutLogDraft log,
  List<WorkoutExerciseDraft> exercises,
) {
  final workoutExercises = exercises.asMap().entries.map((entry) {
    final exercise = entry.value;
    if (exercise.sets.isEmpty) {
      throw Exception(
        'workout_log payload exercise ${entry.key + 1} has no sets.',
      );
    }
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
          'rpe': setDraft.rpe,
        };
      }).toList(),
    };
  }).toList();
  return ApiRequestDto(
    name: 'workout_log_rich',
    requiredFields: const ['name', 'exercises'],
    payload: {
      'name': log.name,
      'template_id': log.templateId,
      'notes': log.notes.isEmpty ? null : log.notes,
      'exercises': workoutExercises,
    },
  ).toJson();
}

Map<String, Object?> workoutLogDocumentedPayload(
  WorkoutLogDraft log,
  List<WorkoutExerciseDraft> exercises,
) {
  return ApiRequestDto(
    name: 'workout_log_documented',
    requiredFields: const ['name', 'exercises'],
    payload: {
      'name': log.name,
      'template_id': log.templateId,
      'notes': log.notes.isEmpty ? null : log.notes,
      'exercises': exercises.asMap().entries.map((entry) {
        final exercise = entry.value;
        return {
          'exercise_id': exercise.exerciseId,
          'order_index': entry.key + 1,
          'sets': exercise.sets.map((setDraft) {
            return {
              'set_number': setDraft.setNumber,
              'reps': setDraft.reps,
              'weight_kg': setDraft.weightKg,
              'is_warmup': setDraft.isWarmup,
              'rpe': setDraft.rpe,
            };
          }).toList(),
        };
      }).toList(),
    },
  ).toJson();
}

Map<String, Object?> workoutLogMetadataPatchPayload(WorkoutLogDraft log) => {
      'name': log.name,
      'notes': log.notes.isEmpty ? null : log.notes,
    };

class ApiRequestDto {
  const ApiRequestDto({
    required this.name,
    required this.payload,
    this.requiredFields = const [],
  });

  final String name;
  final Map<String, Object?> payload;
  final List<String> requiredFields;

  Map<String, Object?> toJson() {
    final missing = requiredFields.where((field) {
      final value = payload[field];
      if (value == null) {
        return true;
      }
      if (value is String) {
        return value.trim().isEmpty;
      }
      if (value is Iterable) {
        return value.isEmpty;
      }
      return false;
    }).toList(growable: false);
    if (missing.isNotEmpty) {
      throw Exception('$name payload is missing: ${missing.join(', ')}.');
    }
    return payload;
  }
}

Map<String, Object?> profileBackendPayload(UserProfile profile) {
  final enums = BackendProfileEnums.fromProfile(profile);
  return ApiRequestDto(
    name: 'profile',
    requiredFields: const ['username'],
    payload: {
      'username': profile.name,
      'age': profile.age,
      'sex': profile.sex,
      'height_cm': profile.heightCm,
      'weight_kg': profile.weightKg,
      'fitness_goal': enums.fitnessGoal,
      'activity_level': enums.activityLevel,
      'experience_level': enums.experienceLevel,
      'dietary_preference': profile.dietaryPreference,
      'available_time_min': profile.availableTimeMinutes,
      'equipment_access': enums.equipmentAccess,
      'coaching_preference': profile.coachingPreference,
      'goal_timeframe': profile.goalTimeframe,
      'prefers_voice_logging': profile.prefersVoiceLogging,
    },
  ).toJson();
}

String _profileGoalLabel(Object? raw) {
  return switch (_normalizeWire(raw?.toString() ?? '')) {
    'lose_fat' || 'lose_weight' => 'Lose fat',
    'gain_muscle' || 'build_muscle' => 'Build muscle',
    'athletic_performance' || 'get_stronger' => 'Get stronger',
    'maintain' || 'stay_consistent' => 'Stay consistent',
    'recomp' => 'Recomp',
    _ => raw?.toString() ?? '',
  };
}

String _profileActivityLabel(Object? raw) {
  return switch (_normalizeWire(raw?.toString() ?? '')) {
    'sedentary' || 'mostly_sitting' => 'Mostly sitting',
    'lightly_active' => 'Lightly active',
    'moderately_active' || 'changes_a_lot' => 'Moderately active',
    'very_active' => 'Very active',
    _ => raw?.toString() ?? '',
  };
}

String _profileEquipmentLabel(Object? raw) {
  return switch (_normalizeWire(raw?.toString() ?? '')) {
    'full_gym' || 'gym' => 'Gym workouts',
    'home_gym' || 'home' => 'Home workouts',
    'dumbbells_bench' || 'mixed' => 'A flexible mix',
    'bodyweight_only' || 'bodyweight' => 'Bodyweight',
    _ => raw?.toString() ?? '',
  };
}

Map<String, dynamic> workoutLogDraftToJson(WorkoutLogDraft log) {
  return {
    'workout_log_id': log.workoutLogId,
    'template_id': log.templateId,
    'name': log.name,
    'notes': log.notes,
    'started_at_label': log.startedAtLabel,
    'ended_at_label': log.endedAtLabel,
    'exercises': log.exercises.map(workoutExerciseDraftToJson).toList(),
  };
}

WorkoutLogDraft workoutLogDraftFromJson(dynamic raw) {
  final map = _asMap(raw);
  final exercises = map['exercises'];
  return WorkoutLogDraft(
    workoutLogId: _toNullableInt(map['workout_log_id']),
    templateId: _toNullableInt(map['template_id']),
    name: map['name']?.toString() ?? 'Workout Session',
    notes: map['notes']?.toString() ?? '',
    startedAtLabel: map['started_at_label']?.toString() ?? '',
    endedAtLabel: map['ended_at_label']?.toString() ?? '',
    exercises: exercises is List
        ? exercises.map(workoutExerciseDraftFromJson).toList(growable: false)
        : const [],
  );
}

Map<String, dynamic> workoutExerciseDraftToJson(WorkoutExerciseDraft exercise) {
  return {
    'exercise_id': exercise.exerciseId,
    'exercise_name': exercise.exerciseName,
    'notes': exercise.notes,
    'target_sets': exercise.targetSets,
    'target_reps': exercise.targetReps,
    'sets': exercise.sets.map(setDraftToJson).toList(),
  };
}

WorkoutExerciseDraft workoutExerciseDraftFromJson(dynamic raw) {
  final map = _asMap(raw);
  final rawSets = map['sets'];
  return WorkoutExerciseDraft(
    exerciseId: _toNullableInt(map['exercise_id']),
    exerciseName: map['exercise_name']?.toString() ?? '',
    notes: map['notes']?.toString() ?? '',
    targetSets: _toNonNegativeInt(map['target_sets'], 0, max: 100),
    targetReps: _toNonNegativeInt(map['target_reps'], 0, max: 1000),
    sets: rawSets is List
        ? rawSets.map(setDraftFromJson).toList(growable: false)
        : const [],
  );
}

Map<String, dynamic> setDraftToJson(SetDraft setDraft) {
  return {
    'set_number': setDraft.setNumber,
    'weight_kg': setDraft.weightKg,
    'reps': setDraft.reps,
    'is_warmup': setDraft.isWarmup,
    'is_completed': setDraft.isCompleted,
    'rpe': setDraft.rpe,
  };
}

SetDraft setDraftFromJson(dynamic raw) {
  final map = _asMap(raw);
  return SetDraft(
    setNumber: _toNonNegativeInt(map['set_number'], 1, max: 1000),
    weightKg: _toNutritionDouble(map['weight_kg'], 0, max: 10000),
    reps: _toNonNegativeInt(map['reps'], 0, max: 1000),
    isWarmup: map['is_warmup'] == true,
    isCompleted: map['is_completed'] == true,
    rpe: _toNutritionDouble(map['rpe'], 0, max: 10),
  );
}

Map<String, dynamic> foodLogDraftToJson(FoodLogDraft log) {
  return {
    'food_log_id': log.foodLogId,
    'food_id': log.foodId,
    'date': log.logDate?.toIso8601String(),
    'quantity_source': _quantitySourceWire(log.quantitySource),
    'calories_per_100g': log.caloriesPer100g,
    'protein_per_100g': log.proteinPer100g,
    'carbs_per_100g': log.carbsPer100g,
    'fat_per_100g': log.fatPer100g,
    'food_name': log.foodName,
    'quantity_grams': log.quantityGrams,
    'meal_type': _mealTypeWire(log.mealType),
    'calories': log.calories,
    'protein': log.protein,
    'carbs': log.carbs,
    'fat': log.fat,
  };
}

FoodLogDraft foodLogDraftFromJson(dynamic raw) {
  final map = _asMap(raw);
  return FoodLogDraft(
    foodLogId: map['food_log_id']?.toString(),
    foodId: map['food_id']?.toString(),
    logDate: DateTime.tryParse(
      (map['date'] ?? map['log_date'])?.toString() ?? '',
    ),
    quantitySource: _parseQuantitySource(map['quantity_source']?.toString()),
    caloriesPer100g: _nullableNutritionDouble(map['calories_per_100g']),
    proteinPer100g: _nullableNutritionDouble(map['protein_per_100g']),
    carbsPer100g: _nullableNutritionDouble(map['carbs_per_100g']),
    fatPer100g: _nullableNutritionDouble(map['fat_per_100g']),
    foodName: map['food_name']?.toString() ?? '',
    quantityGrams: _toNutritionDouble(
      map['quantity_grams'] ?? map['quantity_g'],
      100,
      max: 50000,
    ),
    mealType: _parseMealType(map['meal_type']?.toString()),
    calories: _toNutritionDouble(map['calories'], 0, max: 20000),
    protein: _toNutritionDouble(map['protein'], 0, max: 1000),
    carbs: _toNutritionDouble(map['carbs'], 0, max: 2000),
    fat: _toNutritionDouble(map['fat'], 0, max: 1000),
  );
}

FoodSuggestion foodSuggestionFromBackend(Map<String, dynamic> map) {
  return FoodSuggestion(
    foodId: map['food_id']?.toString(),
    name: map['name']?.toString() ?? '',
    caloriesPer100g: _toNutritionDouble(
      map['calories_per_100g'] ?? map['calories'],
      0,
      max: 2000,
    ),
    proteinPer100g: _toNutritionDouble(
      map['protein_per_100g'] ?? map['protein_g'],
      0,
      max: 200,
    ),
    carbsPer100g: _toNutritionDouble(
      map['carbs_per_100g'] ?? map['carbs_g'],
      0,
      max: 200,
    ),
    fatPer100g: _toNutritionDouble(
      map['fat_per_100g'] ?? map['fat_g'],
      0,
      max: 200,
    ),
    source: map['source']?.toString() ?? 'Food catalog',
  );
}

Map<String, Object?> customFoodBackendPayload(
  FoodLogDraft log, {
  required double factor,
}) {
  return ApiRequestDto(
    name: 'custom_food',
    requiredFields: const ['name'],
    payload: {
      'name': log.foodName,
      'calories_per_100g': _roundNutrition(log.calories * factor),
      'protein_per_100g': _roundNutrition(log.protein * factor),
      'carbs_per_100g': _roundNutrition(log.carbs * factor),
      'fat_per_100g': _roundNutrition(log.fat * factor),
      'source': 'JimBro manual',
    },
  ).toJson();
}

Map<String, Object?> foodLogBackendPayload(
  FoodLogDraft log, {
  required String foodId,
  required String date,
}) {
  return ApiRequestDto(
    name: 'food_log',
    requiredFields: const [
      'food_id',
      'quantity_grams',
      'meal_type',
      'date',
    ],
    payload: {
      'food_id': foodId,
      'quantity_grams': log.quantityGrams,
      'meal_type': _mealTypeWire(log.mealType),
      'date': date,
    },
  ).toJson();
}

DailyNutritionSummary dailyNutritionSummaryFromBackend(
  Map<String, dynamic> data,
) {
  return DailyNutritionSummary(
    targetCalories: _toNutritionDouble(
      data['target_calories'] ?? data['calorie_target'],
      0,
      max: 20000,
    ),
    consumedCalories: _toNutritionDouble(
      data['total_calories'] ?? data['consumed_calories'] ?? data['calories'],
      0,
      max: 20000,
    ),
    proteinTarget: _toNutritionDouble(
      data['protein_target'] ?? data['target_protein'],
      0,
      max: 1000,
    ),
    proteinConsumed: _toNutritionDouble(
      data['total_protein'] ?? data['protein_consumed'] ?? data['protein_g'],
      0,
      max: 1000,
    ),
    carbsTarget: _toNutritionDouble(
      data['carbs_target'] ?? data['target_carbs'],
      0,
      max: 2000,
    ),
    carbsConsumed: _toNutritionDouble(
      data['total_carbs'] ?? data['carbs_consumed'] ?? data['carbs_g'],
      0,
      max: 2000,
    ),
    fatTarget: _toNutritionDouble(
      data['fat_target'] ?? data['target_fat'],
      0,
      max: 1000,
    ),
    fatConsumed: _toNutritionDouble(
      data['total_fat'] ?? data['fat_consumed'] ?? data['fat_g'],
      0,
      max: 1000,
    ),
    hydrationTargetLiters: _toNutritionDouble(
      data['hydration_target'] ?? data['hydration_target_l'],
      0,
      max: 20,
    ),
    hydrationConsumedLiters: _toNutritionDouble(
      data['hydration_consumed'] ?? data['hydration_consumed_l'],
      0,
      max: 20,
    ),
  );
}

AgentContextSnapshot agentContextFromBackend(dynamic raw) {
  final root = _asMap(_unwrapData(raw));
  final profileData = _asMap(root['user_profile'] ?? root['profile']);
  final metricsData =
      root['atlas_metrics'] ?? root['static_metrics'] ?? root['metrics'];
  final templateData = root['active_template'] ?? root['workout_template'];
  final recentData = root['recent_workouts'] ?? root['workout_logs'];
  final trendsData = root['workout_trends'] ?? root['trends'];
  final nutritionData =
      root['todays_nutrition'] ?? root['today_nutrition'] ?? root['nutrition'];

  return AgentContextSnapshot(
    userProfile:
        profileData.isEmpty ? null : _mapContextUserProfile(profileData),
    atlasMetrics: metricsData == null ? null : _mapAtlasMetrics(metricsData),
    activeTemplate:
        templateData == null ? null : _mapWorkoutTemplate(templateData),
    recentWorkouts: _mapWorkoutLogList(recentData),
    workoutTrends: _mapWorkoutTrends(trendsData),
    todaysNutrition:
        nutritionData == null ? null : _mapContextNutrition(nutritionData),
  );
}

UserProfile _mapContextUserProfile(Map<String, dynamic> data) {
  return UserProfile(
    name: data['username']?.toString() ?? data['name']?.toString() ?? '',
    goal: data['goal']?.toString() ?? data['fitness_goal']?.toString() ?? '',
    coachingPreference: data['coaching_preference']?.toString() ?? '',
    userLevel: _parseUserLevel(
      (data['user_level'] ?? data['experience_level'])?.toString(),
    ),
    age: _toInt(data['age'], 0),
    heightCm: _toDouble(data['height_cm'], 0),
    weightKg: _toDouble(data['weight_kg'], 0),
    sex: data['sex']?.toString() ?? '',
    availableTimeMinutes: _toInt(
      data['available_time_min'] ?? data['available_time_minutes'],
      0,
    ),
    trainingPreference: data['training_preference']?.toString() ?? '',
    activityLevel: data['activity_level']?.toString() ?? '',
    dietaryPreference: data['dietary_preference']?.toString() ?? '',
    goalTimeframe: data['goal_timeframe']?.toString() ?? '',
    weeksActive: _toInt(data['weeks_active'], 0),
    prefersVoiceLogging: data['prefers_voice_logging'] == true,
  );
}

DailyNutritionSummary _mapContextNutrition(dynamic raw) {
  final root = _asMap(_unwrapData(raw));
  final summary = _asMap(root['summary']);
  final totals = _asMap(root['totals']);
  return dailyNutritionSummaryFromBackend({
    ...root,
    ...summary,
    ...totals,
  });
}

WorkoutTrendSummary _mapWorkoutTrends(dynamic raw) {
  final unwrapped = _unwrapData(raw);
  final root = _asMap(unwrapped);
  final rawPoints = unwrapped is List
      ? unwrapped
      : root['points'] ?? root['series'] ?? root['daily'] ?? root['data'];
  final points = rawPoints is List
      ? rawPoints.map((item) {
          final point = _asMap(item);
          return WorkoutTrendPoint(
            label: (point['date'] ?? point['label'] ?? point['period'])
                    ?.toString() ??
                '',
            volumeKg: _firstDouble(
              point,
              const ['volume_kg', 'total_volume_kg', 'volume'],
            ),
            workoutCount: _toInt(
              point['workout_count'] ?? point['count'] ?? point['workouts'],
              0,
            ),
          );
        }).toList(growable: false)
      : const <WorkoutTrendPoint>[];
  return WorkoutTrendSummary(
    rollingDays: _toInt(root['rolling_days'] ?? root['window_days'], 28),
    workoutCount: _toInt(
      root['workout_count'] ?? root['total_workouts'] ?? root['count'],
      points.fold<int>(0, (total, point) => total + point.workoutCount),
    ),
    totalVolumeKg: _firstDouble(
      root,
      const ['total_volume_kg', 'volume_kg', 'total_volume'],
      fallback:
          points.fold<double>(0, (total, point) => total + point.volumeKg),
    ),
    completedSets: _toInt(
      root['completed_sets'] ?? root['total_sets'] ?? root['set_count'],
      0,
    ),
    points: points,
  );
}

List<WorkoutLogDraft> _mapWorkoutLogList(dynamic raw) {
  final unwrapped = _unwrapData(raw);
  final map = _asMap(unwrapped);
  final list = unwrapped is List
      ? unwrapped
      : map['items'] ?? map['logs'] ?? map['recent_workouts'];
  if (list is! List) {
    return const [];
  }
  return list.map(_mapWorkoutLog).toList(growable: false);
}

WorkoutTemplateDraft? _mapActiveTemplate(dynamic raw) {
  final unwrapped = _unwrapData(raw);
  if (unwrapped is List) {
    if (unwrapped.isEmpty) {
      return null;
    }
    return _pickMostRecentTemplate(
      unwrapped.map(_mapWorkoutTemplate).toList(growable: false),
    );
  }
  final map = _asMap(unwrapped);
  return map.isEmpty ? null : _mapWorkoutTemplate(map);
}

DailyNutritionSummary nutritionSummaryFromFoodLogs(
  List<FoodLogDraft> logs, {
  DailyNutritionSummary base = DailyNutritionSummary.empty,
}) {
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
  return base.copyWith(
    consumedCalories: calories,
    proteinConsumed: protein,
    carbsConsumed: carbs,
    fatConsumed: fat,
  );
}

List<FoodLogDraft> foodLogsFromBackendSummary(Map<String, dynamic> data) {
  final rawMeals = data['meals'] ?? data['grouped_meals'] ?? data['entries'];
  if (rawMeals is List) {
    return rawMeals.expand<FoodLogDraft>((item) {
      final meal = _asMap(item);
      final mealType = meal['meal_type']?.toString();
      final entries = meal['entries'] ?? meal['foods'] ?? meal['logs'];
      if (entries is! List) {
        return const <FoodLogDraft>[];
      }
      return entries.map((entry) {
        final map = _asMap(entry);
        return _mapFoodLog({
          ...map,
          if (mealType != null && map['meal_type'] == null)
            'meal_type': mealType,
        });
      });
    }).toList();
  }
  if (rawMeals is Map) {
    final logs = <FoodLogDraft>[];
    for (final entry in rawMeals.entries) {
      final items = entry.value;
      if (items is! List) {
        continue;
      }
      for (final item in items) {
        final map = _asMap(item);
        logs.add(
          _mapFoodLog({
            ...map,
            if (map['meal_type'] == null) 'meal_type': entry.key.toString(),
          }),
        );
      }
    }
    return logs;
  }
  return const [];
}

double _roundNutrition(double value) {
  return double.parse(value.toStringAsFixed(2));
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
    'novice' || 'advanced_beginner' || 'beginner' => UserLevel.beginner,
    'expert' || 'advanced' => UserLevel.advanced,
    _ => UserLevel.intermediate,
  };
}

MealType _parseMealType(String? raw) {
  return switch (raw) {
    'breakfast' => MealType.breakfast,
    'lunch' => MealType.lunch,
    'dinner' => MealType.dinner,
    'pre_workout' => MealType.preWorkout,
    'post_workout' => MealType.postWorkout,
    _ => MealType.snack,
  };
}

String _mealTypeWire(MealType mealType) {
  return switch (mealType) {
    MealType.breakfast => 'breakfast',
    MealType.lunch => 'lunch',
    MealType.dinner => 'dinner',
    MealType.snack => 'snack',
    MealType.preWorkout => 'pre_workout',
    MealType.postWorkout => 'post_workout',
  };
}

QuantitySource _parseQuantitySource(String? raw) {
  return switch (raw) {
    'explicit' => QuantitySource.explicit,
    'inferred' => QuantitySource.inferred,
    _ => QuantitySource.default100g,
  };
}

String _quantitySourceWire(QuantitySource source) {
  return switch (source) {
    QuantitySource.explicit => 'explicit',
    QuantitySource.default100g => 'default_100g',
    QuantitySource.inferred => 'inferred',
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

double? _nullableNutritionDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  final parsed = _toDouble(value, double.nan);
  return parsed.isFinite ? parsed : null;
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

WorkoutTemplateDraft _pickMostRecentTemplate(
  List<WorkoutTemplateDraft> templates,
) {
  return templates.reduce((current, candidate) {
    final currentId = current.templateId ?? 0;
    final candidateId = candidate.templateId ?? 0;
    return candidateId >= currentId ? candidate : current;
  });
}

WorkoutTemplateDraft _mapWorkoutTemplate(dynamic raw) {
  final template = _asMap(raw);
  final rawExercises = template['template_exercises'] ??
      template['exercises'] ??
      _exercisesFromTemplateDays(template['days']);
  return WorkoutTemplateDraft(
    templateId: _toNullableInt(template['template_id']),
    name: template['name']?.toString() ?? '',
    description: template['description']?.toString() ?? '',
    durationMinutes: _toInt(template['duration_minutes'], 0),
    goal: template['goal']?.toString() ?? '',
    exercises: _mapTemplateExercises(rawExercises),
  );
}

List<dynamic> _exercisesFromTemplateDays(dynamic raw) {
  if (raw is! List || raw.isEmpty) {
    return const [];
  }
  final exercises = <dynamic>[];
  for (final item in raw) {
    final day = _asMap(item);
    final dayExercises = day['exercises'];
    if (dayExercises is List) {
      exercises.addAll(dayExercises);
    }
  }
  return exercises;
}

WorkoutScheduleEntry _mapWorkoutScheduleEntry(dynamic raw) {
  final map = _asMap(raw);
  return WorkoutScheduleEntry.fromJson(map);
}

Map<String, Object?> _workoutSchedulePayload(
  AuthSession session,
  WorkoutScheduleEntry entry,
) {
  return {
    'template_id': entry.templateId,
    'user_id': session.userId,
    'weekday': entry.weekday,
    'time': entry.timeLabel,
    'repeat_weekly': entry.repeatWeekly,
    'active': entry.active,
  };
}

WorkoutLogDraft _mapWorkoutLog(dynamic raw) {
  final log = _asMap(raw);
  final startedAt = log['started_at']?.toString() ?? '';
  final endedAt = log['ended_at']?.toString() ?? '';
  final date = log['date']?.toString() ?? '';
  return WorkoutLogDraft(
    workoutLogId: _toNullableInt(log['workout_log_id']),
    templateId: _toNullableInt(log['template_id']),
    name: log['name']?.toString() ?? log['workout_name']?.toString() ?? '',
    notes: log['notes']?.toString() ?? '',
    startedAtLabel: startedAt.isEmpty ? date : startedAt,
    endedAtLabel: endedAt.isEmpty ? '' : endedAt,
    exercises: _mapLoggedExercises(
      log['workout_exercises'] ?? log['exercises'],
    ),
  );
}

FoodLogDraft _mapFoodLog(dynamic raw) {
  final map = _asMap(raw);
  final food = _asMap(map['food']);
  final quantity = _toNutritionDouble(
    map['quantity_g'] ?? map['quantity_grams'],
    0,
    max: 50000,
  );
  final calories = _toNutritionDouble(
    map['calories_snapshot'] ?? map['calories'] ?? map['total_calories'],
    0,
    max: 20000,
  );
  final protein = _toNutritionDouble(
    map['protein_snapshot'] ?? map['protein'] ?? map['protein_g'],
    0,
    max: 1000,
  );
  final carbs = _toNutritionDouble(
    map['carbs_snapshot'] ?? map['carbs'] ?? map['carbs_g'],
    0,
    max: 2000,
  );
  final fat = _toNutritionDouble(
    map['fat_snapshot'] ?? map['fat'] ?? map['fat_g'],
    0,
    max: 1000,
  );
  final multiplier = quantity <= 0 ? 0 : 100 / quantity;
  return FoodLogDraft(
    foodLogId: (map['food_log_id'] ?? map['id'])?.toString(),
    foodId: (map['food_id'] ?? food['food_id'] ?? food['id'])?.toString(),
    logDate: DateTime.tryParse(
      (map['log_date'] ?? map['date'])?.toString() ?? '',
    ),
    quantitySource: _parseQuantitySource(map['quantity_source']?.toString()),
    foodName: map['food_name']?.toString() ??
        map['name']?.toString() ??
        food['name']?.toString() ??
        '',
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
    for (final item in data) {
      final map = _asMap(item);
      final foodId = map['food_id']?.toString();
      final foodName = map['name']?.toString() ?? '';
      if (foodId != null &&
          foodId.isNotEmpty &&
          foodName.toLowerCase() == name.toLowerCase()) {
        return foodId;
      }
    }
    return null;
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
    final rawSets = map['sets'] ?? map['planned_sets'];
    final documentedSetCount =
        rawSets is List ? 0 : _toNonNegativeInt(rawSets, 0, max: 100);
    final documentedReps = _toNonNegativeInt(
      map['reps'] ?? map['target_reps'],
      0,
      max: 1000,
    );
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
              isCompleted: setMap['is_completed'] == true,
              rpe: _toNutritionDouble(setMap['rpe'], 0, max: 10),
            );
          }).toList()
        : documentedSetCount > 0 || documentedReps > 0
            ? [
                SetDraft(
                  setNumber: 1,
                  weightKg: 0,
                  reps: documentedReps,
                  isWarmup: false,
                  isCompleted: false,
                  rpe: 0,
                ),
              ]
            : const <SetDraft>[];
    final targetSets = _toNonNegativeInt(
      map['target_sets'],
      documentedSetCount > 0
          ? documentedSetCount
          : sets.isEmpty
              ? 3
              : sets.length,
      max: 100,
    );
    final targetReps = _toNonNegativeInt(
      map['target_reps'],
      documentedReps > 0
          ? documentedReps
          : sets.isEmpty
              ? 10
              : sets.first.reps,
      max: 1000,
    );
    return WorkoutExerciseDraft(
      exerciseId: _toNullableInt(map['exercise_id']),
      exerciseName:
          map['exercise_name']?.toString() ?? map['name']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      targetSets: targetSets,
      targetReps: targetReps,
      sets: sets,
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

List<WorkoutScheduleEntry> _upsertLocalWorkoutSchedule(
  List<WorkoutScheduleEntry> schedule,
  WorkoutScheduleEntry saved,
) {
  final existingIndex = schedule.indexWhere(
    (entry) =>
        entry.scheduleId == saved.scheduleId || entry.weekday == saved.weekday,
  );
  if (existingIndex == -1) {
    return [...schedule, saved]..sort(_compareWorkoutScheduleEntries);
  }
  final updated = [...schedule];
  updated[existingIndex] = saved;
  return updated..sort(_compareWorkoutScheduleEntries);
}

int _compareWorkoutScheduleEntries(
  WorkoutScheduleEntry left,
  WorkoutScheduleEntry right,
) {
  return left.weekday.compareTo(right.weekday);
}

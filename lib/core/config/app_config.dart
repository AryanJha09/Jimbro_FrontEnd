import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum BackendMode {
  mock,
  fastApi,
}

enum AuthMode {
  fastApi,
  supabase,
}

enum AppConfigValidationSeverity {
  warning,
  error,
}

class AppConfigValidationIssue {
  const AppConfigValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.variableName,
  });

  final AppConfigValidationSeverity severity;
  final String code;
  final String message;
  final String? variableName;
}

class AppConfig {
  const AppConfig({
    required this.backendMode,
    required this.authMode,
    required this.fastApiBaseUrl,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.supabaseRedirectScheme,
    required this.supabaseRedirectHost,
  });

  final BackendMode backendMode;
  final AuthMode authMode;
  final String fastApiBaseUrl;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String supabaseRedirectScheme;
  final String supabaseRedirectHost;

  bool get useLiveBackend => backendMode == BackendMode.fastApi;

  bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  bool get useSupabaseDirectAuth =>
      authMode == AuthMode.supabase && isSupabaseConfigured;

  String get normalizedFastApiBaseUrl => _normalizeBaseUrl(fastApiBaseUrl);

  List<AppConfigValidationIssue> validate({
    Set<String>? presentVariableNames,
    bool isReleaseBuild = kReleaseMode,
  }) {
    final names = presentVariableNames;
    final issues = <AppConfigValidationIssue>[];
    final serverOnlyNames =
        names?.where(_looksServerOnlyVariableName).toList(growable: false) ??
            const <String>[];

    for (final name in serverOnlyNames) {
      issues.add(
        AppConfigValidationIssue(
          severity: AppConfigValidationSeverity.warning,
          code: 'server_only_env_name',
          variableName: name,
          message:
              '$name looks server-only. Flutter .env is bundled as an asset; keep only public/client-safe values there.',
        ),
      );
    }

    if (backendMode == BackendMode.mock) {
      return issues;
    }

    void requireName(String name, String description) {
      final isPresent = names == null || names.contains(name);
      final value = switch (name) {
        'FASTAPI_BASE_URL' => fastApiBaseUrl,
        'SUPABASE_URL' => supabaseUrl,
        'SUPABASE_ANON_KEY' => supabaseAnonKey,
        _ => 'present',
      };
      if (!isPresent || value.trim().isEmpty) {
        issues.add(
          AppConfigValidationIssue(
            severity: AppConfigValidationSeverity.error,
            code: 'missing_required_env',
            variableName: name,
            message: '$name is required for $description.',
          ),
        );
      }
    }

    requireName('FASTAPI_BASE_URL', 'FastAPI backend mode');
    final parsedFastApiUrl = Uri.tryParse(fastApiBaseUrl.trim());
    if (fastApiBaseUrl.isNotEmpty &&
        (parsedFastApiUrl == null ||
            !parsedFastApiUrl.hasScheme ||
            !parsedFastApiUrl.hasAuthority ||
            (parsedFastApiUrl.scheme != 'http' &&
                parsedFastApiUrl.scheme != 'https'))) {
      issues.add(
        const AppConfigValidationIssue(
          severity: AppConfigValidationSeverity.error,
          code: 'fastapi_base_url_invalid',
          variableName: 'FASTAPI_BASE_URL',
          message: 'FASTAPI_BASE_URL must be an absolute http or https URL.',
        ),
      );
    }
    if (fastApiBaseUrl.isNotEmpty && !_baseUrlIncludesApiV1(fastApiBaseUrl)) {
      issues.add(
        const AppConfigValidationIssue(
          severity: AppConfigValidationSeverity.error,
          code: 'fastapi_base_url_missing_api_v1',
          variableName: 'FASTAPI_BASE_URL',
          message: 'FASTAPI_BASE_URL must include /api/v1.',
        ),
      );
    }
    if (fastApiBaseUrl.isNotEmpty && _apiV1SegmentCount(fastApiBaseUrl) > 1) {
      issues.add(
        const AppConfigValidationIssue(
          severity: AppConfigValidationSeverity.error,
          code: 'fastapi_base_url_duplicate_api_v1',
          variableName: 'FASTAPI_BASE_URL',
          message: 'FASTAPI_BASE_URL must include /api/v1 exactly once.',
        ),
      );
    }
    if (parsedFastApiUrl != null &&
        _isLoopbackHost(parsedFastApiUrl.host) &&
        isReleaseBuild) {
      issues.add(
        const AppConfigValidationIssue(
          severity: AppConfigValidationSeverity.error,
          code: 'release_fastapi_loopback_url',
          variableName: 'FASTAPI_BASE_URL',
          message: 'Release builds cannot use a loopback API URL.',
        ),
      );
    }

    if (authMode == AuthMode.supabase) {
      requireName('SUPABASE_URL', 'Supabase auth mode');
      requireName('SUPABASE_ANON_KEY', 'Supabase auth mode');
    }

    return issues;
  }

  static AppConfig fromEnv() {
    String? envValue(String key) {
      try {
        return dotenv.maybeGet(key);
      } catch (_) {
        return null;
      }
    }

    final backendMode = switch (envValue('APP_BACKEND_MODE')) {
      'fastapi' => BackendMode.fastApi,
      _ => BackendMode.mock,
    };
    final authMode = switch (envValue('AUTH_MODE')) {
      'supabase' => AuthMode.supabase,
      _ => AuthMode.fastApi,
    };

    return AppConfig(
      backendMode: backendMode,
      authMode: authMode,
      fastApiBaseUrl:
          _normalizeBaseUrl((envValue('FASTAPI_BASE_URL') ?? '').trim()),
      supabaseUrl: (envValue('SUPABASE_URL') ?? '').trim(),
      supabaseAnonKey: (envValue('SUPABASE_ANON_KEY') ?? '').trim(),
      supabaseRedirectScheme:
          (envValue('SUPABASE_REDIRECT_SCHEME') ?? 'jimbro').trim(),
      supabaseRedirectHost:
          (envValue('SUPABASE_REDIRECT_HOST') ?? 'login-callback').trim(),
    );
  }
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnv());

final appConfigValidationProvider =
    Provider<List<AppConfigValidationIssue>>((ref) {
  final config = ref.watch(appConfigProvider);
  Set<String>? variableNames;
  try {
    variableNames = dotenv.env.keys.toSet();
  } catch (_) {
    variableNames = null;
  }
  return config.validate(presentVariableNames: variableNames);
});

String appConfigValidationSummary(List<AppConfigValidationIssue> issues) {
  return issues
      .where((issue) => issue.severity == AppConfigValidationSeverity.error)
      .map((issue) => issue.message)
      .join('\n');
}

bool _baseUrlIncludesApiV1(String value) {
  return _apiV1SegmentCount(value) >= 1;
}

String _normalizeBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
    return trimmed;
  }
  final normalizedSegments = parsed.pathSegments
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  return parsed
      .replace(
        pathSegments: normalizedSegments,
        query: null,
        fragment: null,
      )
      .toString()
      .replaceFirst(RegExp(r'/$'), '');
}

bool _isLoopbackHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

int _apiV1SegmentCount(String value) {
  final parsed = Uri.tryParse(value.trim());
  if (parsed == null) {
    return 0;
  }
  final segments = parsed.pathSegments
      .map((segment) => segment.toLowerCase())
      .toList(growable: false);
  var count = 0;
  for (var index = 0; index < segments.length - 1; index += 1) {
    if (segments[index] == 'api' && segments[index + 1] == 'v1') {
      count += 1;
    }
  }
  return count;
}

bool _looksServerOnlyVariableName(String name) {
  final normalized = name.toUpperCase();
  if (normalized == 'SUPABASE_ANON_KEY') {
    return false;
  }
  return normalized.contains('SERVICE_KEY') ||
      normalized.contains('SERVICE_ROLE') ||
      normalized.contains('JWT_SECRET') ||
      normalized.contains('DATABASE_URL') ||
      normalized.contains('PRIVATE_KEY') ||
      normalized.contains('CLIENT_SECRET') ||
      normalized.endsWith('_SECRET');
}

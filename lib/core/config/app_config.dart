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

  bool get useLiveBackend =>
      backendMode == BackendMode.fastApi && fastApiBaseUrl.isNotEmpty;

  bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  bool get useSupabaseDirectAuth =>
      authMode == AuthMode.supabase && isSupabaseConfigured;

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
      fastApiBaseUrl: (envValue('FASTAPI_BASE_URL') ?? '').trim(),
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

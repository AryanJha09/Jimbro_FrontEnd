import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final env = await _readDotEnvNamesOnly();
  final baseUrl = _readEnvValue('FASTAPI_BASE_URL');
  final token = Platform.environment['JIMBRO_SMOKE_BEARER_TOKEN'];

  _printConfigPresence(env, baseUrl);
  if (baseUrl == null || baseUrl.trim().isEmpty) {
    stderr.writeln('FASTAPI_BASE_URL is missing. Live smoke checks skipped.');
    exitCode = 2;
    return;
  }
  if (!baseUrl.contains('/api/v1')) {
    stderr.writeln('FASTAPI_BASE_URL must include /api/v1.');
    exitCode = 2;
    return;
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  final checks = <_SmokeCheck>[
    const _SmokeCheck('health', '/health', protected: false),
    const _SmokeCheck('auth/me', '/auth/me'),
    const _SmokeCheck('atlas metrics', '/atlas/metrics'),
    _SmokeCheck('food summary', '/food-log/summary/${_todayIso()}'),
    const _SmokeCheck('workout templates', '/workout-templates'),
  ];

  var hadFailure = false;
  for (final check in checks) {
    if (check.protected && (token == null || token.trim().isEmpty)) {
      stdout.writeln('${check.name}: skipped, bearer token not provided');
      continue;
    }
    try {
      final result = await _get(
        client,
        baseUrl,
        check.path,
        bearerToken: check.protected ? token : null,
      );
      stdout.writeln(
        '${check.name}: status=${result.statusCode} keys=${result.keys}',
      );
      if (result.statusCode >= 400) {
        hadFailure = true;
      }
    } catch (error) {
      hadFailure = true;
      stdout.writeln('${check.name}: failed=${error.runtimeType}');
    }
  }

  client.close(force: true);
  exitCode = hadFailure ? 1 : 0;
}

Future<Set<String>> _readDotEnvNamesOnly() async {
  final file = File('.env');
  if (!await file.exists()) {
    return const {};
  }
  final names = <String>{};
  for (final line in await file.readAsLines()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || !trimmed.contains('=')) {
      continue;
    }
    names.add(trimmed.split('=').first.trim());
  }
  return names;
}

String? _readEnvValue(String name) {
  final shellValue = Platform.environment[name];
  if (shellValue != null && shellValue.trim().isNotEmpty) {
    return shellValue.trim();
  }
  final file = File('.env');
  if (!file.existsSync()) {
    return null;
  }
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.startsWith('$name=')) {
      return trimmed.substring(name.length + 1).trim();
    }
  }
  return null;
}

void _printConfigPresence(Set<String> envNames, String? baseUrl) {
  const expected = [
    'APP_BACKEND_MODE',
    'AUTH_MODE',
    'FASTAPI_BASE_URL',
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
    'SUPABASE_REDIRECT_SCHEME',
    'SUPABASE_REDIRECT_HOST',
  ];
  stdout.writeln('Config variable presence only:');
  for (final name in expected) {
    final present =
        envNames.contains(name) || Platform.environment[name] != null;
    stdout.writeln('- $name: ${present ? 'present' : 'missing'}');
  }
  stdout.writeln(
    '- FASTAPI_BASE_URL includes /api/v1: ${baseUrl?.contains('/api/v1') == true}',
  );
}

Future<_SmokeResult> _get(
  HttpClient client,
  String baseUrl,
  String path, {
  String? bearerToken,
}) async {
  final request = await client.getUrl(Uri.parse('${_trimSlash(baseUrl)}$path'));
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  if (bearerToken != null && bearerToken.trim().isNotEmpty) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  final response = await request.close().timeout(const Duration(seconds: 12));
  final body = await utf8.decodeStream(response).timeout(
        const Duration(seconds: 12),
      );
  return _SmokeResult(response.statusCode, _jsonKeys(body));
}

List<String> _jsonKeys(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.keys.map((key) => key.toString()).toList()..sort();
    }
    if (decoded is List) {
      return ['list(length=${decoded.length})'];
    }
  } catch (_) {
    return const ['non_json'];
  }
  return const ['empty'];
}

String _trimSlash(String value) =>
    value.endsWith('/') ? value.substring(0, value.length - 1) : value;

String _todayIso() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

class _SmokeCheck {
  const _SmokeCheck(
    this.name,
    this.path, {
    this.protected = true,
  });

  final String name;
  final String path;
  final bool protected;
}

class _SmokeResult {
  const _SmokeResult(this.statusCode, this.keys);

  final int statusCode;
  final List<String> keys;
}

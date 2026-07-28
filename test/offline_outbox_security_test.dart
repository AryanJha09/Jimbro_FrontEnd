import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const firstUser = AuthSession(
    userId: 'outbox-user-a',
    displayName: 'User A',
    email: 'a@example.test',
    accessToken: 'not-stored-in-outbox',
    provider: 'test',
  );
  const secondUser = AuthSession(
    userId: 'outbox-user-b',
    displayName: 'User B',
    email: 'b@example.test',
    accessToken: 'not-stored-in-outbox',
    provider: 'test',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('outbox round-trips securely without plaintext preferences', () async {
    const store = OfflineOutboxStore();
    await store.enqueue(firstUser, _item('mutation-a'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('offline_outbox_outbox-user-a'), isNull);
    expect(await store.load(firstUser), hasLength(1));
    expect(
      ((await store.load(firstUser)).single.payload['workout'] as Map)['name'],
      'Private log',
    );
  });

  test('corrupt secure payload is discarded', () async {
    FlutterSecureStorage.setMockInitialValues({
      'jimbro.secure_outbox.v2.outbox-user-a': 'not-json',
    });
    const storage = FlutterSecureStorage();
    const store = OfflineOutboxStore();

    expect(await store.load(firstUser), isEmpty);
    expect(
      await storage.read(key: 'jimbro.secure_outbox.v2.outbox-user-a'),
      isNull,
    );
  });

  test('queues are isolated by authenticated user', () async {
    const store = OfflineOutboxStore();
    await store.enqueue(firstUser, _item('mutation-a'));

    expect(await store.load(firstUser), hasLength(1));
    expect(await store.load(secondUser), isEmpty);
  });

  test('legacy plaintext outbox is safely discarded', () async {
    SharedPreferences.setMockInitialValues({
      'offline_outbox_outbox-user-a': jsonEncode([_item('legacy').toJson()]),
    });
    const store = OfflineOutboxStore();

    expect(await store.load(firstUser), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('offline_outbox_outbox-user-a'), isNull);
  });

  test('secure storage unavailability is explicit', () async {
    const store = OfflineOutboxStore(storage: _FailingSecureStorage());

    expect(
      () => store.enqueue(firstUser, _item('mutation-a')),
      throwsA(isA<SecureOutboxUnavailableException>()),
    );
  });
}

OfflineOutboxItem _item(String mutationId) {
  return OfflineOutboxItem(
    localId: mutationId,
    operationType: 'workout_log_create',
    payload: const {
      'workout': {'name': 'Private log'}
    },
    createdAt: DateTime(2026),
    retryCount: 0,
  );
}

class _FailingSecureStorage extends FlutterSecureStorage {
  const _FailingSecureStorage();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw PlatformException(code: 'key_unavailable');
  }
}

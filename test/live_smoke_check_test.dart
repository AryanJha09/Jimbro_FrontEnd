import 'package:flutter_test/flutter_test.dart';

import '../tool/live_smoke_check.dart' as smoke;

void main() {
  test('smoke output summarizes JSON response keys without values', () {
    final keys = smoke.smokeResponseKeyNames(
      '{"email":"person@example.com","id":"secret-id","data":[]}',
    );

    expect(keys, ['data', 'email', 'id']);
    expect(keys.join(' '), isNot(contains('person@example.com')));
    expect(keys.join(' '), isNot(contains('secret-id')));
  });

  test('smoke output reports only safe shapes for non-object responses', () {
    expect(smoke.smokeResponseKeyNames('[{"id":"private"}]'), [
      'list(length=1)',
    ]);
    expect(smoke.smokeResponseKeyNames('not json'), ['non_json']);
  });
}

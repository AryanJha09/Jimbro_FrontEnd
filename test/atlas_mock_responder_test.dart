import 'package:flutter_test/flutter_test.dart';
import 'package:jimbro/features/atlas/application/atlas_mock_responder.dart';

void main() {
  test('returns supplement guidance with disclaimer', () {
    final response = atlasMockResponseFor(
      'Do I need supplements to build muscle?',
    );

    expect(response, contains('protein powder'));
    expect(response, contains('creatine monohydrate'));
    expect(response, contains('This is general guidance, not medical advice.'));
  });

  test('returns coming soon guidance for other questions', () {
    final response = atlasMockResponseFor('How many rest days should I take?');

    expect(response, contains('I can help with that soon.'));
    expect(response, isNot(contains('medical advice')));
  });
}

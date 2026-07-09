import 'package:flutter_test/flutter_test.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  test('stale search responses cannot overwrite the latest query', () {
    final gate = SearchRequestGate();
    final firstRequest = gate.begin('be');
    final latestRequest = gate.begin('bench');

    expect(gate.isCurrent(firstRequest, 'be'), isFalse);
    expect(gate.isCurrent(latestRequest, 'bench'), isTrue);

    gate.clear();

    expect(gate.isCurrent(latestRequest, 'bench'), isFalse);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/shared/components/backend_state_view.dart';

void main() {
  testWidgets('backend error view never renders raw backend exception text',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackendErrorView(
          error: Exception('DioException 500: email=member@example.com'),
          onRetry: () {},
        ),
      ),
    );

    expect(find.text('Could not load app state'), findsOneWidget);
    expect(find.textContaining('could not reach the service'), findsOneWidget);
    expect(find.textContaining('member@example.com'), findsNothing);
    expect(find.textContaining('DioException'), findsNothing);
  });
}

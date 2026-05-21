import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/app/app.dart';

void main() {
  testWidgets('renders JimBro splash stage', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JimBroApp()));

    expect(find.text('JIMBRO'), findsOneWidget);
    expect(find.textContaining('Warming up your companion'), findsOneWidget);
  });

  testWidgets('auth and onboarding reach the home prompt', (tester) async {
    await enterApp(tester);

    expect(find.text('Ask Jim about training, nutrition, or recovery'),
        findsOneWidget);
    expect(find.text('Hey Aryan'), findsOneWidget);
  });

  testWidgets('home prompt accepts typed AI prompt text', (tester) async {
    await enterApp(tester);

    await tester
        .tap(find.text('Ask Jim about training, nutrition, or recovery'));
    await tester.pumpAndSettle();

    expect(find.text('Talk to Jim'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('atlas-prompt-field')),
      'Should I train legs today?',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Should I train legs today?'), findsWidgets);
    expect(find.textContaining('Voice capture will live here'), findsOneWidget);
  });

  testWidgets('profile edit updates visible profile state', (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.person_outline_rounded);

    await tester.enterText(
      find.byKey(const ValueKey('profile-name-field')),
      'Test Athlete',
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Athlete'), findsWidgets);
  });

  testWidgets('food add and edit updates nutrition totals', (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.ramen_dining_outlined);

    expect(find.text('1705 kcal'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-food-entry-button')));
    await tester.pumpAndSettle();
    expect(find.text('1705 kcal'), findsWidgets);

    final caloriesField = find.byKey(const ValueKey('food-calories-field-3'));
    for (var i = 0; i < 6 && caloriesField.evaluate().isEmpty; i++) {
      await tester.drag(
        find.byKey(const ValueKey('nutrition-scroll-view')),
        const Offset(0, -360),
      );
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      caloriesField,
      '220',
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 4 && find.text('1485 kcal').evaluate().isEmpty; i++) {
      await tester.drag(
        find.byKey(const ValueKey('nutrition-scroll-view')),
        const Offset(0, 420),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('1485 kcal'), findsOneWidget);
  });

  testWidgets('workout draft edit updates template UI', (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.fitness_center_rounded);

    await tester.enterText(
      find.byKey(const ValueKey('template-name-field')),
      'Pull Strength',
    );
    await tester.pumpAndSettle();

    expect(find.text('Pull Strength'), findsWidgets);
  });

  testWidgets('consistency increments update streak and companion stage',
      (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.show_chart_rounded);

    expect(find.text('12 day streak'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const ValueKey('increment-streak-button')));
      await tester.pumpAndSettle();
    }

    expect(find.text('16 day streak'), findsOneWidget);
    expect(find.text('Armored I'), findsOneWidget);
  });

  testWidgets('bottom navigation switches pages', (tester) async {
    await enterApp(tester);

    await tapBottomNav(tester, Icons.fitness_center_rounded);
    expect(find.text('Editable training draft'), findsOneWidget);

    await tapBottomNav(tester, Icons.show_chart_rounded);
    expect(find.text('Consistency drives evolution'), findsOneWidget);

    await tapBottomNav(tester, Icons.ramen_dining_outlined);
    expect(find.text('Editable food logging'), findsOneWidget);
  });
}

Future<void> enterApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: JimBroApp()));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Continue with Google'));
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.text('Continue'));
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.text('Continue'));
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.text('Enter JimBro'));
  await tester.tap(find.text('Enter JimBro'));
  await tester.pumpAndSettle();
}

Future<void> tapBottomNav(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon));
  await tester.pumpAndSettle();
}

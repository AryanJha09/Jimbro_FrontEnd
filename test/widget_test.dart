import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/app/app.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders JimBro splash stage', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JimBroApp()));

    expect(find.text('JIMBRO'), findsOneWidget);
    expect(find.textContaining('Warming up your companion'), findsOneWidget);
  });

  testWidgets('auth and onboarding reach the coaching dashboard',
      (tester) async {
    await enterApp(tester);

    expect(find.text('Today\'s focus'), findsOneWidget);
    expect(find.text('Create workout plan'), findsOneWidget);
    expect(find.text('Plan your first workout'), findsOneWidget);
    expect(find.text('Workouts this week'), findsOneWidget);
    expect(find.text('Training streak'), findsOneWidget);
    expect(find.text('Recent volume'), findsOneWidget);
    expect(find.text('Next workout'), findsOneWidget);
  });

  testWidgets('onboarding completion shows optional split generation choice',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JimBroApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await completeOnboardingFlow(tester, finishProgramChoice: false);

    expect(
      find.text('Want Jim to generate your weekly workout split?'),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('generate-program-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('skip-program-button')), findsOneWidget);
  });

  testWidgets('program generation skip enters Home without backend call',
      (tester) async {
    final programs = _CountingProgramRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [programRepositoryProvider.overrideWithValue(programs)],
        child: const JimBroApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await completeOnboardingFlow(tester, finishProgramChoice: false);
    await tester.tap(find.byKey(const ValueKey('skip-program-button')));
    await tester.pumpAndSettle();

    expect(programs.generateCalls, 0);
    expect(find.text('Today\'s focus'), findsOneWidget);
  });

  testWidgets('program generation failure shows retry and keeps app entry open',
      (tester) async {
    final programs = _CountingProgramRepository(succeed: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [programRepositoryProvider.overrideWithValue(programs)],
        child: const JimBroApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await completeOnboardingFlow(tester, finishProgramChoice: false);
    await tester.tap(find.byKey(const ValueKey('generate-program-button')));
    await tester.pumpAndSettle();

    expect(programs.generateCalls, 1);
    expect(
      find.text('Your profile is saved. Jim couldn’t build the split yet.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('skip-program-button')));
    await tester.pumpAndSettle();
    expect(find.text('Today\'s focus'), findsOneWidget);
  });

  testWidgets('home primary CTA opens workout flow', (tester) async {
    await enterApp(tester);

    await tester.tap(find.text('Create workout plan'));
    await tester.pumpAndSettle();

    expect(find.text('Workout templates'), findsOneWidget);
    expect(find.text('Create your first workout template.'), findsOneWidget);
  });

  testWidgets('profile edit updates visible profile state', (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.person_outline_rounded);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-name-field')),
      320,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('profile-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-name-field')),
      'Test Athlete',
    );
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('profile-save-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Test Athlete'), findsWidgets);
    expect(find.text('Profile saved. Targets refreshed.'), findsOneWidget);
  });

  testWidgets('profile sign out returns to auth', (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.person_outline_rounded);

    await tester.tap(find.byKey(const ValueKey('profile-sign-out-button')));
    await tester.pumpAndSettle();

    expect(find.text('Meet Jim'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('debug profile control reopens onboarding without sign out',
      (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.person_outline_rounded);

    expect(find.text('Restart Onboarding (Dev)'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('restart-onboarding-dev-button')));
    await tester.pumpAndSettle();

    expect(
        find.text('Ready to set up your first coaching plan?'), findsOneWidget);
    expect(find.text('Start setup'), findsOneWidget);
  });

  testWidgets('debug onboarding preview completes locally and restarts fresh',
      (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.person_outline_rounded);

    await tester.tap(find.byKey(const ValueKey('preview-onboarding-button')));
    await tester.pumpAndSettle();

    expect(
        find.text('Ready to set up your first coaching plan?'), findsOneWidget);
    await completeOnboardingFlow(tester, finishProgramChoice: false);

    expect(find.text('Shape your coaching plan'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('preview-onboarding-button')));
    await tester.pumpAndSettle();

    expect(
        find.text('Ready to set up your first coaching plan?'), findsOneWidget);
  });

  testWidgets('manual food logging groups meals and updates daily totals',
      (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.ramen_dining_outlined);

    expect(find.text('Today\'s food log'), findsOneWidget);

    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('add-food-breakfast-button')),
    );
    await tester.pumpAndSettle();

    await enterManualFood(
      tester,
      index: 0,
      name: 'Greek yogurt',
      calories: '220',
      protein: '24',
      carbs: '18',
      fat: '4',
    );

    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('add-food-lunch-button')),
    );
    await tester.pumpAndSettle();

    await enterManualFood(
      tester,
      index: 1,
      name: 'Chicken rice bowl',
      calories: '540',
      protein: '32',
      carbs: '72',
      fat: '18',
    );

    await scrollNutritionTextIntoView(
      tester,
      'Breakfast · 220 kcal',
      delta: -360,
    );
    expect(find.text('Breakfast · 220 kcal'), findsOneWidget);

    await scrollNutritionTextIntoView(
      tester,
      'Lunch · 540 kcal',
      delta: 360,
    );
    expect(find.text('Lunch · 540 kcal'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('nutrition-scroll-view')),
      const Offset(0, 900),
    );
    await tester.pumpAndSettle();

    expect(find.text('1660 kcal'), findsWidgets);
    expect(find.text('70 g'), findsWidgets);
    expect(find.textContaining('760 / 2420'), findsWidgets);
    expect(find.textContaining('56 / 126 g'), findsWidgets);
    expect(find.text('90 g'), findsOneWidget);
    expect(find.text('22 g'), findsOneWidget);
  });

  testWidgets('workout draft edit updates template UI', (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.fitness_center_rounded);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('template-name-field')),
      320,
    );
    await tester.pumpAndSettle();
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

    expect(find.text('0 day streak'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const ValueKey('increment-streak-button')));
      await tester.pumpAndSettle();
    }

    expect(find.text('4 day streak'), findsOneWidget);
    expect(find.text('Soft base'), findsWidgets);
  });

  testWidgets('bottom navigation switches pages', (tester) async {
    await enterApp(tester);

    await tapBottomNav(tester, Icons.fitness_center_rounded);
    expect(find.text('Workout templates'), findsOneWidget);

    await tapBottomNav(tester, Icons.show_chart_rounded);
    expect(find.text('Consistency drives evolution'), findsOneWidget);

    await tapBottomNav(tester, Icons.ramen_dining_outlined);
    expect(find.text('Today\'s food log'), findsOneWidget);
  });
}

Future<void> enterApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: JimBroApp()));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Continue with Google'));
  await tester.pumpAndSettle();

  await completeOnboardingFlow(tester);
}

Future<void> completeOnboardingFlow(
  WidgetTester tester, {
  bool finishProgramChoice = true,
}) async {
  await tapOnboardingCta(tester, 'Start setup');
  await selectOnboardingOption(tester, 'Build muscle');
  await tapOnboardingCta(tester, 'Continue');
  await selectOnboardingOption(tester, 'I want more energy');
  await tapOnboardingCta(tester, 'Continue');
  await selectOnboardingOption(
      tester, 'I’ve trained before, but not consistently');
  await tapOnboardingCta(tester, 'Continue');
  await tapOnboardingCta(tester, 'Continue');
  await selectOnboardingOption(tester, 'Lightly active');
  await tapOnboardingCta(tester, 'Continue');
  await selectOnboardingOption(tester, '30 minutes');
  await tapOnboardingCta(tester, 'Continue');
  await selectOnboardingOption(tester, 'Home workouts');
  await tapOnboardingCta(tester, 'Continue');
  await tapOnboardingCta(tester, 'Continue');
  await selectOnboardingOption(tester, 'Keep it simple');
  await tapOnboardingCta(tester, 'Continue');
  await tapOnboardingCta(tester, 'Continue');
  await selectOnboardingOption(tester, 'Prefer not to say');
  await tapOnboardingCta(tester, 'Continue');
  await tapOnboardingCta(tester, 'Continue');
  await tapOnboardingCta(tester, 'Continue');
  await tapOnboardingCta(tester, 'Start my plan');
  await tester.pumpAndSettle();
  if (finishProgramChoice && find.text('Skip for now').evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const ValueKey('skip-program-button')));
    await tester.pumpAndSettle();
  }
}

Future<void> tapBottomNav(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon).last);
  await tester.pumpAndSettle();
}

Future<void> tapScrollableTarget(
  WidgetTester tester,
  Finder finder,
) async {
  await tester.scrollUntilVisible(
    finder,
    360,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('nutrition-scroll-view')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.25,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> scrollNutritionTextIntoView(
  WidgetTester tester,
  String text, {
  required double delta,
}) async {
  await tester.scrollUntilVisible(
    find.text(text),
    delta,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('nutrition-scroll-view')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> enterManualFood(
  WidgetTester tester, {
  required int index,
  required String name,
  required String calories,
  required String protein,
  required String carbs,
  required String fat,
}) async {
  Future<void> enterField(String key, String value) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, value);
    await tester.pumpAndSettle();
  }

  await enterField('food-name-field-$index', name);
  await enterField('food-calories-field-$index', calories);
  await enterField('food-protein-field-$index', protein);
  await enterField('food-carbs-field-$index', carbs);
  await enterField('food-fat-field-$index', fat);
}

Future<void> selectOnboardingOption(
  WidgetTester tester,
  String label,
) async {
  final option = find.byKey(ValueKey('onboarding-option-$label'));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  final topLeft = tester.getTopLeft(option);
  await tester.tapAt(topLeft + const Offset(32, 24));
  await tester.pumpAndSettle();
}

Future<void> tapOnboardingCta(
  WidgetTester tester,
  String label,
) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class _CountingProgramRepository implements ProgramRepository {
  _CountingProgramRepository({this.succeed = true});

  final bool succeed;
  int generateCalls = 0;

  @override
  Future<ProgramGenerationResult> generateProgram(AuthSession? session) async {
    generateCalls++;
    if (succeed) {
      return const ProgramGenerationResult.success();
    }
    return const ProgramGenerationResult.failure(
      'Jim could not build your split yet. You can retry or skip for now.',
    );
  }
}

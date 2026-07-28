import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jimbro/app/app.dart';
import 'package:jimbro/core/errors/app_error.dart';
import 'package:jimbro/core/repositories/app_repositories.dart';
import 'package:jimbro/core/theme/jim_theme.dart';
import 'package:jimbro/shared/components/jim_companion.dart';
import 'package:jimbro/shared/models/app_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders JimBro splash stage', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JimBroApp()));

    expect(find.text('JIMBRO'), findsOneWidget);
    expect(find.textContaining('Warming up your companion'), findsOneWidget);
    expect(find.byType(JimCompanionAvatar), findsOneWidget);
  });

  testWidgets('auth and onboarding reach the coaching dashboard',
      (tester) async {
    await enterApp(tester);

    expect(find.text('Today\'s focus'), findsOneWidget);
    expect(find.text('Create workout plan'), findsOneWidget);
    expect(find.text('Plan your first workout'), findsOneWidget);
    for (final label in const [
      'Workouts this week',
      'Training streak',
      'Recent volume',
      'Next workout',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(label), findsOneWidget);
    }
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

  testWidgets(
      'dietary step shows five choices, blocks continue, and preserves selection',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JimBroApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    await tapOnboardingCta(tester, 'Start setup');
    await selectOnboardingOption(tester, 'Build muscle');
    await tapOnboardingCta(tester, 'Continue');
    await selectOnboardingOption(tester, 'I want more energy');
    await tapOnboardingCta(tester, 'Continue');
    await selectOnboardingOption(
      tester,
      'I’ve trained before, but not consistently',
    );
    await tapOnboardingCta(tester, 'Continue');
    await tapOnboardingCta(tester, 'Continue');
    await selectOnboardingOption(tester, 'Lightly active');
    await tapOnboardingCta(tester, 'Continue');
    await selectOnboardingOption(tester, '30 minutes');
    await tapOnboardingCta(tester, 'Continue');
    await selectOnboardingOption(tester, 'Home workouts');
    await tapOnboardingCta(tester, 'Continue');
    await tapOnboardingCta(tester, 'Continue');

    for (final label in const [
      'Omnivore',
      'Vegetarian',
      'Vegan',
      'Keto',
      'Other',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    await tapOnboardingCta(tester, 'Continue');
    expect(
      find.text('Which dietary preference fits you best?'),
      findsOneWidget,
    );

    await selectOnboardingOption(tester, 'Keto');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tapOnboardingCta(tester, 'Continue');
    await tapOnboardingCta(tester, 'Continue');

    expect(find.text('How old are you?'), findsOneWidget);
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

  testWidgets('failed canonical profile write keeps onboarding incomplete',
      (tester) async {
    final profiles = _FailingOnboardingProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(profiles)],
        child: const JimBroApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await completeOnboardingFlow(
      tester,
      finishProgramChoice: false,
      expectSaveFailure: true,
    );

    expect(profiles.onboardingSaveAttempts, 1);
    expect(profiles.lastOnboardingCompleted, isTrue);
    expect(
      find.byKey(const ValueKey('retry-onboarding-save-button')),
      findsOneWidget,
    );
    expect(
      find.text('Want Jim to generate your weekly workout split?'),
      findsNothing,
    );
    expect(find.text('Today\'s focus'), findsNothing);
  });

  testWidgets('home primary CTA opens workout flow', (tester) async {
    await enterApp(tester);

    await tester.tap(find.text('Create workout plan'));
    await tester.pumpAndSettle();

    expect(find.text('Workout templates'), findsOneWidget);
    expect(find.text('Create your first workout template.'), findsOneWidget);
  });

  testWidgets('home has one usable five-tab navigation and shared mascot',
      (tester) async {
    await enterApp(tester);

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.byType(JimCompanionAvatar), findsOneWidget);
    expect(find.text('Workout'), findsNothing);
    expect(find.text('Food'), findsNothing);
    expect(find.text('Progress'), findsNothing);
    expect(find.text('Profile'), findsNothing);
    final navigation = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(navigation.items, hasLength(5));

    for (var index = 0; index < navigation.items.length; index++) {
      final icon = navigation.items[index].icon as Icon;
      await tester.tap(find.byIcon(icon.icon!).last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        index,
      );
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('home remains scrollable above its bar at supported widths',
      (tester) async {
    await enterApp(tester);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    tester.view.devicePixelRatio = 1;

    await tester.drag(find.byType(ListView).first, const Offset(0, -5000));
    await tester.pumpAndSettle();
    final finalContent = find.byIcon(Icons.lightbulb_outline_rounded).last;
    expect(finalContent, findsOneWidget);
    final contentBottom = tester.getBottomRight(finalContent).dy;
    final navigationTop =
        tester.getTopLeft(find.byType(BottomNavigationBar)).dy;
    expect(contentBottom, lessThan(navigationTop));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: JimTheme.lightTheme,
        home: const Scaffold(
          body: Center(
            child: JimCompanionAvatar(
              stage: JimCompanionStage.softBase,
              size: 64,
            ),
          ),
        ),
      ),
    );
    for (final width in const [320.0, 375.0, 430.0]) {
      tester.view.physicalSize = Size(width, 760);
      await tester.pumpAndSettle();
      expect(find.byType(JimCompanionAvatar), findsOneWidget);
      final avatarRect = tester.getRect(find.byType(JimCompanionAvatar));
      expect(avatarRect.left, greaterThanOrEqualTo(0));
      expect(avatarRect.right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull, reason: 'width: $width');
    }
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'text scale');
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
      find.byKey(const ValueKey('log-food-0-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Food logged and synced.'), findsOneWidget);

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
    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('log-food-1-button')),
    );
    await tester.pumpAndSettle();

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
      const Offset(0, 3000),
    );
    await tester.pumpAndSettle();

    expect(find.text('1660 kcal'), findsWidgets);
    expect(find.text('77 g'), findsWidgets);
    expect(find.textContaining('760 / 2420'), findsWidgets);
    expect(find.textContaining('56 / 133 g'), findsWidgets);
    expect(find.text('90 g'), findsOneWidget);
    expect(find.text('22 g'), findsOneWidget);

    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('delete-food-0-button')),
    );
    expect(find.text('Food deleted.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Food restored and synced.'), findsOneWidget);
  });

  testWidgets('food CTA prevents duplicate taps while commit is in flight',
      (tester) async {
    final repository = _ControlledNutritionRepository()..delaySave = true;
    await enterAppWithNutritionRepository(tester, repository);
    await tapBottomNav(tester, Icons.ramen_dining_outlined);
    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('add-food-breakfast-button')),
    );
    await enterManualFood(
      tester,
      index: 0,
      name: 'Oats',
      calories: '200',
      protein: '10',
      carbs: '30',
      fat: '4',
    );
    final button = find.byKey(const ValueKey('log-food-0-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();

    expect(repository.saveCalls, 1);
    repository.releaseSave();
    await tester.pumpAndSettle();
    expect(find.text('Logged'), findsWidgets);
  });

  testWidgets('food entry shows pending, failed and retry states truthfully',
      (tester) async {
    final repository = _ControlledNutritionRepository()
      ..pendingSavesRemaining = 1;
    await enterAppWithNutritionRepository(tester, repository);
    await tapBottomNav(tester, Icons.ramen_dining_outlined);
    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('add-food-breakfast-button')),
    );
    await enterManualFood(
      tester,
      index: 0,
      name: 'Paneer',
      calories: '250',
      protein: '20',
      carbs: '8',
      fat: '16',
    );
    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('log-food-0-button')),
    );
    expect(find.text('Pending sync'), findsWidgets);

    // A fresh draft exercises the retryable failure path independently.
    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('add-food-lunch-button')),
    );
    await enterManualFood(
      tester,
      index: 1,
      name: 'Rice',
      calories: '180',
      protein: '4',
      carbs: '40',
      fat: '1',
    );
    repository.failedSavesRemaining = 1;
    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('log-food-1-button')),
    );
    expect(find.text('Failed — retry'), findsOneWidget);
    expect(find.text('Retry logging'), findsOneWidget);

    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('log-food-1-button')),
    );
    expect(repository.saveCalls, 3);
    expect(find.text('Logged'), findsWidgets);
  });

  testWidgets('search select quantity meal and CTA work on a small screen',
      (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.ramen_dining_outlined);
    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('add-food-breakfast-button')),
    );
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-name-field-0')),
      'greek',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Greek Yogurt'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-quantity-field-0')),
      '150',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-meal-field-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lunch').last);
    await tester.pumpAndSettle();

    await tapScrollableTarget(
      tester,
      find.byKey(const ValueKey('log-food-0-button')),
    );
    expect(find.text('Food logged and synced.'), findsOneWidget);
    expect(find.textContaining('Lunch · 88.5 kcal'), findsOneWidget);
  });

  testWidgets('workout draft edit updates template UI', (tester) async {
    await enterApp(tester);
    await tapBottomNav(tester, Icons.fitness_center_rounded);

    await tester.tap(find.text('Create Template'));
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

Future<void> enterAppWithNutritionRepository(
  WidgetTester tester,
  NutritionRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nutritionRepositoryProvider.overrideWithValue(repository),
      ],
      child: const JimBroApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue with Google'));
  await tester.pumpAndSettle();
  await completeOnboardingFlow(tester);
}

Future<void> completeOnboardingFlow(
  WidgetTester tester, {
  bool finishProgramChoice = true,
  bool expectSaveFailure = false,
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
  await selectOnboardingOption(tester, 'Vegetarian');
  await tapOnboardingCta(tester, 'Continue');
  await tapOnboardingCta(tester, 'Continue');
  await selectOnboardingOption(tester, 'Prefer not to say');
  await tapOnboardingCta(tester, 'Continue');
  await tapOnboardingCta(tester, 'Continue');
  await tapOnboardingCta(tester, 'Continue');
  await tester.ensureVisible(find.text('Start my plan').last);
  await tester.tap(find.text('Start my plan').last);
  if (expectSaveFailure) {
    await tester.pump(const Duration(milliseconds: 500));
  } else {
    await tester.pumpAndSettle();
  }
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

class _ControlledNutritionRepository extends MockNutritionRepository {
  int saveCalls = 0;
  int pendingSavesRemaining = 0;
  int failedSavesRemaining = 0;
  bool delaySave = false;
  Completer<void>? _saveRelease;

  void releaseSave() {
    _saveRelease?.complete();
  }

  @override
  Future<NutritionMutationResult> saveFoodLogs(
    AuthSession? session,
    List<FoodLogDraft> logs,
  ) async {
    saveCalls++;
    if (pendingSavesRemaining > 0) {
      pendingSavesRemaining--;
      throw const NutritionMutationPendingException(
        'Nutrition changes are waiting to sync.',
      );
    }
    if (failedSavesRemaining > 0) {
      failedSavesRemaining--;
      throw const AppError(
        code: AppErrorCode.serverUnavailable,
        userMessage: 'The service is temporarily unavailable.',
        diagnostics: AppErrorDiagnostics(retryable: true),
      );
    }
    if (delaySave) {
      _saveRelease ??= Completer<void>();
      await _saveRelease!.future;
      delaySave = false;
    }
    return super.saveFoodLogs(session, logs);
  }
}

class _FailingOnboardingProfileRepository extends MockProfileRepository {
  int onboardingSaveAttempts = 0;
  bool? lastOnboardingCompleted;

  @override
  Future<UserProfile> saveProfile(
    AuthSession? session,
    UserProfile profile, {
    bool onboardingCompleted = false,
  }) async {
    if (onboardingCompleted) {
      onboardingSaveAttempts++;
      lastOnboardingCompleted = onboardingCompleted;
      throw Exception('simulated profile write failure');
    }
    return super.saveProfile(
      session,
      profile,
      onboardingCompleted: onboardingCompleted,
    );
  }
}

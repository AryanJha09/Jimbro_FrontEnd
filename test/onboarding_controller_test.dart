import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:jimbro/features/onboarding/application/onboarding_controller.dart';
import 'package:jimbro/shared/models/onboarding_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists answered progress and resumes in a new container', () async {
    final firstContainer = ProviderContainer();
    addTearDown(firstContainer.dispose);

    await firstContainer.read(onboardingControllerProvider.future);
    final firstController =
        firstContainer.read(onboardingControllerProvider.notifier);

    await firstController.continueFromCurrentStep();
    await firstController.answerFitnessGoal(OnboardingFitnessGoal.buildMuscle);
    await firstController.continueFromCurrentStep();

    final secondContainer = ProviderContainer();
    addTearDown(secondContainer.dispose);

    final resumed =
        await secondContainer.read(onboardingControllerProvider.future);

    expect(resumed.currentStepId, OnboardingStepId.motivation.wireValue);
    expect(resumed.answers.fitnessGoal, OnboardingFitnessGoal.buildMuscle);
    expect(
      resumed.completedStepIds,
      containsAll([
        OnboardingStepId.welcome.wireValue,
        OnboardingStepId.goal.wireValue,
      ]),
    );
  });

  test('repairs resumed progress to earliest incomplete required step',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesOnboardingPersistenceStore(preferences);
    final now = DateTime.now();

    await store.save(
      OnboardingPersistenceModel(
        userId: 'local',
        status: OnboardingPersistenceStatus.inProgress,
        currentStepId: OnboardingStepId.coachSummary.wireValue,
        completedStepIds: const [
          'welcome',
          'goal',
          'motivation',
        ],
        answers: const OnboardingAnswersDto(
          fitnessGoal: OnboardingFitnessGoal.loseWeight,
          motivation: OnboardingMotivation.moreEnergy,
        ),
        inference: const OnboardingInferenceResultDto(),
        startedAt: now,
        updatedAt: now,
      ),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final resumed = await container.read(onboardingControllerProvider.future);

    expect(resumed.currentStepId, OnboardingStepId.experience.wireValue);
    expect(resumed.answers.fitnessGoal, OnboardingFitnessGoal.loseWeight);
    expect(resumed.answers.motivation, OnboardingMotivation.moreEnergy);
  });

  test('requires valid answers and inference before completion', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final initial = await container.read(onboardingControllerProvider.future);
    final controller = container.read(onboardingControllerProvider.notifier);

    expect(controller.validateForCompletion(initial).isValid, isFalse);

    await controller.answerFitnessGoal(OnboardingFitnessGoal.feelFitter);
    await controller.answerMotivation(OnboardingMotivation.feelBetter);
    await controller
        .answerExperienceLevel(OnboardingExperienceLevel.inconsistent);
    await controller.answerActivityLevel(OnboardingActivityLevel.lightlyActive);
    await controller.answerAvailableTimeMin(30);
    await controller
        .answerTrainingPreference(OnboardingTrainingPreference.home);
    await controller
        .answerDietaryPreference(OnboardingDietaryPreference.omnivore);
    await controller.answerAge(28);
    await controller.answerSex(OnboardingSex.preferNotToSay);
    await controller.answerHeightCm(172);
    await controller.answerWeightKg(74);

    final beforeInference = container.read(onboardingControllerProvider).value!;
    expect(controller.validateForCompletion(beforeInference).isValid, isFalse);

    await controller.updateInference(
      recommendedFrequency: '3 days/week',
      adherenceScore: 82,
    );

    final ready = container.read(onboardingControllerProvider).value!;
    expect(controller.validateForCompletion(ready).isValid, isTrue);
  });

  test('dietary preference uses exact API enum values and rejects old values',
      () {
    expect(
      OnboardingDietaryPreference.values
          .map((value) => value.wireValue)
          .toSet(),
      {
        'omnivore',
        'vegetarian',
        'vegan',
        'keto',
        'other',
      },
    );

    for (final preference in OnboardingDietaryPreference.values) {
      final encoded = OnboardingAnswersDto(
        dietaryPreference: preference,
      ).toJson();
      expect(encoded['dietary_preference'], preference.wireValue);
      expect(
        OnboardingAnswersDto.fromJson(encoded).dietaryPreference,
        preference,
      );
    }

    expect(
      OnboardingAnswersDto.fromJson(
        const {'dietary_preference': 'Keep it simple'},
      ).dietaryPreference,
      isNull,
    );
  });

  test('dietary selection persists across navigation and reload', () async {
    final firstContainer = ProviderContainer();
    addTearDown(firstContainer.dispose);
    await firstContainer.read(onboardingControllerProvider.future);
    final controller =
        firstContainer.read(onboardingControllerProvider.notifier);

    await controller.answerDietaryPreference(
      OnboardingDietaryPreference.keto,
    );
    await controller.goToStep(OnboardingStepId.age);
    await controller.goBack();

    expect(
      firstContainer
          .read(onboardingControllerProvider)
          .value!
          .answers
          .dietaryPreference,
      OnboardingDietaryPreference.keto,
    );

    final secondContainer = ProviderContainer();
    addTearDown(secondContainer.dispose);
    final resumed =
        await secondContainer.read(onboardingControllerProvider.future);
    expect(
      resumed.answers.dietaryPreference,
      OnboardingDietaryPreference.keto,
    );
  });

  test('failed step write stays on the current step and retry advances',
      () async {
    final store = _TestOnboardingStore()..failNextSave = true;
    final container = _containerWithStore(store);
    addTearDown(container.dispose);
    await container.read(onboardingControllerProvider.future);
    final controller = container.read(onboardingControllerProvider.notifier);

    await controller.continueFromCurrentStep();

    final failed = container.read(onboardingControllerProvider).value!;
    expect(failed.currentStepId, OnboardingStepId.welcome.wireValue);
    expect(failed.errorMessage, isNotNull);
    expect(store.saved, isNull);

    final restarted = _containerWithStore(store);
    addTearDown(restarted.dispose);
    expect(
      (await restarted.read(onboardingControllerProvider.future)).currentStepId,
      OnboardingStepId.welcome.wireValue,
    );

    await controller.continueFromCurrentStep();
    expect(
      container.read(onboardingControllerProvider).value!.currentStepId,
      OnboardingStepId.goal.wireValue,
    );
  });

  test('failed answer write retains dietary selection and retry persists it',
      () async {
    final store = _TestOnboardingStore()..failNextSave = true;
    final container = _containerWithStore(store);
    addTearDown(container.dispose);
    await container.read(onboardingControllerProvider.future);
    final controller = container.read(onboardingControllerProvider.notifier);

    await controller.answerDietaryPreference(
      OnboardingDietaryPreference.vegetarian,
    );

    final failed = container.read(onboardingControllerProvider).value!;
    expect(
      failed.answers.dietaryPreference,
      OnboardingDietaryPreference.vegetarian,
    );
    expect(failed.errorMessage, isNotNull);

    await controller.retryPersist();
    final restarted = _containerWithStore(store);
    addTearDown(restarted.dispose);
    final resumed = await restarted.read(onboardingControllerProvider.future);
    expect(
      resumed.answers.dietaryPreference,
      OnboardingDietaryPreference.vegetarian,
    );
  });

  test('rapid continue actions perform one persistence write', () async {
    final saveGate = Completer<void>();
    final store = _TestOnboardingStore(saveGate: saveGate);
    final container = _containerWithStore(store);
    addTearDown(container.dispose);
    await container.read(onboardingControllerProvider.future);
    final controller = container.read(onboardingControllerProvider.notifier);

    final first = controller.continueFromCurrentStep();
    await Future<void>.delayed(Duration.zero);
    final second = controller.continueFromCurrentStep();
    await Future<void>.delayed(Duration.zero);

    expect(store.saveCalls, 1);
    saveGate.complete();
    await Future.wait([first, second]);
    expect(
      container.read(onboardingControllerProvider).value!.currentStepId,
      OnboardingStepId.goal.wireValue,
    );
  });

  test('failed final write remains incomplete and retry completes', () async {
    final now = DateTime.now();
    final store = _TestOnboardingStore(
      saved: OnboardingPersistenceModel(
        userId: 'local',
        status: OnboardingPersistenceStatus.inProgress,
        currentStepId: OnboardingStepId.coachSummary.wireValue,
        completedStepIds: OnboardingStepId.values
            .where((step) => step != OnboardingStepId.coachSummary)
            .map((step) => step.wireValue)
            .toList(),
        answers: const OnboardingAnswersDto(
          fitnessGoal: OnboardingFitnessGoal.feelFitter,
          motivation: OnboardingMotivation.feelBetter,
          experienceLevel: OnboardingExperienceLevel.inconsistent,
          activityLevel: OnboardingActivityLevel.lightlyActive,
          availableTimeMin: 30,
          trainingPreference: OnboardingTrainingPreference.home,
          dietaryPreference: OnboardingDietaryPreference.omnivore,
          age: 28,
          sex: OnboardingSex.preferNotToSay,
          heightCm: 172,
          weightKg: 74,
        ),
        inference: const OnboardingInferenceResultDto(
          recommendedFrequency: '3 days/week',
          adherenceScore: 82,
        ),
        startedAt: now,
        updatedAt: now,
      ),
    )..failNextSave = true;
    final container = _containerWithStore(store);
    addTearDown(container.dispose);
    await container.read(onboardingControllerProvider.future);
    final controller = container.read(onboardingControllerProvider.notifier);

    expect(await controller.complete(), isFalse);
    expect(store.saved!.status, OnboardingPersistenceStatus.inProgress);
    expect(
      container.read(onboardingControllerProvider).value!.errorMessage,
      isNotNull,
    );

    expect(await controller.complete(), isTrue);
    expect(store.saved!.status, OnboardingPersistenceStatus.completed);
  });
}

ProviderContainer _containerWithStore(_TestOnboardingStore store) {
  return ProviderContainer(
    overrides: [
      onboardingPersistenceStoreProvider.overrideWith((ref) async => store),
    ],
  );
}

class _TestOnboardingStore implements OnboardingPersistenceStore {
  _TestOnboardingStore({this.saved, this.saveGate});

  OnboardingPersistenceModel? saved;
  final Completer<void>? saveGate;
  bool failNextSave = false;
  int saveCalls = 0;

  @override
  Future<void> clear(String userId) async {
    saved = null;
  }

  @override
  Future<OnboardingPersistenceModel?> load(String userId) async => saved;

  @override
  Future<void> save(OnboardingPersistenceModel model) async {
    saveCalls++;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Test persistence failure');
    }
    await saveGate?.future;
    saved = model;
  }
}

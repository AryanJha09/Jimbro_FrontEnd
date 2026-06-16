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
        .answerDietaryPreference(OnboardingDietaryPreference.simple);
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
}

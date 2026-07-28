import '../../shared/models/app_models.dart';

class NutritionTargetEstimate {
  const NutritionTargetEstimate({
    required this.hasRequiredProfile,
    required this.bmr,
    required this.tdee,
    required this.calorieTarget,
    required this.maintenanceCalories,
    required this.cutCalories,
    required this.bulkCalories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.hydrationL,
    required this.activityMultiplier,
    required this.goalLabel,
    required this.assumptionSummary,
  });

  final bool hasRequiredProfile;
  final double bmr;
  final double tdee;
  final double calorieTarget;
  final double maintenanceCalories;
  final double cutCalories;
  final double bulkCalories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double hydrationL;
  final double activityMultiplier;
  final String goalLabel;
  final String assumptionSummary;

  UserStaticMetrics toMetrics() {
    return UserStaticMetrics(
      bmr: bmr,
      tdee: tdee,
      targetCalories: calorieTarget,
      maintenanceCalories: maintenanceCalories,
      cutCalories: cutCalories,
      bulkCalories: bulkCalories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      hydrationL: hydrationL,
      cutIntensity: assumptionSummary,
    );
  }
}

class NutritionTargetCalculator {
  const NutritionTargetCalculator._();

  static const _deficitRate = 0.15;
  static const _muscleGainSurplusRate = 0.10;
  static const _strengthSurplusRate = 0.05;
  static const _hydrationMlPerKg = 35.0;

  static NutritionTargetEstimate estimate(UserProfile profile) {
    final age = profile.age;
    final heightCm = profile.heightCm;
    final weightKg = profile.weightKg;
    final sex = profile.sex;
    if (age == null ||
        age <= 0 ||
        heightCm == null ||
        heightCm <= 0 ||
        weightKg == null ||
        weightKg <= 0 ||
        sex == null ||
        sex.trim().isEmpty) {
      return const NutritionTargetEstimate(
        hasRequiredProfile: false,
        bmr: 0,
        tdee: 0,
        calorieTarget: 0,
        maintenanceCalories: 0,
        cutCalories: 0,
        bulkCalories: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        hydrationL: 0,
        activityMultiplier: 0,
        goalLabel: 'Needs profile',
        assumptionSummary: 'Add age, sex, height, and weight to estimate.',
      );
    }

    final bmr = _roundToNearest(
      (10 * weightKg) + (6.25 * heightCm) - (5 * age) + _sexConstant(sex),
      1,
    );
    final activityMultiplier = _activityMultiplier(profile.activityLevel ?? '');
    final tdee = _roundToNearest(bmr * activityMultiplier, 10);
    final maintenance = tdee;
    final cut = _roundToNearest(tdee * (1 - _deficitRate), 10);
    final bulk = _roundToNearest(tdee * (1 + _muscleGainSurplusRate), 10);
    final goal = _targetGoal(profile.goal ?? '');
    final calorieTarget = switch (goal) {
      _TargetGoal.fatLoss => cut,
      _TargetGoal.muscleGain => bulk,
      _TargetGoal.strength => _roundToNearest(
          tdee * (1 + _strengthSurplusRate),
          10,
        ),
      _TargetGoal.generalHealth || _TargetGoal.consistency => maintenance,
    };
    final proteinPerKg = _proteinPerKg(
      goal: goal,
      dietaryPreference: profile.dietaryPreference ?? '',
    );
    final proteinG = _roundToNearest(weightKg * proteinPerKg, 1);
    final hydrationL = _roundToNearest(
      (weightKg * _hydrationMlPerKg / 1000).clamp(1.5, 5.0),
      0.1,
    );
    final fatG = _roundToNearest((calorieTarget * 0.25) / 9, 1);
    final carbsCalories = calorieTarget - (proteinG * 4) - (fatG * 9);
    final carbsG = _roundToNearest(
      carbsCalories.clamp(0, calorieTarget).toDouble() / 4,
      1,
    );

    return NutritionTargetEstimate(
      hasRequiredProfile: true,
      bmr: bmr,
      tdee: tdee,
      calorieTarget: calorieTarget,
      maintenanceCalories: maintenance,
      cutCalories: cut,
      bulkCalories: bulk,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      hydrationL: hydrationL,
      activityMultiplier: activityMultiplier,
      goalLabel: _goalLabel(goal),
      assumptionSummary:
          'Mifflin-St Jeor, ${activityMultiplier.toStringAsFixed(3)}x activity, ${_goalLabel(goal).toLowerCase()} calories, ${proteinPerKg.toStringAsFixed(1)}g/kg protein, 35ml/kg water.',
    );
  }

  static double _sexConstant(String value) {
    final normalized = _normalize(value);
    if (normalized.contains('female') || normalized == 'f') {
      return -161;
    }
    if (normalized.contains('male') || normalized == 'm') {
      return 5;
    }
    return -78;
  }

  static double _activityMultiplier(String value) {
    final normalized = _normalize(value);
    if (normalized.contains('mostly_sitting') ||
        normalized.contains('sedentary') ||
        normalized.contains('mostly sitting')) {
      return 1.2;
    }
    if (normalized.contains('light')) {
      return 1.375;
    }
    if (normalized.contains('moderate')) {
      return 1.55;
    }
    if (normalized.contains('very') || normalized.contains('active job')) {
      return 1.725;
    }
    if (normalized.contains('changes') || normalized.contains('varies')) {
      return 1.45;
    }
    return 1.375;
  }

  static _TargetGoal _targetGoal(String value) {
    final normalized = _normalize(value);
    if (normalized.contains('lose') ||
        normalized.contains('fat') ||
        normalized.contains('cut')) {
      return _TargetGoal.fatLoss;
    }
    if (normalized.contains('muscle') ||
        normalized.contains('bulk') ||
        normalized.contains('gain')) {
      return _TargetGoal.muscleGain;
    }
    if (normalized.contains('strong') || normalized.contains('strength')) {
      return _TargetGoal.strength;
    }
    if (normalized.contains('consistent') || normalized.contains('routine')) {
      return _TargetGoal.consistency;
    }
    return _TargetGoal.generalHealth;
  }

  static double _proteinPerKg({
    required _TargetGoal goal,
    required String dietaryPreference,
  }) {
    final normalizedPreference = _normalize(dietaryPreference);
    final base = switch (goal) {
      _TargetGoal.fatLoss => 1.8,
      _TargetGoal.muscleGain => 1.8,
      _TargetGoal.strength => 1.7,
      _TargetGoal.generalHealth || _TargetGoal.consistency => 1.5,
    };
    final adjusted = normalizedPreference.contains('protein')
        ? base + 0.1
        : normalizedPreference.contains('not now') ||
                normalizedPreference.contains('not_now') ||
                normalizedPreference.contains('simple')
            ? base - 0.1
            : base;
    return adjusted.clamp(1.4, 2.0).toDouble();
  }

  static String _goalLabel(_TargetGoal goal) {
    return switch (goal) {
      _TargetGoal.fatLoss => 'Moderate deficit',
      _TargetGoal.muscleGain => 'Moderate surplus',
      _TargetGoal.strength => 'Slight surplus',
      _TargetGoal.generalHealth => 'Maintenance',
      _TargetGoal.consistency => 'Maintenance',
    };
  }

  static double _roundToNearest(double value, double nearest) {
    if (value <= 0 || nearest <= 0) {
      return 0;
    }
    final rounded = (value / nearest).round() * nearest;
    return double.parse(rounded.toStringAsFixed(3));
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll('-', '_');
  }
}

enum _TargetGoal {
  fatLoss,
  muscleGain,
  strength,
  generalHealth,
  consistency,
}

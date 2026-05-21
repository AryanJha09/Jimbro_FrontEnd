enum JimCompanionStage {
  softBase,
  activeBase,
  armored1,
  armored2,
  jackedArmorFinal,
}

enum UserLevel {
  beginner,
  intermediate,
  advanced,
}

enum MealType {
  breakfast,
  lunch,
  dinner,
  snack,
}

enum SearchCategory {
  exercises,
  foods,
  metrics,
  insights,
}

const Object _unset = Object();

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.accessToken,
    this.refreshToken,
    required this.provider,
  });

  final String userId;
  final String displayName;
  final String email;
  final String accessToken;
  final String? refreshToken;
  final String provider;

  Map<String, String> get fastApiHeaders {
    return {'Authorization': 'Bearer $accessToken'};
  }
}

class UserProfile {
  const UserProfile({
    required this.name,
    required this.goal,
    required this.coachingPreference,
    required this.userLevel,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.weeksActive,
    required this.prefersVoiceLogging,
  });

  final String name;
  final String goal;
  final String coachingPreference;
  final UserLevel userLevel;
  final int age;
  final double heightCm;
  final double weightKg;
  final int weeksActive;
  final bool prefersVoiceLogging;

  UserProfile copyWith({
    String? name,
    String? goal,
    String? coachingPreference,
    UserLevel? userLevel,
    int? age,
    double? heightCm,
    double? weightKg,
    int? weeksActive,
    bool? prefersVoiceLogging,
  }) {
    return UserProfile(
      name: name ?? this.name,
      goal: goal ?? this.goal,
      coachingPreference: coachingPreference ?? this.coachingPreference,
      userLevel: userLevel ?? this.userLevel,
      age: age ?? this.age,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      weeksActive: weeksActive ?? this.weeksActive,
      prefersVoiceLogging: prefersVoiceLogging ?? this.prefersVoiceLogging,
    );
  }
}

class UserStaticMetrics {
  const UserStaticMetrics({
    required this.bmr,
    required this.tdee,
    required this.maintenanceCalories,
    required this.cutCalories,
    required this.bulkCalories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.hydrationL,
    required this.cutIntensity,
  });

  final double bmr;
  final double tdee;
  final double maintenanceCalories;
  final double cutCalories;
  final double bulkCalories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double hydrationL;
  final String cutIntensity;

  UserStaticMetrics copyWith({
    double? bmr,
    double? tdee,
    double? maintenanceCalories,
    double? cutCalories,
    double? bulkCalories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? hydrationL,
    String? cutIntensity,
  }) {
    return UserStaticMetrics(
      bmr: bmr ?? this.bmr,
      tdee: tdee ?? this.tdee,
      maintenanceCalories: maintenanceCalories ?? this.maintenanceCalories,
      cutCalories: cutCalories ?? this.cutCalories,
      bulkCalories: bulkCalories ?? this.bulkCalories,
      proteinG: proteinG ?? this.proteinG,
      carbsG: carbsG ?? this.carbsG,
      fatG: fatG ?? this.fatG,
      hydrationL: hydrationL ?? this.hydrationL,
      cutIntensity: cutIntensity ?? this.cutIntensity,
    );
  }
}

class SetDraft {
  const SetDraft({
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    required this.isWarmup,
    required this.isCompleted,
    required this.rpe,
  });

  final int setNumber;
  final double weightKg;
  final int reps;
  final bool isWarmup;
  final bool isCompleted;
  final double rpe;

  SetDraft copyWith({
    int? setNumber,
    double? weightKg,
    int? reps,
    bool? isWarmup,
    bool? isCompleted,
    double? rpe,
  }) {
    return SetDraft(
      setNumber: setNumber ?? this.setNumber,
      weightKg: weightKg ?? this.weightKg,
      reps: reps ?? this.reps,
      isWarmup: isWarmup ?? this.isWarmup,
      isCompleted: isCompleted ?? this.isCompleted,
      rpe: rpe ?? this.rpe,
    );
  }
}

class WorkoutExerciseDraft {
  const WorkoutExerciseDraft({
    this.exerciseId,
    required this.exerciseName,
    required this.notes,
    required this.targetSets,
    required this.targetReps,
    required this.sets,
  });

  final int? exerciseId;
  final String exerciseName;
  final String notes;
  final int targetSets;
  final int targetReps;
  final List<SetDraft> sets;

  WorkoutExerciseDraft copyWith({
    Object? exerciseId = _unset,
    String? exerciseName,
    String? notes,
    int? targetSets,
    int? targetReps,
    List<SetDraft>? sets,
  }) {
    return WorkoutExerciseDraft(
      exerciseId:
          identical(exerciseId, _unset) ? this.exerciseId : exerciseId as int?,
      exerciseName: exerciseName ?? this.exerciseName,
      notes: notes ?? this.notes,
      targetSets: targetSets ?? this.targetSets,
      targetReps: targetReps ?? this.targetReps,
      sets: sets ?? this.sets,
    );
  }
}

class WorkoutTemplateDraft {
  const WorkoutTemplateDraft({
    this.templateId,
    required this.name,
    required this.description,
    required this.durationMinutes,
    required this.goal,
    required this.exercises,
  });

  final int? templateId;
  final String name;
  final String description;
  final int durationMinutes;
  final String goal;
  final List<WorkoutExerciseDraft> exercises;

  WorkoutTemplateDraft copyWith({
    Object? templateId = _unset,
    String? name,
    String? description,
    int? durationMinutes,
    String? goal,
    List<WorkoutExerciseDraft>? exercises,
  }) {
    return WorkoutTemplateDraft(
      templateId:
          identical(templateId, _unset) ? this.templateId : templateId as int?,
      name: name ?? this.name,
      description: description ?? this.description,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      goal: goal ?? this.goal,
      exercises: exercises ?? this.exercises,
    );
  }

  static const empty = WorkoutTemplateDraft(
    name: '',
    description: '',
    durationMinutes: 0,
    goal: '',
    exercises: [],
  );
}

class WorkoutLogDraft {
  const WorkoutLogDraft({
    this.workoutLogId,
    this.templateId,
    required this.name,
    required this.notes,
    required this.startedAtLabel,
    required this.exercises,
  });

  final int? workoutLogId;
  final int? templateId;
  final String name;
  final String notes;
  final String startedAtLabel;
  final List<WorkoutExerciseDraft> exercises;

  WorkoutLogDraft copyWith({
    Object? workoutLogId = _unset,
    Object? templateId = _unset,
    String? name,
    String? notes,
    String? startedAtLabel,
    List<WorkoutExerciseDraft>? exercises,
  }) {
    return WorkoutLogDraft(
      workoutLogId: identical(workoutLogId, _unset)
          ? this.workoutLogId
          : workoutLogId as int?,
      templateId:
          identical(templateId, _unset) ? this.templateId : templateId as int?,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      startedAtLabel: startedAtLabel ?? this.startedAtLabel,
      exercises: exercises ?? this.exercises,
    );
  }

  static const empty = WorkoutLogDraft(
    name: '',
    notes: '',
    startedAtLabel: '',
    exercises: [],
  );
}

class FoodLogDraft {
  const FoodLogDraft({
    this.foodLogId,
    this.foodId,
    this.logDate,
    this.caloriesPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    required this.foodName,
    required this.quantityGrams,
    required this.mealType,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final String? foodLogId;
  final String? foodId;
  final DateTime? logDate;
  final double? caloriesPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final String foodName;
  final double quantityGrams;
  final MealType mealType;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  FoodLogDraft copyWith({
    Object? foodLogId = _unset,
    Object? foodId = _unset,
    Object? logDate = _unset,
    Object? caloriesPer100g = _unset,
    Object? proteinPer100g = _unset,
    Object? carbsPer100g = _unset,
    Object? fatPer100g = _unset,
    String? foodName,
    double? quantityGrams,
    MealType? mealType,
    double? calories,
    double? protein,
    double? carbs,
    double? fat,
  }) {
    return FoodLogDraft(
      foodLogId:
          identical(foodLogId, _unset) ? this.foodLogId : foodLogId as String?,
      foodId: identical(foodId, _unset) ? this.foodId : foodId as String?,
      logDate: identical(logDate, _unset) ? this.logDate : logDate as DateTime?,
      caloriesPer100g: identical(caloriesPer100g, _unset)
          ? this.caloriesPer100g
          : caloriesPer100g as double?,
      proteinPer100g: identical(proteinPer100g, _unset)
          ? this.proteinPer100g
          : proteinPer100g as double?,
      carbsPer100g: identical(carbsPer100g, _unset)
          ? this.carbsPer100g
          : carbsPer100g as double?,
      fatPer100g: identical(fatPer100g, _unset)
          ? this.fatPer100g
          : fatPer100g as double?,
      foodName: foodName ?? this.foodName,
      quantityGrams: quantityGrams ?? this.quantityGrams,
      mealType: mealType ?? this.mealType,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
    );
  }

  static final empty = FoodLogDraft(
    foodName: '',
    quantityGrams: 100,
    mealType: MealType.snack,
    calories: 0,
    protein: 0,
    carbs: 0,
    fat: 0,
    logDate: DateTime.now(),
  );
}

class DailyNutritionSummary {
  const DailyNutritionSummary({
    required this.targetCalories,
    required this.consumedCalories,
    required this.proteinTarget,
    required this.proteinConsumed,
    required this.carbsTarget,
    required this.carbsConsumed,
    required this.fatTarget,
    required this.fatConsumed,
    required this.hydrationTargetLiters,
    required this.hydrationConsumedLiters,
  });

  final double targetCalories;
  final double consumedCalories;
  final double proteinTarget;
  final double proteinConsumed;
  final double carbsTarget;
  final double carbsConsumed;
  final double fatTarget;
  final double fatConsumed;
  final double hydrationTargetLiters;
  final double hydrationConsumedLiters;

  double get remainingCalories => targetCalories - consumedCalories;

  DailyNutritionSummary copyWith({
    double? targetCalories,
    double? consumedCalories,
    double? proteinTarget,
    double? proteinConsumed,
    double? carbsTarget,
    double? carbsConsumed,
    double? fatTarget,
    double? fatConsumed,
    double? hydrationTargetLiters,
    double? hydrationConsumedLiters,
  }) {
    return DailyNutritionSummary(
      targetCalories: targetCalories ?? this.targetCalories,
      consumedCalories: consumedCalories ?? this.consumedCalories,
      proteinTarget: proteinTarget ?? this.proteinTarget,
      proteinConsumed: proteinConsumed ?? this.proteinConsumed,
      carbsTarget: carbsTarget ?? this.carbsTarget,
      carbsConsumed: carbsConsumed ?? this.carbsConsumed,
      fatTarget: fatTarget ?? this.fatTarget,
      fatConsumed: fatConsumed ?? this.fatConsumed,
      hydrationTargetLiters:
          hydrationTargetLiters ?? this.hydrationTargetLiters,
      hydrationConsumedLiters:
          hydrationConsumedLiters ?? this.hydrationConsumedLiters,
    );
  }

  static const empty = DailyNutritionSummary(
    targetCalories: 0,
    consumedCalories: 0,
    proteinTarget: 0,
    proteinConsumed: 0,
    carbsTarget: 0,
    carbsConsumed: 0,
    fatTarget: 0,
    fatConsumed: 0,
    hydrationTargetLiters: 0,
    hydrationConsumedLiters: 0,
  );
}

class ExerciseSuggestion {
  const ExerciseSuggestion({
    required this.exerciseId,
    required this.name,
    required this.subtitle,
  });

  final int exerciseId;
  final String name;
  final String subtitle;
}

class FoodSuggestion {
  const FoodSuggestion({
    this.foodId,
    required this.name,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.source,
  });

  final String? foodId;
  final String name;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final String source;

  FoodLogDraft applyTo(FoodLogDraft log) {
    final multiplier = log.quantityGrams / 100;
    return log.copyWith(
      foodId: foodId,
      foodName: name,
      caloriesPer100g: caloriesPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
      calories: caloriesPer100g * multiplier,
      protein: proteinPer100g * multiplier,
      carbs: carbsPer100g * multiplier,
      fat: fatPer100g * multiplier,
    );
  }
}

class ConsistencyState {
  const ConsistencyState({
    required this.currentStreak,
    required this.longestStreak,
    required this.weeklyCheckins,
    required this.totalLogs,
  });

  final int currentStreak;
  final int longestStreak;
  final int weeklyCheckins;
  final int totalLogs;

  JimCompanionStage get companionStage {
    if (currentStreak >= 35) {
      return JimCompanionStage.jackedArmorFinal;
    }
    if (currentStreak >= 24) {
      return JimCompanionStage.armored2;
    }
    if (currentStreak >= 16) {
      return JimCompanionStage.armored1;
    }
    if (currentStreak >= 8) {
      return JimCompanionStage.activeBase;
    }
    return JimCompanionStage.softBase;
  }

  ConsistencyState copyWith({
    int? currentStreak,
    int? longestStreak,
    int? weeklyCheckins,
    int? totalLogs,
  }) {
    return ConsistencyState(
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      weeklyCheckins: weeklyCheckins ?? this.weeklyCheckins,
      totalLogs: totalLogs ?? this.totalLogs,
    );
  }
}

class SearchResultItem {
  const SearchResultItem({
    required this.label,
    required this.subtitle,
    required this.category,
  });

  final String label;
  final String subtitle;
  final SearchCategory category;
}

class SearchResultGroup {
  const SearchResultGroup({
    required this.title,
    required this.items,
  });

  final String title;
  final List<SearchResultItem> items;
}

class SearchState {
  const SearchState({
    required this.query,
    required this.groups,
  });

  final String query;
  final List<SearchResultGroup> groups;

  SearchState copyWith({
    String? query,
    List<SearchResultGroup>? groups,
  }) {
    return SearchState(
      query: query ?? this.query,
      groups: groups ?? this.groups,
    );
  }
}

class AppDraftState {
  const AppDraftState({
    required this.session,
    required this.profile,
    required this.metrics,
    required this.template,
    required this.workoutLog,
    required this.foodLogs,
    required this.nutritionSummary,
    required this.consistency,
    required this.search,
  });

  final AuthSession? session;
  final UserProfile profile;
  final UserStaticMetrics metrics;
  final WorkoutTemplateDraft template;
  final WorkoutLogDraft workoutLog;
  final List<FoodLogDraft> foodLogs;
  final DailyNutritionSummary nutritionSummary;
  final ConsistencyState consistency;
  final SearchState search;

  AppDraftState copyWith({
    AuthSession? session,
    UserProfile? profile,
    UserStaticMetrics? metrics,
    WorkoutTemplateDraft? template,
    WorkoutLogDraft? workoutLog,
    List<FoodLogDraft>? foodLogs,
    DailyNutritionSummary? nutritionSummary,
    ConsistencyState? consistency,
    SearchState? search,
  }) {
    return AppDraftState(
      session: session ?? this.session,
      profile: profile ?? this.profile,
      metrics: metrics ?? this.metrics,
      template: template ?? this.template,
      workoutLog: workoutLog ?? this.workoutLog,
      foodLogs: foodLogs ?? this.foodLogs,
      nutritionSummary: nutritionSummary ?? this.nutritionSummary,
      consistency: consistency ?? this.consistency,
      search: search ?? this.search,
    );
  }
}

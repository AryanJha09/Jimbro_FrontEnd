# Frontend profile contract matrix

Evidence used:

- Deployed `GET /api/v1/supabase/profile` OpenAPI response:
  `SuccessResponse[Dict[str, Any]]`.
- Deployed `AtlasProfileUpdate` schema for documented profile field types.
- Frozen backend checkout read-only SQLAlchemy `User` model. That model only
  exposes `user_id`, `username`, `email`, `age`, `height_cm`, `weight_kg`,
  `sex`, `created_at`, and `updated_at`; fields absent from it are marked
  unknown rather than guessed.
- Flutter's canonical GET contract is a flat `{"success": true, "data": {...}}`
  envelope. Nested `data.profile` and `data.user` are unsupported.

| Database column | API JSON key | Dart DTO | Dart domain | DB nullability | API optionality | Dart nullability | Enum converter | Default behaviour |
|---|---|---|---|---|---|---|---|---|
| legacy `id` unknown | `id` | `id` | — | unknown | optional, non-canonical | nullable | — | retained as metadata; never substitutes for `user_id` |
| `user_id` | `user_id` | `userId` | bootstrap result ID | non-null primary key | required by Flutter GET contract | non-null | — | none; missing/invalid is a schema error |
| auth UUID column unknown | `auth_user_id` | `authUserId` | session owns auth identity | unknown | optional | nullable | — | none |
| `email` | `email` | `email` | session owns display email | non-null in frozen model | optional in generic GET response | nullable | — | none; value is never logged |
| `username` | `username` | `username` | `name` | non-null in frozen model | optional in generic GET response | DTO nullable; domain name uses signed-in display name when absent | — | signed-in display name, not a fabricated profile value |
| `age` | `age` | `age` | `age` | nullable | optional/null | nullable | — | none |
| `height_cm` | `height_cm` | `heightCm` | `heightCm` | nullable | optional/null; number or numeric string | nullable | — | none |
| `weight_kg` | `weight_kg` | `weightKg` | `weightKg` | nullable | optional/null; number or numeric string | nullable | — | none |
| `sex` | `sex` | `sex` | `sex` wire value | nullable | optional/null | nullable | `ProfileSex` | none; unsupported non-null value is a schema error |
| unknown | `activity_level` | `activityLevel` | `activityLevel` display label | unknown | optional/null | nullable | `ProfileActivityLevel` | none |
| unknown | `fitness_goal` | `fitnessGoal` | `goal` display label | unknown | optional/null | nullable | `ProfileFitnessGoal` | none |
| unknown | `experience_level` | `experienceLevel` | `userLevel` | unknown | optional/null | nullable | `ProfileExperienceLevel` | none |
| unknown | `available_time_min` | `availableTimeMin` | `availableTimeMinutes` | unknown | optional/null | nullable | — | none |
| unknown | `equipment_access` | `equipmentAccess` | `trainingPreference` display label | unknown | optional/null | nullable | `ProfileEquipmentAccess` | none |
| unknown | `dietary_preference` | `dietaryPreference` | `dietaryPreference` wire value | unknown in frozen model | optional/null in deployed update schema | nullable | `ProfileDietaryPreference` | none; null is not coerced to `omnivore` |
| unknown | `allergies` | `allergies` | — | unknown | not documented by deployed OpenAPI | nullable string list | — | none |
| unknown | `food_availability` | `foodAvailability` | — | unknown | not documented by deployed OpenAPI | nullable string list | — | none |
| unknown | `budget` | `budget` | — | unknown | not documented by deployed OpenAPI | nullable double | — | none |
| unknown | `hostel_mess` | `hostelMess` | — | unknown | not documented by deployed OpenAPI | nullable bool | — | none |
| unknown | `gym_access` | `gymAccess` | — | unknown | not documented by deployed OpenAPI | nullable bool | — | none |
| unknown | `time_of_day` | `timeOfDay` | — | unknown | not documented by deployed OpenAPI | nullable string | no wire enum documented | none |
| unknown | `sleep_quality` | `sleepQuality` | — | unknown | not documented by deployed OpenAPI | nullable string | no wire enum documented | none |
| unknown | `steps` | `steps` | — | unknown | not documented by deployed OpenAPI | nullable int | — | none |
| unknown | `stress_level` | `stressLevel` | — | unknown | not documented by deployed OpenAPI | nullable string | no wire enum documented | none |
| unknown | `constraints_json` | `constraintsJson` | — | unknown | optional/null; array of strings | nullable string list | deployed constraint values validated server-side | null remains null; list is preserved |
| unknown | `onboarding_completed` | `onboardingCompleted` | bootstrap completeness | unknown | optional/null in generic GET response | nullable | — | only literal `true` is complete; false/null routes to onboarding |
| unknown | `profile_status` | `profileStatus` | — | unknown | not documented by deployed OpenAPI | nullable string | no wire enum documented | none |
| `created_at` | `created_at` | `createdAt` | — | generated/non-null in frozen model | optional | nullable `DateTime` | — | strict ISO-8601 parse; no timestamp fallback |
| `updated_at` | `updated_at` | `updatedAt` | cache freshness | generated/non-null in frozen model | optional | nullable `DateTime` | — | strict ISO-8601 parse; absent timestamp does not overwrite a fresh cache entry |

The profile cache in this frontend is memory-only. SharedPreferences stores
workout/onboarding state, and secure storage stores the auth session; neither
serializes `UserProfile`. Consequently, an optional profile cache write cannot
turn bootstrap fatal, and nullable profile fields require no disk-schema
migration.

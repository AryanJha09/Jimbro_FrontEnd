# JimBro Project State

Use this document as the first message or first file reference when a Codex chat becomes too long and needs to continue in a fresh thread.

## Copy-Paste Starter

I am working in `/Users/aryanjha/jimbro`, a Flutter/Riverpod app named JimBro. Please read `PROJECT_STATE.md` first, then check `git status --short` and `git diff --cached --stat` before making changes. There is staged work in progress, including `.env`, so do not overwrite or unstage existing changes unless I explicitly ask. Do not print or copy `.env` values.

Current objective: wire the polished JimBro prototype to real auth/backend flows while keeping mock mode usable. The onboarding experience has been rebuilt as a guided coaching conversation with persistent state, dynamic insights, inference-backed recommendations, and final profile persistence. A reusable JimBro mobile design-system foundation has also been added so screens can move away from slideshow/demo-feeling UI incrementally. Home has now been upgraded into a meaningful coaching dashboard with one primary action, honest empty states, workout/nutrition metric cards, one workout volume chart when real set data exists, target-aware nutrition adherence, coaching insight text, and compact navigation. Workout template management has now been upgraded for MVP: users can create custom templates, add exercises and planned set data, save them, see saved template cards, open a template later, start a workout from it, delete saved templates where the backend supports `DELETE /workout-templates/{templateId}`, assign saved templates to weekdays, see the weekly schedule, start today's scheduled workout from Home, edit the active workout's reps/weight/RPE/sets without mutating the saved template, finish the workout, and send a full nested workout log payload. Nutrition has now been upgraded from single-item logging to a MyFitnessPal-inspired MVP day log with macro summary, meal sections, manual food entry, per-meal add CTAs, editable/deletable existing entries through the current repository flow, correct daily/meal totals, and profile-derived BMR/TDEE/calorie/protein/hydration targets. Profile has now been upgraded into an editable fitness profile with a clean summary, explicit edit/save flow, validation, save confirmation, profile-driven target refresh, read-only calculated calorie/protein/hydration/TDEE targets, and graceful missing-target states.

Latest verification: after TASK 11 Final Deployment QA / Regression Review on 2026-06-07, `flutter analyze` passed with no issues, `flutter test test/widget_test.dart` passed, full `flutter test` passed 25/25 tests, and `flutter build web --release` succeeded. The release web build required sandbox escalation because Flutter writes to its SDK cache outside the repo. Earlier native Android build verification was attempted with `flutter build apk --debug`, but this machine has no Android SDK configured (`ANDROID_HOME` missing). The remaining June 16 work should focus on live auth/backend persistence, confirming live profile/workout-log/nutrition schemas accept the MVP payloads, native-device testing the local notification bridge, and verifying `.env` contains only public/client-safe values because it is bundled as a Flutter asset.

TASK 11 QA fixes applied on 2026-06-07:

- Added a real sign-out path: `AppDraftController.signOut()` clears auth/onboarding/tab state, Profile exposes a `Sign out` action, and `test/widget_test.dart` covers returning to Auth.
- Removed investor-demo unsafe History behavior: the hard-coded bench progression chart/metric grid and no-op `View Full Progress` action were replaced by an honest latest-completed-workout summary or empty state.
- Gated manual History streak mutation controls behind `kDebugMode` so release builds do not expose debug-only progression controls.
- Removed user-visible prototype/demo/auth copy from Auth and neutralized mock-mode identity from seeded Aryan data to generic JimBro user data.
- Reworded mock ATLAS insights so they do not claim fake sleep/training/plateau data; nutrition insight now handles missing or already-met protein targets honestly.

## MVP Execution Protocol

This protocol applies to every JimBro task unless the user explicitly overrides it.

- Investor deadline: June 16.
- Quality target: deploy-ready MVP, not prototype/demo.
- Required workflow: inspect -> plan -> implement -> review.
- Preserve existing working functionality by default: auth, onboarding access, workout logging, food logging, routing, backend payload shapes, and database models.
- Treat the current dirty repo state as intentional user-owned work unless the task specifically targets those files.
- Prefer small, production-safe, testable diffs over broad rewrites.
- Do not refactor unrelated code, especially in `app_state.dart`, `app_repositories.dart`, routing, repositories, or feature pages.
- Keep JimBro human-centric, polished, mobile-first, simple, and coach-like.
- Avoid spreadsheet-style clutter, speculative polish, and unnecessary fitness jargon.
- Add validation, empty states, and graceful error states only where directly relevant to the task.
- Keep debug/demo/dev-only behavior behind `kDebugMode`; it must not leak into release flows.

Before editing code, identify the exact ownership boundary involved:

- UI state
- Controller/provider
- DTO or payload builder
- Repository or API client
- API response mapping
- Backend schema or database behavior, when applicable

For backend-related bugs:

- Verify live API/OpenAPI/schema when available before changing request payloads.
- If live backend schema conflicts with docs, live OpenAPI/schema wins.
- Keep request/response field names aligned exactly.
- Add debug-only diagnostics that reveal useful payload/error details without exposing secrets.

For UI work:

- Reuse existing JimBro components and theme first.
- Keep the first screen focused.
- Optimize for trust, completion rate, personalization, coaching feel, and learning experience.

For tests and review:

- Add focused coverage at the boundary that failed: state object, payload builder, repository adapter, widget flow, or controller persistence.
- Run `flutter analyze` after code changes.
- Run targeted tests for the changed behavior, then `flutter test` when feasible.
- Finish with a self-review covering files changed, behavior changed, verification commands/results, risks or follow-ups, and confirmation that unrelated auth/backend/database/routing behavior was not touched when applicable.

## Current Snapshot

- App: Flutter fitness coaching platform with Riverpod state management.
- Product direction: JimBro is a warm AI-ready coaching experience with onboarding, home insights, workout logging, nutrition logging, profile/history/consistency flows, and a companion avatar progression. It is not just a workout tracker.
- Architecture:
  - `main.dart` loads `.env`, builds `AppConfig`, initializes Supabase when configured, and starts `JimBroApp`.
  - `AppConfig` supports `APP_BACKEND_MODE=mock|fastapi` and `AUTH_MODE=fastApi|supabase`.
  - `AppDraftController` in `lib/core/navigation/app_state.dart` owns the draft app state and coordinates repositories.
  - `lib/core/repositories/app_repositories.dart` contains repository interfaces plus mock, FastAPI, and Supabase-backed implementations.
  - UI pages consume `appDraftProvider` and related FutureProviders for insights/search/actions.
  - Reusable UI primitives live under `lib/shared/components/`, with design tokens in `lib/core/theme/jim_tokens.dart` and `lib/core/theme/jim_theme.dart`.

## June 16 Audit Snapshot

Last audited: 2026-06-07. The latest code changes were TASK 9: Dashboard / Progress Insights.

Verification from audit:

- `flutter analyze` passed with no issues.
- `flutter test` passed, 16/16 tests.
- Post-audit design-system pass also passed `flutter analyze` and `flutter test` on 2026-06-06.
- Post-Home-redesign pass also passed `flutter analyze`, `flutter test test/widget_test.dart`, and `flutter test` on 2026-06-06.
- Post-Workout-Templates-MVP pass also passed `flutter analyze`, `flutter test test/workout_log_flow_test.dart`, `flutter test test/widget_test.dart`, and full `flutter test` on 2026-06-06. Full test count is now 18/18.
- Post-Workout-Scheduling pass also passed `flutter analyze`, `flutter test test/workout_log_flow_test.dart`, `flutter test test/widget_test.dart`, and full `flutter test` on 2026-06-06. Full test count is now 19/19. `flutter build apk --debug` could not complete because no Android SDK is configured on this machine.
- Post-Workout-Execution-Logging pass also passed `flutter analyze`, `flutter test test/workout_log_flow_test.dart`, `flutter test test/widget_test.dart`, and full `flutter test` on 2026-06-07. Full test count is now 20/20.
- Post-Nutrition-Logging-MVP pass also passed `flutter analyze`, `flutter test test/widget_test.dart`, and full `flutter test` on 2026-06-07. Full test count remains 20/20.
- Post-TDEE/Protein/Hydration-Targets pass also passed `flutter analyze`, `flutter test test/nutrition_targets_test.dart`, and full `flutter test` on 2026-06-07. Full test count is now 24/24.
- Post-Dashboard/Progress-Insights pass also passed `flutter analyze`, `flutter test test/widget_test.dart`, and full `flutter test` on 2026-06-07. Full test count remains 24/24.
- Post-Profile-Section-Upgrade pass also passed `flutter analyze`, `flutter test test/widget_test.dart test/nutrition_targets_test.dart`, and full `flutter test` on 2026-06-07. Full test count remains 24/24.
- The repo was dirty before the audit. Treat existing modified/staged/untracked files as intentional user-owned work.

Current capability map:

- Working: boot/splash, auth gate, onboarding gate, bottom tab shell, mock auth, email auth code paths, Supabase direct auth code path, profile sign out, guided onboarding persistence/validation/resume, final onboarding-to-profile update, focused Home coaching dashboard with workout/nutrition metric cards, training streak, next scheduled workout, honest recent-volume chart, target-aware nutrition adherence, coaching text, and new-user CTAs, workout draft editing, exercise search, workout template management in mock/local app state, workout template/log save payload builders, saved workout template cards, open/start-from-template flow, active workout execution editing for reps/weight/RPE/sets, finish-workout state, weekly workout schedule assignment, today's scheduled workout on Home, scheduled-start flow from Home/controller, local notification permission/result handling, MyFitnessPal-inspired nutrition day log with calorie/protein/carbs/fat summary, meal sections, per-meal add CTAs, manual food entry, grouped meal totals, profile-derived BMR/TDEE/calorie/protein/hydration targets, food search as optional convenience, nutrition save payload builders, shared JimBro theme/components/design-system primitives, current widget/controller/repository tests.
- Partial: live backend integration is implemented but not live-verified in this audit; workout log payload now sends `started_at`, `ended_at`, `duration_minutes`, `workout_exercises`, nested `sets`, and a legacy `exercises` alias for compatibility, but the live FastAPI/DB schema must still be verified; nutrition logging uses existing food/food-log endpoints and existing edit/delete behavior, but live FastAPI/DB support for create-food plus log save/read/delete should still be verified; workout schedule persistence uses a clean expected `/workout-schedule` FastAPI route and falls back to local `SharedPreferences` if the backend route is unsupported/unavailable; local notifications are bridged natively but still need device/native build verification; profile save now attempts the full MVP fitness profile payload (`sex`, `fitness_goal`, `activity_level`, `experience_level`, `dietary_preference`, `available_time_min`, `training_preference`) and retries the legacy four-field payload if an older backend rejects it, so live persistence of the expanded fields still needs schema verification; Home dashboard analytics use current draft state only until richer backend history exists; Home/History/Nutrition still use honest mock ATLAS text until live AI is wired; hydration target is calculated from profile and hydration consumed still updates local state only; progression/history now shows an honest latest completed workout summary or empty state until richer workout history aggregation exists.
- Missing: real ATLAS/chat/agent endpoints in UI, real progression analytics from workout history, production Google/Apple/phone auth, register/invite flow UI, account management beyond sign out, custom meals/meals/splits flows, production release docs/config checklist.
- Broken or investor-demo unsafe: no critical UI/demo-data blockers remain from the repo-only QA pass after Task 11 fixes. Remaining investor risk is unverified live backend/device behavior, especially auth/profile/workout/nutrition persistence, schedule backend support, native notification behavior, and release `.env` contents.

Critical blockers before deployment:

- Prove one live end-to-end path: Supabase or FastAPI email login -> onboarding save -> reload -> template save -> start/finish workout save -> nutrition save.
- Verify live FastAPI workout log schema accepts the finished-workout payload: `name`, `template_id`, `notes`, `started_at`, `ended_at`, `duration_minutes`, `workout_exercises[]`, nested `sets[]`, `reps`, `weight_kg`, `is_warmup`, and `rpe`. The frontend also sends `exercises` as a compatibility alias; remove or gate that alias only if live schema rejects extra fields.
- Confirm `FASTAPI_BASE_URL` includes the correct `/api/v1` base, because Flutter calls paths like `/auth/login` while backend docs list `/api/v1/auth/login`.
- Re-run a release-copy scan before the demo; Task 11 removed the known Auth/History prototype/demo copy and no-op progress action.
- Keep History on honest latest-workout/empty-state data until richer backend progression analytics exist.
- Close the profile persistence gap or explicitly scope MVP profile persistence to backend-supported fields.
- Keep all service-role/backend secrets out of Flutter `.env`; Flutter should only contain public/client-safe config such as Supabase anon key.
- Continue migrating screens onto the shared design-system primitives instead of creating one-off page shells/cards.

Recommended implementation order, highest investor value first:

1. Live auth/session smoke test and session error cleanup.
2. Onboarding completion persistence: save all MVP profile fields if backend supports them, or clearly persist/display only the supported subset.
3. Workout live save/read verification for templates and finished workout logs, including full nested exercise/set persistence.
4. Nutrition live save/read verification for food logs and daily summary.
5. Workout schedule live save/read verification, including whether the backend supports `/workout-schedule`.
6. Native device verification for local workout notifications on Android/iOS, including permission denied behavior.
7. Re-run release-copy/no-op scan after any UI changes; Task 11 removed the known Auth/History issues.
8. Add richer real progression analytics only after backend workout-history aggregation is proven.
9. Add basic account/session recovery if time allows.
10. Final QA across clean install, mock mode, live mode, mobile layout, native reminders, `flutter analyze`, and `flutter test`.

Recommended June 16 MVP scope:

- Ship a polished mobile-first app with email/Supabase auth, persisted onboarding, home dashboard, workout template/log save, food log save with summary, profile display/edit for supported fields, simple real progression/consistency view, and mock ATLAS presented as coaching insight until live AI is wired.
- Keep Google/Apple auth, phone auth, full chat, custom meals, splits, and advanced analytics out of MVP unless backend readiness is proven early.

What must not be touched for this MVP:

- Do not broadly rewrite routing, Riverpod app state, repositories, or page architecture.
- Do not change backend request/response field names without checking live OpenAPI/schema.
- Do not remove mock mode.
- Do not print, paste, summarize, or churn `.env` values.
- Do not modify native platform folders unless release packaging specifically requires it.
- Do not weaken onboarding principles or reintroduce giant forms/demo seed data.

## Product And Onboarding Principles

Treat these as implementation constraints for onboarding and coaching UX:

- JimBro is a fitness coaching platform, not just a workout tracker.
- Onboarding should feel conversational, not interrogative.
- Onboarding should feel like a first coaching session.
- Educate before asking.
- Keep screens outcome-focused.
- Minimize friction and keep language simple.
- Ask one question per screen.
- Avoid giant forms.
- Avoid fitness jargon.
- Avoid medical advice.
- Avoid injury screening.
- Do not ask questions the product cannot act upon.
- The user should feel understood, not profiled.
- Every onboarding screen should provide value.
- Total onboarding time should stay under 90 seconds.
- Quality bar should feel closer to Headspace, Duolingo, MyFitnessPal, and Hevy than a generic intake form.

Prioritize implementation decisions in this order:

1. User trust
2. Completion rate
3. Personalization
4. Coaching feel
5. Learning experience

Do not simplify these requirements, replace personalization with generic text, or introduce fitness jargon.

## Current Staged Work

As of this handoff, the repo has intentional staged and unstaged work. Always run `git status --short` before edits and inspect targeted diffs. `.env` is staged and sensitive.

Staged modifications include:

- `.env`
- `lib/core/navigation/app_state.dart`
- `lib/core/repositories/app_repositories.dart`
- `lib/core/theme/jim_theme.dart`
- `lib/features/nutrition/presentation/nutrition_page.dart`
- `lib/features/onboarding/presentation/onboarding_page.dart`
- `lib/features/workouts/presentation/workouts_page.dart`
- `lib/shared/models/app_models.dart`
- `test/widget_test.dart`

Unstaged/design-system/workout-execution-related modifications include:

- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/example/jimbro/MainActivity.kt`
- `android/app/src/main/kotlin/com/example/jimbro/WorkoutNotificationReceiver.kt`
- `ios/Runner/AppDelegate.swift`
- `lib/core/notifications/workout_notification_service.dart`
- `lib/core/navigation/app_state.dart`
- `lib/core/repositories/app_repositories.dart`
- `lib/core/theme/jim_tokens.dart`
- `lib/core/theme/jim_theme.dart`
- `lib/shared/models/app_models.dart`
- `lib/shared/components/backend_state_view.dart`
- `lib/shared/components/jim_button.dart`
- `lib/shared/components/jim_surface.dart`
- `lib/shared/components/metric_tile.dart`
- `lib/shared/components/section_header.dart`
- `lib/shared/components/jim_page_scaffold.dart`
- `lib/features/home/presentation/home_page.dart`
- `lib/features/nutrition/presentation/nutrition_page.dart`
- `lib/features/workouts/presentation/workouts_page.dart`
- `test/workout_log_flow_test.dart`

High-level active changes:

- Onboarding has been rebuilt from a form-like setup into a guided coaching conversation covering welcome, goal, motivation, experience, insight #1, activity level, available time, training preference, insight #2, dietary preference, age, sex, height, weight, and coach summary.
- `UserProfile` now includes `sex`, `availableTimeMinutes`, `activityLevel`, and `goalTimeframe`.
- `lib/shared/models/onboarding_models.dart` adds onboarding DTOs, state models, persistence models, enums, JSON helpers, and future-safe `extra` fields.
- `lib/features/onboarding/application/onboarding_controller.dart` adds persistent Riverpod onboarding state with `SharedPreferences`, resume repair, validation, completion state, and recoverable local storage.
- `lib/features/onboarding/presentation/onboarding_page.dart` now uses card-based one-question screens, smooth transitions, dynamic insight generation, number wheel pickers, inference-backed summary generation, and final profile persistence.
- Mock defaults were changed to empty-first data so onboarding and logging begin from a clean user state instead of seeded Aryan/demo data.
- Auth/session diagnostics were made more explicit for protected actions, especially workout template save, workout log save, and nutrition save.
- Supabase auth header creation now treats Supabase sessions separately from mock/FastAPI sessions and refuses to send stale/missing tokens.
- FastAPI profile load/save now surfaces response-shape diagnostics and falls back when the backend indicates a missing Supabase service key.
- Workout and nutrition pages were reorganized into ordered workflows and expose more technical save errors in dialogs/messages for backend debugging.
- Workout Templates MVP was added after the Home redesign. `AppDraftState` now carries both the active `template` and a `templates` list. `WorkoutRepository` now exposes `loadTemplates`, `loadTemplate`, `saveTemplate`, `deleteTemplate`, `loadWorkoutLog`, `saveWorkoutLog`, and exercise search. Mock workout repository now stores multiple templates with generated local IDs. FastAPI workout repository still uses existing `/workout-templates` endpoints: `GET /workout-templates`, `POST /workout-templates`, `PATCH /workout-templates/{templateId}`, and `DELETE /workout-templates/{templateId}`.
- Workout Scheduling MVP was added after the template MVP. `WorkoutScheduleEntry` models `schedule_id`, `user_id`, `template_id`, `template_name`, `weekday`, `time`, `repeat_weekly`, and `active`. `AppDraftState` now carries `workoutSchedule`. `WorkoutRepository` now exposes `loadSchedule`, `saveScheduleEntry`, and `deleteScheduleEntry`. Mock workout repository stores schedule entries in memory. FastAPI workout repository tries `GET /workout-schedule`, `POST /workout-schedule`, `PATCH /workout-schedule/{scheduleId}`, and `DELETE /workout-schedule/{scheduleId}`; if the route is 404/405 or load/save is recoverably unavailable, it falls back to `LocalWorkoutScheduleStore` backed by `SharedPreferences`.
- Scheduling behavior is MVP-simple: one active template per weekday, repeated weekly. Assigning a new template to an already-scheduled weekday updates that day instead of creating duplicates, which also avoids notification spam.
- `AppDraftController` now supports `scheduleWorkoutTemplate`, `deleteWorkoutSchedule`, and `startScheduledWorkout`. Scheduling requires a saved template with a `templateId`, persists the schedule through the repository, then asks the notification service to schedule a local reminder. Deleting a schedule cancels the reminder. Deleting a template also cancels and removes schedules that reference that template.
- `lib/features/workouts/presentation/workouts_page.dart` now includes a weekly schedule panel above the template builder. It shows Monday-Sunday rows, lets users choose a saved template for a day, set a local reminder time through `showTimePicker`, and clear a scheduled day.
- `lib/features/home/presentation/home_page.dart` now checks today's active weekly schedule first. If a schedule exists for the current weekday, Home shows the scheduled template/time and the primary CTA starts that scheduled workout before switching to the Workouts tab.
- Local notification behavior is implemented through `lib/core/notifications/workout_notification_service.dart` plus native MethodChannel bridges. Permission is requested only when scheduling a reminder. If permission is denied or the bridge is unavailable, the schedule still saves and the app reports that reminders are off/unavailable. Android uses `POST_NOTIFICATIONS`, `AlarmManager`, a notification channel, and `WorkoutNotificationReceiver`; iOS uses `UNUserNotificationCenter` weekly calendar triggers. No Google/Apple Calendar integration exists.
- Template payloads now send `name`, `description`, and `exercises[]` with `exercise_id`, `order_index`, `target_sets`, `target_reps`, `notes`, and planned `sets[]` when present. Planned set fields sent are `set_number`, `reps`, `weight_kg`, and `rpe` when greater than zero. The template mapper reads `template_exercises` or `exercises`, and reconstructs planned sets from `sets` or `planned_sets` if the backend returns them.
- `WorkoutLogDraft` now has `endedAtLabel` and an `isInProgress` getter. Active workout state is represented by a non-empty `startedAtLabel` and an empty `endedAtLabel`.
- `AppDraftController` now supports `createTemplateDraft`, `openWorkoutTemplate`, `startWorkoutFromTemplate`, `saveWorkoutTemplate`, and `deleteWorkoutTemplate`. Starting from a template creates a fresh `WorkoutLogDraft` with `templateId`, template name, current ISO `startedAtLabel`, empty `endedAtLabel`, and execution-ready copied exercises/sets. If a template exercise has no planned sets, start creates sets from `targetSets`/`targetReps` so the workout still has editable rows.
- Template builder edits now sync into the workout log only while the workout log is idle. Once a workout is in progress, template edits no longer overwrite the active workout execution draft.
- `AppDraftController` now has workout-execution-specific methods: `updateWorkoutExercise`, `applyWorkoutExerciseSuggestion`, `updateWorkoutSet`, `addWorkoutSet`, and `removeWorkoutSet`. Updating a live workout set marks it completed. Removing workout sets renumbers remaining sets.
- Finishing/logging a workout now stamps `endedAtLabel` if missing, preserves the original `startedAtLabel`, calculates duration in the repository from start/end, and saves the active `workoutLog` instead of rebuilding the log from the template. This prevents dropping modified reps/weight/RPE/sets.
- FastAPI workout log save now builds a full finished-workout payload with `name`, `template_id`, `notes`, `started_at`, `ended_at`, `duration_minutes`, `workout_exercises[]`, nested `sets[]`, `set_number`, `reps`, `weight_kg`, `is_warmup`, and `rpe`. It also sends the same nested list under `exercises` as a compatibility alias for the previous endpoint contract. The mapper reads `workout_exercises` first, then falls back to `exercises`.
- `lib/features/workouts/presentation/workouts_page.dart` now has a saved-template library above the builder: empty state text is “Create your first workout template.”, CTA is “Create Template”, saved templates appear as cards with Open, Start, and Delete actions, and the existing exercise builder/logging flow remains below.
- `lib/features/workouts/presentation/workouts_page.dart` now shows an active workout execution panel after Start. The panel displays the workout name, exercise/set count, session notes, editable exercise rows, editable set kg/reps/RPE fields, Add Set, Remove Set, and Finish Workout. During execution, exercises are fixed to the started workout rather than removable from the template builder, while set editing remains available.
- `test/workout_log_flow_test.dart` now covers the acceptance paths: template created -> saved -> visible later -> opened -> can start workout from it; saved template -> scheduled for Monday -> notification service called -> scheduled workout can start; started workout -> edit reps/weight/RPE -> add/remove sets -> finish -> repository captures full workout details without truncating the name or mutating the saved template. It also verifies the FastAPI template payload includes planned fields and that workout log payloads include timing plus `workout_exercises`. `test/widget_test.dart` expects the new Workouts page title `Workout templates` and the first-template empty state, and scrolls before editing the template name because the schedule panel pushes the builder lower in the `ListView`.
- Design system foundation added/upgraded: spacing/radius/elevation tokens, typography cleanup, `JimPageScaffold`, `JimSurfaceTone`, `JimInteractiveSurface`, stronger primary/secondary/text buttons, section header subtitles, `JimMetricCard`, `JimCtaPanel`, and shared empty/loading/error state cards.
- Workouts and Nutrition now use `JimPageScaffold` and shared empty/metric states.
- Home has been redesigned around a single hero CTA, today focus, workout prompt, compact nutrition snapshot, one coaching insight card, and minimal icon navigation to workout/nutrition/progress/profile. It handles empty/new users, existing workout/template drafts, no nutrition targets/logs, available calories/protein progress, and insight loading/error/data states. The old Home prompt overlay and cluttered daily-state grid were removed.
- TASK 9 dashboard insights were added to Home without changing repository/backend contracts. Metric definitions/data sources: workouts this week = latest completed workout log only if its `endedAtLabel` is in the current Monday-Sunday week; training streak = `ConsistencyState.currentStreak`; recent volume = sum of `weightKg * reps` from the latest completed workout's sets, grouped by exercise, shown only when real set data exists; next scheduled workout = nearest active repeated `WorkoutScheduleEntry`; calories/protein today = `DailyNutritionSummary` consumed vs target values; weekly adherence snapshot = `ConsistencyState.weeklyCheckins` when available, otherwise explicitly says weekly food history is not available yet. Empty states CTA to Workouts/Nutrition instead of faking history.
- Nutrition Logging MVP was added after workout execution polish. `lib/features/nutrition/presentation/nutrition_page.dart` now shows a daily macro summary at the top, calorie/protein progress, carbs/fat totals, breakfast/lunch/dinner/snack sections, empty states, and add-food CTAs per meal. Manual entry remains the primary path: food name, quantity, calories, protein, carbs, fat, and meal type.
- `AppDraftController.addFoodLog` now accepts an optional `MealType` so meal CTAs create entries in the correct section. Daily nutrition totals still rebuild by summing logged food `calories`, `protein`, `carbs`, and `fat`. `DailyNutritionSummary.remainingProtein` was added; when no calorie/protein target exists, the UI shows logged totals instead of confusing negative remaining values.
- TASK 8 nutrition targets were added after the nutrition logging MVP. `lib/core/nutrition/nutrition_targets.dart` calculates guidance estimates from `UserProfile`: BMR by Mifflin-St Jeor; TDEE by activity multiplier; calorie target by goal; protein target by practical g/kg bodyweight range; hydration by 35ml/kg bodyweight. Assumptions: 15% fat-loss deficit, 10% muscle-gain surplus, 5% strength surplus, maintenance for general health/consistency, activity multipliers 1.2/1.375/1.55/1.725/1.45 for sitting/light/moderate/very/variable, and sex `Prefer not to say` uses a midpoint Mifflin constant. Missing age/sex/height/weight produces zero targets rather than invented estimates.
- `UserProfile` now includes `dietaryPreference`; `UserStaticMetrics` now includes `targetCalories`. On onboarding completion, dietary preference is copied into the app profile. `AppDraftController` recalculates metrics/summary targets when profile data loads or changes, and clears derived targets if required profile fields are removed. `DailyNutritionSummary` gets target calories, protein, carbs, fat, and hydration from calculated metrics while consumed food totals still come from logged foods.
- Nutrition/Home/Profile now surface the calculated targets: Nutrition shows calories/protein progress plus a BMR/TDEE guidance note; Home's nutrition snapshot uses the same target-aware summary; Profile shows age/height/weight plus sex/activity/dietary preference inputs and BMR/TDEE/target kcal/protein/carbs/fat/hydration fields. Copy explicitly frames estimates as guidance, not medical advice.
- TASK 10 Profile Section Upgrade completed on 2026-06-07. Profile now uses the shared page/surface/button/metric components, has a concise profile summary, a single edit form, validation for required text plus age/height/weight/available-time ranges, explicit save confirmation, and read-only calculated calorie/protein/hydration/TDEE cards. `UserProfile` now has `trainingPreference`; onboarding completion stores it from the guided onboarding answer; profile edits save it separately from `coachingPreference`. FastAPI profile load accepts `available_time_min` or legacy `available_time_minutes`; save attempts expanded MVP fields and falls back to the legacy payload on 400/422 to avoid breaking older profile endpoints.
- Nutrition backend/API shape was intentionally not changed. Existing FastAPI nutrition repository behavior remains the contract: `GET /food-log`, `GET /food-log/summary/{date}`, optional `GET /food/search`, `POST /food` for custom/manual foods when needed, `POST /food-log`, safe quantity-only `PATCH /food-log/{id}`, and `DELETE /food-log/{id}` for removed saved entries. Live verification is still required.
- Widget tests were updated for empty-first data and the full guided onboarding flow.
- Widget tests now cover the redesigned Home dashboard and primary CTA path. They also cover manual nutrition logging across breakfast and lunch, grouped meal totals, and target-aware daily calorie/protein/carbs/fat totals. Findings: because Home now repeats bottom-nav icons in its minimal navigation row, tests that tap by icon must target the bottom nav instance with `.last` or a more specific finder; nutrition tests may need explicit scroll helpers because meal sections and editors are lazily built inside the `ListView`.
- `test/nutrition_targets_test.dart` covers muscle-gain estimates, fat-loss estimates, missing-profile graceful handling, and controller-level profile-change target refresh.
- `test/onboarding_controller_test.dart` covers persistence, resume repair, and completion validation.
- `shared_preferences` is now a direct dependency for onboarding progress persistence.

## Files To Inspect First

- `lib/core/repositories/app_repositories.dart`: auth, profile, workout, nutrition, consistency, ATLAS/search repositories; FastAPI/Supabase request mapping; auth header and diagnostics helpers.
- `lib/core/navigation/app_state.dart`: Riverpod app state controller, session replacement, onboarding detection, draft updates, protected save/session requirements.
- `lib/core/nutrition/nutrition_targets.dart`: profile-derived BMR/TDEE/calorie/protein/hydration formulas and MVP assumptions.
- `lib/shared/models/app_models.dart`: core models, especially `AuthSession`, `UserProfile`, `UserStaticMetrics`, workout drafts, food logs, nutrition summary, consistency state, and app draft state.
- `lib/features/onboarding/application/onboarding_controller.dart`: persistent onboarding navigation, validation, resume, recovery, and completion state.
- `lib/features/onboarding/presentation/onboarding_page.dart`: guided onboarding UI, dynamic insights, inference summary, wheel pickers, final app profile save.
- `lib/shared/models/onboarding_models.dart`: onboarding DTO/state/persistence models and enums.
- `lib/features/workouts/presentation/workouts_page.dart`: workout template library, weekly schedule panel, first-template empty state, create/open/start/delete card actions, active workout execution panel, template builder, finish/log workout UI, and technical save error dialog.
- `lib/features/nutrition/presentation/nutrition_page.dart`: MyFitnessPal-inspired nutrition day log, target-aware daily macro summary, BMR/TDEE guidance note, meal sections, per-meal add CTAs, manual food editor, grouped totals, hydration stepper, nutrition save handling.
- `lib/features/profile/presentation/profile_page.dart`: profile/body inputs and calculated static nutrition metrics display. Profile still has some debug/dev controls behind `kDebugMode`.
- `lib/features/home/presentation/home_page.dart`: focused coaching dashboard, scheduled workout detection/start, primary CTA selection, workout/nutrition empty states, one insight card, and minimal tab navigation.
- `lib/core/notifications/workout_notification_service.dart`: local workout reminder abstraction, permission-safe MethodChannel service, reminder result statuses, and weekday labels.
- `android/app/src/main/kotlin/com/example/jimbro/MainActivity.kt`, `android/app/src/main/kotlin/com/example/jimbro/WorkoutNotificationReceiver.kt`, `android/app/src/main/AndroidManifest.xml`, and `ios/Runner/AppDelegate.swift`: native notification bridge. Native compile/device verification is still pending because this machine lacks an Android SDK.
- `lib/core/theme/jim_tokens.dart` and `lib/core/theme/jim_theme.dart`: JimBro colors, spacing/radius/elevation tokens, typography, inputs, cards, chips.
- `lib/shared/components/jim_page_scaffold.dart`: reusable mobile page scaffold, CTA panel, and empty/loading/error state cards.
- `lib/shared/components/jim_surface.dart`, `jim_button.dart`, `section_header.dart`, `metric_tile.dart`, `backend_state_view.dart`: shared card/button/header/metric/backend-state primitives.
- `lib/core/config/app_config.dart`: backend/auth mode and environment variable parsing.
- `lib/core/network/jim_api_client.dart`: Dio base configuration and timeouts.
- `test/widget_test.dart`: current widget coverage and assumptions for onboarding, navigation, nutrition, workouts, and consistency.
- `test/nutrition_targets_test.dart`: formula and controller refresh coverage for BMR/TDEE/calorie/protein/hydration targets.
- `test/workout_log_flow_test.dart`: workout repository/controller coverage, including finished workout log payloads, template create/save/open/start behavior, live workout set editing, finish-workout behavior, schedule start behavior, and planned template payload fields.
- `BACKEND DOCUMENTATION.docx`: backend contract reference. Render or inspect this before changing request payloads or endpoint assumptions.

## Environment Notes

Do not print, paste, commit, or summarize actual `.env` values. Only refer to variable names unless the user explicitly asks for secret handling.

Known environment variables used by the Flutter app:

- `APP_BACKEND_MODE`
- `AUTH_MODE`
- `FASTAPI_BASE_URL`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_REDIRECT_SCHEME`
- `SUPABASE_REDIRECT_HOST`

Important behavior:

- Mock mode should remain usable without live backend services.
- FastAPI mode depends on `FASTAPI_BASE_URL`.
- Supabase direct auth depends on valid `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- Protected FastAPI requests expect a usable bearer token.
- The staged `.env` change exists; inspect status, not contents, unless the user explicitly requests secret-safe validation.

## Known Risks And Open Threads

- `.env` is staged. Treat it as sensitive and do not expose values.
- Live save flows depend on the backend accepting the bearer token generated by the current auth path.
- The frontend has diagnostics for missing sessions and rejected tokens, but repeated failures likely require checking Supabase project/JWT settings and FastAPI auth middleware.
- Profile load/save falls back for a backend missing-service-key condition, but that is a backend configuration problem to resolve before relying on live profile persistence.
- Nutrition targets are derived locally from profile fields and are not a changed backend contract. Live profile persistence currently saves only `username`, `age`, `height_cm`, and `weight_kg`; verify or add backend support before relying on persisted `sex`, `activity_level`, and `dietary_preference` across live reloads.
- The formula output is guidance only, not medical advice. Preserve that framing in copy and do not add clinical claims or injury/medical screening.
- Guided onboarding saves each answer locally immediately and saves the app profile at the final summary step.
- The onboarding flow now avoids giant forms by using one-question screens and card/wheel interactions.
- Empty-first mock data changes test expectations and first-run UX; do not reintroduce seeded demo data unless requested.
- Home is now intentionally CTA-led and uncluttered. Avoid reintroducing multi-card dashboard grids, demo/prototype copy, or multiple competing primary actions.
- The redesigned Home uses the same icons as the bottom nav for its minimal navigation row; widget tests should use scoped finders or `.last` when the goal is the persistent bottom navigation.
- Backend endpoint and payload assumptions should be checked against `BACKEND DOCUMENTATION.docx` before altering request mappings.
- Workout template list/open/start is covered in mock mode and repository tests. Live backend still needs verification that `GET /workout-templates` returns all user templates, that POST/PATCH accept `target_sets`, `target_reps`, and optional planned `sets`, and that `DELETE /workout-templates/{templateId}` exists. If the backend rejects planned set fields, prefer feature-detecting/falling back rather than removing the UI.
- Workout execution/logging is covered in mock/controller/repository tests, but live DB persistence still needs verification. Confirm the backend stores `started_at`, `ended_at`, `duration_minutes`, nested workout exercises, nested sets, `reps`, `weight_kg`, `is_warmup`, and `rpe`. The frontend currently sends both `workout_exercises` and `exercises` for compatibility; if FastAPI forbids extra fields, update the repository mapping after checking live OpenAPI/schema rather than changing UI/controller logic.
- Starting from a template now protects the saved template from live workout edits. Future work should preserve this separation; do not route execution set edits through template-update methods.
- Template delete is implemented only through the existing expected REST endpoint. If live backend does not support delete, hide or gracefully disable Delete for release rather than breaking template creation/logging.
- Workout schedule persistence expects a backend model/API with `template_id`, `user_id`, `weekday`, `time`, `repeat_weekly`, and `active`. The app currently uses `/workout-schedule` and falls back locally if unsupported. Before relying on live persistence, verify the backend route names and response shape. If the backend chooses a different path, update only the repository mapping.
- Local notification native code has passed Dart analysis/tests but not native compilation on this machine. Android build failed because `ANDROID_HOME` is missing. Run a real Android/iOS build and device test before investor demo. Confirm permission-denied flow saves the schedule without reminders and does not crash.
- The schedule panel adds vertical content above the workout builder. Widget tests or manual flows that access builder fields may need to scroll.
- Design-system migration is intentionally partial. Do not redesign every screen at once; adopt shared primitives screen-by-screen while preserving business logic and routing.

## Fresh Chat Workflow

1. Read this file.
2. Run `git status --short`.
3. Run `git diff --cached --stat`.
4. Follow the MVP Execution Protocol: inspect -> plan -> implement -> review.
5. Inspect targeted staged diffs with `git diff --cached -- <path>` before editing touched files.
6. Avoid modifying or reverting staged work unless it is necessary for the user request.
7. Never print `.env` values.
8. Prefer focused edits that keep mock mode and live backend mode both working.
9. Run `flutter analyze` after code changes.
10. Run targeted tests for changed behavior, then `flutter test` when feasible.

## Maintenance Checklist

Update this document whenever:

- A major objective changes.
- The staged/active file list changes materially.
- Backend endpoint assumptions or auth mode behavior changes.
- New high-risk files become central to the next task.
- A bug is found that a fresh chat must know before making edits.

Keep the document concise, current, and secret-safe.

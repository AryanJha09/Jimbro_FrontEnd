# JimBro Project State

Use this file as the first reference when continuing work in a fresh Codex thread.

## Starter Context

I am working in `/Users/aryanjha/jimbro`, a Flutter/Riverpod app named JimBro. Before changing code, read this file, run `git status --short`, and run `git diff --cached --stat`.

The repo is intentionally dirty and has work in progress, including `.env`. Do not overwrite, unstage, revert, or churn user-owned work unless explicitly requested. `.env` is sensitive; do not print, paste, summarize, or copy its values.

Current goal: keep the polished MVP stable while finishing live backend/device verification and resolving the remaining backend Atlas onboarding contract mismatch. Mock mode must remain usable.

Production backend is deployed on Render at `https://jimbro-uvi6.onrender.com/`. Flutter `FASTAPI_BASE_URL` should point to the same host with `/api/v1`.

## Current Status

JimBro is now a mobile-first fitness coaching MVP with:

- Guided one-question onboarding with persistent progress, validation, resume repair, dynamic coaching insights, required database-safe dietary preference, and final profile persistence.
- Onboarding/profile consistency hardening: completed onboarding becomes the canonical local profile for Profile, Nutrition, Workout, and Home; Atlas sync failures are non-fatal and show sync-pending messaging.
- Auth/session hardening for mock, FastAPI, and Supabase-direct modes, including a blocking application-user bootstrap before authenticated navigation.
- Profile edit/save with validation, target refresh, sign out, and calculated calorie/protein/hydration/TDEE cards.
- Home dashboard wired to real backend context when available: `/agent/context` first, then Atlas metrics, food summary, workout logs/trends/templates fallback.
- Workout templates, saved-template library, weekly schedule, local schedule fallback, start-from-template, active workout execution, edited sets/reps/weight/RPE, finish workout, and nested workout log payloads.
- Nutrition diary with meal sections, manual/custom food flow, food search flow, food-log create/edit/delete, backend-owned summary totals in live mode, and local summing fallback in mock/offline mode.
- Jim chat technical foundation: standard `/chat/`, streaming `/chat/stream`, clarification options, session deletion, minimal chat screen, and action-triggered app refresh.
- Offline-first/recoverable fallback behavior for schedule, workout/nutrition outbox paths, and backend endpoint unavailability where previously implemented.
- Native local workout notification bridge for iOS/Android scheduling, permission-denied graceful behavior, and Android notification tap launch intent.
- Release QA assets: `RELEASE_CHECKLIST.md`, `tool/live_smoke_check.dart`, and `test/release_copy_scan_test.dart`.
- Backend contract request doc: `docs/BACKEND_ATLAS_ONBOARD_CONTRACT_REQUEST.md`.

## Latest Verification

Last updated: 2026-06-22.

Recent successful checks:

- `flutter analyze` passed.
- Full `flutter test` passed: 62 tests.
- `test/atlas_profile_integration_test.dart` passed.
- `test/home_agent_context_test.dart` passed.
- `flutter build web --release` passed.
- `flutter build ios --debug --no-codesign` passed.
- `flutter build ios --simulator --debug` passed.
- `flutter run -d <iPhone 17 simulator> --debug --no-resident` launched successfully.
- Release-copy scan test passed.
- `dart run tool/live_smoke_check.dart` ran without printing secrets. It reports config variable presence only, checks Render service-root reachability, and skips protected checks when no `JIMBRO_SMOKE_BEARER_TOKEN` is provided.

Blocked/unverified:

- `flutter build apk --debug` is blocked on this machine because no Android SDK is configured (`ANDROID_HOME` missing).
- Real device notification delivery/tap behavior still needs manual iOS and Android verification.
- Live protected backend smoke checks need a real bearer token.
- Live backend end-to-end persistence still needs verification against deployed FastAPI/Supabase.
- Live deployment is blocked until the backend implements the bearer-only Atlas contract and idempotent `/supabase/profile` reconciliation contract documented in `docs/BACKEND_ATLAS_ONBOARD_CONTRACT_REQUEST.md`.

## Current Dirty Worktree

Treat all existing changes as intentional unless the user says otherwise. As of the latest audit, notable staged/unstaged areas include:

- Sensitive modified `.env`.
- Config/auth/network/repository state: `lib/core/config/app_config.dart`, `lib/core/network/jim_api_client.dart`, `lib/core/navigation/app_state.dart`, `lib/core/repositories/app_repositories.dart`.
- Main feature screens: auth, onboarding, home, workouts, nutrition, history, profile, atlas chat.
- Shared UI/models: theme tokens, surfaces/buttons/state components, app models, onboarding models, Jim chat models.
- Native notification bridge: Android manifest/activity/receiver and iOS AppDelegate.
- Release/test assets: release checklist, live smoke helper, auth/config, Atlas, workout, nutrition, home, chat, onboarding, and widget tests.
- Backend docs: `docs/BACKEND_ATLAS_ONBOARD_CONTRACT_REQUEST.md`.

Always inspect targeted diffs before editing touched files, especially staged files.

## Environment And Secrets

Flutter bundles `.env` as an asset. It must contain only public/client-safe values:

- `APP_BACKEND_MODE`
- `AUTH_MODE`
- `FASTAPI_BASE_URL`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_REDIRECT_SCHEME`
- `SUPABASE_REDIRECT_HOST`

Never ship server-only values in Flutter:

- Supabase service role key
- database URL
- JWT secret
- private API keys
- backend/admin credentials

`FASTAPI_BASE_URL` must include `/api/v1`.

Mode matrix:

- `APP_BACKEND_MODE=mock`: app should boot without live config.
- `APP_BACKEND_MODE=fastapi`, `AUTH_MODE=fastApi`: FastAPI auth/session path.
- `APP_BACKEND_MODE=fastapi`, `AUTH_MODE=supabase`: Supabase direct auth provides bearer token for protected FastAPI endpoints.

## Backend Contracts Currently Implemented

Auth/config:

- Protected FastAPI requests use bearer token headers.
- 401 from protected actions clears session and returns to auth.
- Debug diagnostics avoid printing bearer tokens or `.env` values.

Atlas/profile:

- `POST /atlas/onboard`
- `GET /atlas/metrics`
- `PATCH /atlas/profile`
- Onboarding maps supported fields, sends `constraints_json` rather than `constraints`, does not send `generate_program`, and omits unsupported sex enum values.
- Frontend Atlas onboarding is bearer-only and never sends or retains a plaintext password for profile creation.
- Authenticated startup and fresh login/sign-up call `GET /supabase/profile` as the canonical provisioning/reconciliation gate and require a returned application-user identifier before navigation.
- Completed onboarding sends one of `omnivore`, `vegetarian`, `vegan`, `keto`, or `other` and marks `onboarding_completed` only in the canonical profile write.
- `GET /atlas/metrics` 404 / `ATLAS_METRICS_NOT_FOUND` is treated as metrics pending, not app failure.
- Live Atlas metrics are source of truth for BMR/TDEE/macros/hydration when available; local formulas are fallback only.
- Backend source code is not present in this repo. Requested backend change is documented in `docs/BACKEND_ATLAS_ONBOARD_CONTRACT_REQUEST.md`: `/atlas/onboard` should accept authenticated bearer JWT users without requiring `password`, derive user id/email server-side, make username optional/derived, and return profile/metrics with `updated_at`.

Home/dashboard:

- Preferred: `GET /agent/context`
- Fallback: `GET /atlas/metrics`, `GET /food-log/summary/{today}`, `GET /workout-logs/trends`, `GET /workout-logs`, `GET /workout-templates`
- Home uses backend metrics for targets, backend food summary for consumed values, and trends/recent workouts for progress.

Workout templates/logs:

- Templates: `GET/POST/PATCH/DELETE /workout-templates`
- Documented template payload fallback: `name`, `description`, `days[{day_label, exercises[{exercise_id, sets, reps, notes}]}]`
- Workout logs: `POST/PATCH /workout-logs`
- Rich log payload includes `name`, `template_id`, `notes`, `started_at`, `ended_at`, `duration_minutes`, `workout_exercises`, nested `sets`, `reps`, `weight_kg`, `is_warmup`, `rpe`, plus compatibility `exercises`.
- Documented log payload fallback: `workout_name`, `date`, `duration_min`, `notes`, `exercises[{exercise_id, sets[{set_number,reps,weight_kg,is_warmup}]}]`
- Schedule endpoint expected as `/workout-schedule`; unsupported/unavailable backend falls back locally.

Nutrition:

- `GET /food/search?q=...`
- `POST /food` for custom/manual food when needed
- `POST /food-log`
- `GET /food-log/summary/{date}`
- Quantity-only `PATCH /food-log/{id}` where supported
- `DELETE /food-log/{id}`
- Live mode refreshes summary after mutations; mock mode sums locally.

Jim chat:

- `POST /chat/`
- `POST /chat/stream` SSE
- `DELETE /chat/{session_id}`
- Request shape: `session_id`, `message`, optional `mode`.
- Modes: `workout`, `nutrition`, `knowledge`, `general`.
- Clarification response supports `requires_clarification`, `clarification_options[{id,label}]`, and `prompt`.
- Selection request sends same `session_id`, empty `message`, and `selected_option`.
- `actions_taken` triggers refresh of workout logs/templates, nutrition summary/logs, and dashboard context.

## Release Assets

- `RELEASE_CHECKLIST.md`: repeatable release checklist, env variable names only, mode matrix, mock/live smoke steps, notification tests, Android SDK note, copy scan instructions.
- `tool/live_smoke_check.dart`: optional no-secret live smoke helper. Prints config presence, status codes, and response key names only. Use `JIMBRO_SMOKE_BEARER_TOKEN` for protected checks.
- `test/release_copy_scan_test.dart`: scans `lib/**/*.dart` for user-facing banned release-copy terms: `demo`, `prototype`, `fake`, `lorem`, `no-op`, and Aryan seed-data references. Comment-only lines are ignored.
- `docs/BACKEND_ATLAS_ONBOARD_CONTRACT_REQUEST.md`: backend contract request for passwordless, bearer-authenticated Atlas onboarding.

## What Still Needs To Be Done

Highest priority:

1. Backend Atlas onboarding contract fix:
   - update deployed backend so `POST /atlas/onboard` accepts authenticated bearer users without `password`
   - make authenticated `GET /supabase/profile` idempotently provision/reconcile `public.users` and return its identifier
   - add the real backend migration for dietary enum/default/not-null and unique Auth UUID invariants
   - derive user id/email from JWT/session
   - make `username` optional/derived
   - return saved profile/metrics with `updated_at`
   - see `docs/BACKEND_ATLAS_ONBOARD_CONTRACT_REQUEST.md`
2. After backend contract fix, run one real live end-to-end path:
   - sign in
   - complete onboarding
   - reload profile/Atlas metrics
   - save/fetch/open workout template
   - schedule template and confirm Home today CTA
   - start/finish workout and verify nested log persistence
   - create/edit/delete food log and verify daily summary
   - open Jim chat and verify standard/streaming/clarification behavior
3. Run `tool/live_smoke_check.dart` with a valid bearer token and confirm protected endpoints.
4. Run live smoke helper with a bearer token against the Render backend.
5. Configure Android SDK and run `flutter build apk --debug`.
6. Native notification manual QA:
   - iOS device/simulator permission accept/deny
   - schedule delivery
   - notification tap opens app
   - Android 13+ permission accept/deny
   - Android delivery/tap after SDK is configured
7. Confirm Flutter `.env` contains only client-safe public values before any release build is distributed.

Medium priority:

- Verify live backend accepts expanded profile fields and Atlas profile patch fields.
- Verify workout schedule backend route support; keep local fallback if unsupported.
- Verify live workout log schema accepts rich payload or fallback documented payload.
- Verify live food create/log/edit/delete behavior and summary ownership.
- Decide whether the backend should add a dedicated `/health` or `/api/v1/health` endpoint; current smoke helper uses the service root for reachability.
- Device-test Supabase redirect/auth behavior for iOS and Android.

Lower priority/post-MVP:

- Production Google/Apple/phone auth.
- Account management beyond sign out.
- Rich progression analytics beyond current honest summaries/trends.
- Advanced meals/splits/custom plan flows.
- Full release signing/distribution automation.

## Development Rules

- Do not broadly rewrite routing, Riverpod app state, repositories, or page architecture.
- Do not change backend request/response field names without checking backend docs/live schema.
- Preserve mock mode.
- Preserve current guided onboarding UX.
- Preserve workout execution behavior: live workout edits must not mutate saved templates.
- Preserve nutrition truth rule: live mode must use backend-owned nutrition values, not AI/local guesses, as authoritative.
- Keep diagnostics debug/dev-safe and secret-free.
- Reuse existing shared components; no broad UI redesign unless requested.
- Do not edit native folders unless build/release/native verification directly requires it.
- Do not add demo seed data.

## Product Principles

- JimBro is a coaching platform, not just a tracker.
- Onboarding should feel like a first coaching session, not a form.
- Educate before asking.
- Ask one question per screen.
- Keep language simple and outcome-focused.
- Avoid medical advice, injury screening, and unsupported claims.
- Do not ask questions the product cannot act on.
- Prioritize trust, completion rate, personalization, coaching feel, and learning experience.

## Files To Inspect First

Core:

- `lib/core/config/app_config.dart`
- `lib/core/network/jim_api_client.dart`
- `lib/core/navigation/app_state.dart`
- `lib/core/repositories/app_repositories.dart`
- `lib/core/notifications/workout_notification_service.dart`

Models/components:

- `lib/shared/models/app_models.dart`
- `lib/shared/models/onboarding_models.dart`
- `lib/shared/models/jim_chat_models.dart`
- `lib/shared/components/backend_state_view.dart`
- `lib/shared/components/action_state.dart`
- `lib/shared/components/jim_page_scaffold.dart`

Features:

- `lib/features/onboarding/**`
- `lib/features/home/**`
- `lib/features/workouts/**`
- `lib/features/nutrition/**`
- `lib/features/profile/**`
- `lib/features/atlas/**`

Native/release:

- `ios/Runner/AppDelegate.swift`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/example/jimbro/MainActivity.kt`
- `android/app/src/main/kotlin/com/example/jimbro/WorkoutNotificationReceiver.kt`
- `RELEASE_CHECKLIST.md`
- `tool/live_smoke_check.dart`

Tests:

- `test/widget_test.dart`
- `test/release_config_auth_test.dart`
- `test/atlas_profile_integration_test.dart`
- `test/workout_log_flow_test.dart`
- `test/nutrition_targets_test.dart`
- `test/home_agent_context_test.dart`
- `test/jim_chat_integration_test.dart`
- `test/release_copy_scan_test.dart`

## Fresh Thread Workflow

1. Read this file.
2. Run `git status --short`.
3. Run `git diff --cached --stat`.
4. Inspect targeted diffs before editing files.
5. Make the smallest safe change.
6. Run `flutter analyze`.
7. Run targeted tests, then full `flutter test` when feasible.
8. For release tasks, also run relevant build commands from `RELEASE_CHECKLIST.md`.
9. Final response should include files changed, commands/results, risks, and whether mock mode/live mode/native behavior were preserved.

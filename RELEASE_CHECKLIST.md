# JimBro Release Checklist

Use this checklist before final UI polish and every release candidate. Do not paste or print `.env` values in logs, tickets, screenshots, or review notes.

## Environment

Flutter-bundled `.env` may contain only public/client-safe values:

- `APP_BACKEND_MODE`
- `AUTH_MODE`
- `FASTAPI_BASE_URL`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_REDIRECT_SCHEME`
- `SUPABASE_REDIRECT_HOST`

Do not ship server-only values in Flutter assets:

- Supabase service role key
- database URL
- JWT secret
- private third-party API keys
- backend admin credentials

`FASTAPI_BASE_URL` must include `/api/v1`, for example a base URL ending in `/api/v1`. The app calls paths such as `/auth/login`, `/atlas/metrics`, `/food-log`, and `/workout-templates` relative to that base.

## Mode Matrix

| Backend mode | Auth mode | Expected use | Required config |
| --- | --- | --- | --- |
| `mock` | `fastApi` or unset | Local demo-free smoke path with no backend dependency | no live backend config required |
| `fastapi` | `fastApi` | FastAPI handles email/password auth and protected API calls | `FASTAPI_BASE_URL` |
| `fastapi` | `supabase` | Supabase direct auth provides bearer token for FastAPI protected endpoints | `FASTAPI_BASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` |

## Automated Checks

Run from the repo root:

```sh
flutter analyze
flutter test
flutter build web --release
flutter build ios --debug
```

Run Android only on a machine with the Android SDK configured:

```sh
flutter build apk --debug
```

If Android is unavailable, record the blocker, usually missing `ANDROID_HOME`, and verify on a configured machine before release.

## Copy Scan

The test suite includes a release-copy scanner for Dart files under `lib/`. It blocks user-facing occurrences of:

- `demo`
- `prototype`
- `fake`
- `lorem`
- `no-op`
- Aryan seed-data references

Comments are ignored by the scanner so historical implementation notes do not fail release copy QA.

## Mock Mode Smoke Steps

1. Set `APP_BACKEND_MODE=mock`.
2. Launch the app.
3. Continue through auth with the available local provider.
4. Complete onboarding.
5. Confirm Home shows honest empty states and one primary CTA.
6. Create and save a workout template.
7. Start a workout from the template, edit at least one set, and finish it.
8. Add a food log, edit quantity/macros, delete one entry, and save the day.
9. Edit and save profile.
10. Confirm sign out returns to auth.

## Live Mode Smoke Steps

1. Set `APP_BACKEND_MODE=fastapi`.
2. Confirm `FASTAPI_BASE_URL` includes `/api/v1`.
3. Choose `AUTH_MODE=fastApi` or `AUTH_MODE=supabase`.
4. Launch a clean install.
5. Sign in and confirm session survives app reload.
6. Complete onboarding and confirm profile/Atlas metrics reload.
7. Save a workout template, fetch it, open it, and start from it.
8. Schedule a template and confirm Home shows today's scheduled workout.
9. Finish a workout and confirm nested exercises/sets persist.
10. Create a food log and confirm daily summary totals refresh from backend.
11. Edit/delete a food log and confirm daily summary refreshes.
12. Open Jim chat and verify non-secret chat errors are recoverable if backend chat is unavailable.

Optional command-line smoke helper:

```sh
JIMBRO_SMOKE_BEARER_TOKEN='<supabase-or-fastapi-jwt>' dart run tool/live_smoke_check.dart
```

The helper prints endpoint status codes and response key names only. It does not print tokens, `.env` values, or response bodies. Protected checks are skipped when `JIMBRO_SMOKE_BEARER_TOKEN` is absent.

## Native Notifications

iOS device or simulator:

1. Build and run with Xcode/Flutter.
2. Create a workout template.
3. Schedule it for the current weekday a few minutes ahead.
4. Accept notification permission.
5. Confirm the reminder appears.
6. Tap the reminder and confirm the app opens.
7. Repeat after denying permission on a fresh install; schedule should save and show a calm “reminders off” message without crashing.

Android device or emulator:

1. Verify Android SDK is configured.
2. Run `flutter build apk --debug`.
3. Install and run on Android 13+.
4. Schedule a workout reminder.
5. Accept notification permission and confirm delivery.
6. Tap the reminder and confirm the app opens.
7. Deny notification permission on a fresh install; schedule should save without crashing and reminders should remain off.

## Final Manual QA

- No `.env` values appear in logs or UI.
- No bearer tokens appear in logs or UI.
- Mock mode still boots without live config.
- Live mode fails clearly when required config is missing.
- No native folders are changed during final QA unless a compile error directly requires it.
- Any remaining unverified item is listed in release notes with owner and device/tooling blocker.

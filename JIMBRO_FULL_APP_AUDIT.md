# JimBro Full Application Audit

Audit date: 2026-07-21  
Audit target: current working tree at `main` / `e8d5cb4` (including pre-existing uncommitted changes)  
Audit mode: evidence-gathering only; no product code or production data was changed

## 1. Executive Summary

JimBro is suitable for continued local frontend development, but it is not ready for TestFlight or production and is not currently reliable enough for an unscripted live demo. The Flutter project is buildable and its 113 automated tests pass, but the repository does not contain the FastAPI implementation, Supabase schema, migrations, triggers, RLS policies, or backend tests needed to prove the central identity invariant. The configured live API also timed out during the audit.

The audit records **22 issues: 2 P0, 11 P1, 8 P2, and 1 P3**.

The five largest risks are:

1. The application-user provisioning and orphan-reconciliation contract exists only as client documentation; its database implementation and deployment cannot be verified.
2. Nutrition replacement is a sequence of destructive requests, so a failure after a delete can leave the remote diary partially erased.
3. Offline workout and nutrition writes return ordinary domain objects, causing the UI to claim remote success while data is only queued locally; replay is not demonstrably idempotent.
4. Template builder, active workout, and last completed workout are conflated in one page and one draft object; there is no recoverable active-session lifecycle.
5. Search, startup loads, schedule synchronization, analytics, and several endpoint fallbacks hide integration failures as empty or local data.

**Demo safety:** a controlled frontend-only demo is possible with a known test account and network/API health checked immediately beforehand, while avoiding nutrition mutation, offline mode, account deletion, and app restarts during an active workout. An unscripted or stakeholder data-integrity demo is not safe.

**Production readiness:** no. P0/P1 data integrity, identity, session, and write-observability work must be completed first.

**Most important dependency chain:** obtain and test the real FastAPI/Supabase repository → establish JWT-derived, idempotent user provisioning and deletion → make core mutations atomic/idempotent and truthfully represented in state → separate active workout from templates/history → repair search/nutrition UX → finish responsive and end-to-end coverage.

## 2. Audit Scope and Environment

### Source inspected

- Flutter/Dart source under `lib/`, tests under `test/`, platform projects, `.env` variable names, `pubspec.yaml`, repository documentation, and the current Git diff.
- Branch `main`, commit `e8d5cb4`, plus a dirty working tree that predated this audit. The audit does not attribute those edits to a particular author and did not modify them.
- Flutter 3.41.1 stable and Dart 3.11.0.
- Riverpod, Dio, Supabase Flutter, SharedPreferences, and the repository/provider composition in `lib/core/repositories/app_repositories.dart`.

### Platforms and runtime inspected

- Flutter static analysis and all repository Flutter tests.
- Release web build.
- iOS simulator debug build.
- Android debug build attempt.
- Locally served web build in the in-app browser at a 320 × 568 viewport. The exact splash mascot and authentication screen rendered without a console warning or a visible overflow at that viewport.
- Configured API smoke check and OpenAPI reachability attempt.

### Available services

- Flutter/Dart toolchain, Xcode simulator build toolchain, local browser, and the client-side Supabase configuration.
- The web client initialized the configured Supabase auth integration; no credentials were used and no account/data mutation was performed.

### Unavailable services and limitations

- The checkout is explicitly frontend-only: `docs/BACKEND_ATLAS_ONBOARD_CONTRACT_REQUEST.md:3-8` says FastAPI source, schema, migrations, triggers, and backend tests are absent.
- The configured API root and health endpoint timed out. OpenAPI could not be obtained, so “actual backend contract” entries below are marked uncertain rather than invented.
- No test credentials were supplied. Authenticated home, database writes, actual token refresh, signup, orphan repair, deletion, and restart behavior could not be exercised against the deployed stack.
- Android SDK/`ANDROID_HOME` is not installed, so the Android build could not run.
- The reported pixel overflow was not reproduced on the reachable splash/auth flow. Authenticated and keyboard/text-scale variants could not be dynamically inspected; candidate risks are identified as such, not as confirmed runtime failures.
- The `.docx` backend document was inspected as an endpoint index, but it does not provide authoritative request/response schemas, database constraints, RLS, trigger, or transaction behavior.

## 3. Priority Overview

| ID | Priority | Area | Issue | User Impact | Root Cause Status | Recommended Order |
| -- | -------- | ---- | ----- | ----------- | ----------------- | ----------------- |
| JMB-001 | P0 | Auth/database | Required application-user provisioning is not implemented or verifiable in this checkout | Auth users may be unusable or orphaned | Confirmed repository/release gap; deployed behavior unable to reproduce | 1 |
| JMB-002 | P0 | Nutrition/data | Nutrition replacement can delete remote rows before a later write fails | Partial diary data loss | Confirmed | 2 |
| JMB-003 | P1 | Workout sync | Offline workout is reported as remotely saved and replay is not demonstrably idempotent | False success, delayed or duplicate logs | Confirmed | 3 |
| JMB-004 | P1 | Workout UX/architecture | Template builder, active workout, and completed workout are conflated | Wrong destination and no real active-workout flow | Confirmed | 5 |
| JMB-005 | P1 | Workout lifecycle | Active workouts have no durable recovery, autosave, rest timer, or lifecycle model | Session loss on restart/backgrounding | Confirmed | 6 |
| JMB-006 | P1 | Templates | Save can succeed without a server ID; stale cache and no draft recovery undermine persistence | Duplicate or apparently missing templates | Confirmed | 4 |
| JMB-007 | P1 | Search | Exercise and food search swallow all failures as empty results | Search looks broken and cannot be diagnosed | Confirmed | 8 |
| JMB-008 | P1 | Nutrition UX/sync | Logging has a remote-success false positive, an obscure CTA, and non-persisted hydration | Users cannot tell what was logged | Confirmed | 7 |
| JMB-009 | P1 | Schedule | Missing/unreachable schedule API silently becomes local-only state | Schedule disappears across devices/reinstall | Confirmed | 4 |
| JMB-010 | P1 | Auth/state | FastAPI sessions are memory-only; auth/onboarding truth is duplicated and inferred | Cold starts and gating can become inconsistent | Confirmed | 3 |
| JMB-011 | P1 | History/analytics | History loads one workout and consistency/Atlas sources are mocks in live composition | Misleading or ephemeral progress | Confirmed | 9 |
| JMB-012 | P1 | Account lifecycle | `/account` and orphan-safe deletion are undocumented/unverifiable server-side | Deletion may fail or be incomplete | Highly likely contract risk; runtime unable to reproduce | 1 |
| JMB-013 | P1 | Security/errors | Raw request/response diagnostics can reach end users | Sensitive profile details/internal errors may be exposed | Confirmed | 2 |
| JMB-014 | P2 | Navigation | Home renders a second scrolling footer that duplicates primary tabs | Confusing duplicate navigation | Confirmed | 10 |
| JMB-015 | P2 | Home/brand | Home omits the exact shared splash mascot | Inconsistent identity and missed requested behavior | Confirmed | 10 |
| JMB-016 | P2 | Startup/errors | Core resource failures are converted to empty/default state and app readiness continues | Stale/empty screens with no retry explanation | Confirmed | 3 |
| JMB-017 | P2 | Responsive UI | Responsive coverage is insufficient for the reported overflow conditions | Common layout failures may escape release checks | Possible; reported issue not reproduced | 11 |
| JMB-018 | P2 | Onboarding persistence | Riverpod advances before SharedPreferences commit completes | Interrupted progress can regress after restart | Confirmed | 9 |
| JMB-019 | P2 | Privacy/local data | Workout and nutrition payloads are stored plaintext in SharedPreferences | Behavioral/profile data exposed to local extraction | Confirmed | 2 |
| JMB-020 | P2 | Navigation/state | Minimal route map, no tab back stacks, and unused mock global search state | Weak deep links and unreachable/dead behavior | Confirmed | 10 |
| JMB-021 | P2 | Performance | Main tabs and large editable lists build eagerly | Slower startup/rebuilds as data grows | Confirmed architecture risk | 11 |
| JMB-022 | P3 | Documentation/maintainability | Default README, endpoint drift, and very large repository/state files impede change safety | Higher regression and onboarding cost | Confirmed | 12 |

## 4. P0 — Critical Issues

### JMB-001 — Application-user provisioning and database invariants are not release-verifiable

**Priority:** P0  
**Area:** Authentication, account lifecycle, FastAPI, Supabase  
**Status:** Confirmed repository/release gap; deployed behavior Unable to reproduce  
**Observed behavior:** The frontend now blocks authenticated readiness on `GET /supabase/profile`, but this checkout contains only a required backend contract. The contract itself states that the FastAPI source, schema, migrations, triggers, and backend tests are absent (`docs/BACKEND_ATLAS_ONBOARD_CONTRACT_REQUEST.md:3-8`). The configured service timed out, so the idempotent provision/repair operation, `dietary_preference` constraint/default, Auth UUID uniqueness, RLS, and orphan-safe deletion could not be exercised.  
**Expected behavior:** Every verified Supabase JWT resolves to exactly one usable `public.users` row; a missing row is repaired transaction-safely with a valid provisional preference, while completed onboarding validates and persists one of the five enum values.  
**User impact:** A Supabase account can appear created but remain unusable for every application-level write, or the client can be blocked indefinitely. This is a production and account-use blocker.  
**Reproduction steps:** Inspect `docs/BACKEND_ATLAS_ONBOARD_CONTRACT_REQUEST.md:30-62`; search this repository for FastAPI entry points, SQL migrations, RLS, triggers, or backend tests (none exist); run the live smoke check (health times out). Actual orphan creation was intentionally not attempted without a controlled backend.  
**Root cause:** The frontend and required backend/database implementation are split across repositories, but the implementation/deployment artifact and integration proof are not present. Client gating cannot itself enforce a database invariant.  
**Affected files/components:** `lib/core/navigation/app_state.dart:138-167`, `lib/core/navigation/app_state.dart:1607-1658`, `docs/BACKEND_ATLAS_ONBOARD_CONTRACT_REQUEST.md:30-127`, deployed FastAPI/Supabase repository (absent).  
**Backend/database involvement:** Total. Must verify JWT identity derivation, one unique Auth UUID, all NOT NULL fields, enum/check constraint, trigger/service behavior, transaction, RLS, and cascades.  
**Recommended fix:** Bring the backend repository and environment into the release pipeline; implement one canonical JWT-derived idempotent provision/reconcile service used by bootstrap and downstream writes; add the real safe migration and integration tests; expose stable non-sensitive error codes; verify against a disposable environment.  
**Dependencies:** Blocks reliable auth, onboarding, workouts, nutrition, schedule, analytics, and deletion.  
**Tests required:** Real signup creates exactly one row; retry is idempotent; provisional omnivore; all five completed values; missing/null/unknown 422; orphan repair without overwrite; concurrent bootstrap; downstream write after repair; RLS isolation; normal/orphan deletion.  
**Estimated effort:** Large

### JMB-002 — Nutrition save is destructive and non-atomic

**Priority:** P0  
**Area:** Nutrition, API, data integrity  
**Status:** Confirmed  
**Observed behavior:** `_saveFoodLogsOnline` loads the current remote list, deletes rows omitted by the client, and may delete an edited row before posting its replacement (`lib/core/repositories/app_repositories.dart:2053-2081`, `2131-2164`). Any timeout, validation error, expired token, or server error after an earlier delete leaves only part of the requested day persisted. Offline replay repeats the same replace sequence.  
**Expected behavior:** A day mutation is all-or-nothing, or independent item mutations are ordered and versioned so a failed update preserves the previously committed entry.  
**User impact:** Previously logged food can disappear even though “save day” fails. A stale offline batch can also overwrite a newer remote day. This is direct user-data loss.  
**Reproduction steps:** Seed two remote entries; submit a list that removes the first and modifies the second; make the replacement POST return 422/500 after the first DELETE succeeds; reload. The removed/recreated rows are not rolled back.  
**Root cause:** A client-side replace algorithm implements a transaction using multiple independent DELETE/PATCH/POST requests, without a backend transaction, revision check, or idempotent batch command.  
**Affected files/components:** `lib/core/repositories/app_repositories.dart:2017-2164`, `2180-2213`; Nutrition save UI at `lib/features/nutrition/presentation/nutrition_page.dart:61-76`.  
**Backend/database involvement:** Requires an atomic authenticated batch endpoint/RPC or safe per-row update semantics; ownership must be JWT-derived and transaction-scoped.  
**Recommended fix:** Add an atomic `PUT`/transactional batch contract for a date with a client mutation ID and version/updated-at precondition. Never delete an existing row before its validated replacement is guaranteed. Return the authoritative committed day and explicit conflict/offline status.  
**Dependencies:** Resolve before refining the nutrition CTA or enabling offline replay.  
**Tests required:** Inject failure after each operation; assert rollback/no loss; concurrent-edit conflict; duplicate mutation replay; expired token refresh; stale offline batch; empty-day replacement; multi-user isolation.  
**Estimated effort:** Large

## 5. P1 — High-Priority Issues

### JMB-003 — Offline workout completion is presented as server success

**Priority:** P1  
**Area:** Workout logging, synchronization  
**Status:** Confirmed  
**Observed behavior:** On a recoverable Dio failure, `saveWorkoutLog` queues a SharedPreferences outbox item and returns the normalized unsaved draft (`app_repositories.dart:1654-1691`). The controller treats it as saved, and both finish controls announce “Workout finished and saved” (`workouts_page.dart:87-101`, `231-246`). Mutation IDs are timestamp-derived and no idempotency key is sent; replay after an uncertain commit can duplicate a POST.  
**Expected behavior:** State and UI distinguish `pendingSync`, `synced`, `needsReview`, and `failed`; retries use a stable server idempotency key.  
**User impact:** Users leave believing a workout exists remotely when it may be queued indefinitely, rejected later, or duplicated.  
**Reproduction steps:** Start and finish a valid workout with the API unreachable; observe the success message and completed-looking state; inspect outbox; restore network and replay twice around an uncertain response.  
**Root cause:** The repository return type carries no persistence status, and the client outbox has only locally generated operation identity.  
**Affected files/components:** `lib/core/repositories/app_repositories.dart:1654-1818`, `lib/core/repositories/app_repositories.dart:3064-3131`, `lib/core/navigation/app_state.dart:1261-1273`, `lib/features/workouts/presentation/workouts_page.dart:87-101`.  
**Backend/database involvement:** Server needs idempotency/unique mutation identity and authoritative response IDs.  
**Recommended fix:** Return a typed mutation result; retain active/completed local record with visible sync badge; persist stable mutation UUID before first attempt; send it to an idempotent endpoint; surface rejected items with retry/review.  
**Dependencies:** JMB-001 and stable workout contract.  
**Tests required:** Offline completion, queued indicator, restart/replay, response lost after commit, duplicate replay, 422 review, 401 refresh, server ID reconciliation.  
**Estimated effort:** Medium

### JMB-004 — There is no distinct active-workout route or screen

**Priority:** P1  
**Area:** Workout information architecture and navigation  
**Status:** Confirmed  
**Observed behavior:** Starting a template mutates `AppDraftState.workoutLog`; it does not navigate. `WorkoutsPage` always renders library, schedule, optional inline execution, and the template builder (`workouts_page.dart:47-253`). The active panel and builder each expose finish/log controls.  
**Expected behavior:** “Start” opens a dedicated active-workout route; “Edit” opens the template builder; a completed record is read-only history.  
**User impact:** Users land in editing UI while exercising, can confuse reusable structure with session data, and see duplicate completion actions.  
**Reproduction steps:** Workouts → select saved template → Start; observe execution embedded above “Template builder,” plus Finish at `workouts_page.dart:427-435` and another at `231-247`.  
**Root cause:** One tab/page and one draft aggregate were used for three domain concepts; the route map has no active session route.  
**Affected files/components:** `lib/features/workouts/presentation/workouts_page.dart:47-253`, `lib/core/navigation/app_state.dart:511-531`, `lib/app/app.dart`, `lib/core/navigation/app_flow.dart`.  
**Backend/database involvement:** Active drafts and completed logs require distinct contracts/identifiers.  
**Recommended fix:** Implement the route/state split in section 9; do not reuse template editing widgets as the active-session page except for genuinely shared exercise/set components.  
**Dependencies:** Define session persistence contract before UI extraction.  
**Tests required:** Start vs edit destinations, route restoration, exactly one finish action, discard confirmation, completion summary, template remains unchanged.  
**Estimated effort:** Large

### JMB-005 — Active workout sessions cannot survive lifecycle interruptions

**Priority:** P1  
**Area:** Workout lifecycle  
**Status:** Confirmed  
**Observed behavior:** In-progress sets live only in `AppDraftState.workoutLog`. Startup reloads the latest completed `/workout-logs` item, not an active draft. There is no rest timer, autosave interval, app pause/resume handling, resume banner, or discard state.  
**Expected behavior:** An active session is durably checkpointed, recoverable after process death, and has an explicit timer/finish/discard lifecycle.  
**User impact:** A long workout can be lost on app termination, OS reclaim, sign-in refresh problem, or accidental navigation.  
**Reproduction steps:** Start a template, enter sets, terminate/restart; the state is rebuilt from completed-log/template loads.  
**Root cause:** No active-session entity/repository exists; “in progress” is inferred from fields on the completed-log draft.  
**Affected files/components:** `lib/core/navigation/app_state.dart:511-531`, `1261-1273`, `1691-1757`; workout models and `workouts_page.dart`.  
**Backend/database involvement:** Decide local-first checkpoint plus server draft, or server session with revisioned autosave.  
**Recommended fix:** Add a single active-session owner with stable session ID, lifecycle timestamps, local durable checkpoint, throttled/versioned autosave, timer state based on timestamps, recovery, and explicit finish/discard.  
**Dependencies:** JMB-004 and backend session contract.  
**Tests required:** process restart, pause/resume, timer reconstruction, concurrent autosaves, expired token, discard, finish exactly once, failed final sync.  
**Estimated effort:** Large

### JMB-006 — Workout-template persistence accepts ambiguous saves and stale cache

**Priority:** P1  
**Area:** Workout templates  
**Status:** Confirmed  
**Observed behavior:** If the create response lacks a mapped template and `template_id`, the repository returns the normalized draft with a null ID as success (`app_repositories.dart:1415-1425`); another save POSTs again. A valid server response containing an empty list is replaced by cached templates (`1211-1243`), so server deletions can appear to return. Unsaved builder state is memory-only.  
**Expected behavior:** Create succeeds only with a stable authoritative ID; an authoritative empty list clears cache; dirty drafts survive accidental navigation/restart or prompt before loss.  
**User impact:** Intermittent duplicates, templates that appear saved but cannot be edited reliably, and stale/deleted templates.  
**Reproduction steps:** Return 200/201 without `template_id`; save twice. Separately cache a template then return `[]` from GET and observe cached data returned.  
**Root cause:** Response validation conflates a successful HTTP status with a valid persistence result; cache fallback cannot distinguish unavailable from authoritative empty.  
**Affected files/components:** `lib/core/repositories/app_repositories.dart:1211-1243`, `1377-1482`, `1518-1535`; `workouts_page.dart:110-224`.  
**Backend/database involvement:** Document create/update response schema and uniqueness/idempotency.  
**Recommended fix:** Require/validate ID and canonical response; use typed response parsing; clear cache on authoritative empty; add dirty-draft persistence/guard; retain the guarded submit button.  
**Dependencies:** Contract inventory and JMB-001.  
**Tests required:** malformed success body, empty authoritative list, lost response, repeat submit, restart draft, edit/read-back/delete/sign-out.  
**Estimated effort:** Medium

### JMB-007 — Search errors are silently rendered as no results

**Priority:** P1  
**Area:** Exercise and food search  
**Status:** Confirmed  
**Observed behavior:** Both API search methods trim/lowercase and support partial query parameters, but omit auth headers and catch every exception, returning cached or empty lists (`app_repositories.dart:1325-1374`, `1973-2014`). Therefore UI exception/error branches do not run; API failure is indistinguishable from no match. Debounce gates stale rendering but does not cancel requests.  
**Expected behavior:** Search exposes loading, no-result, offline/cached, unauthorized, and retryable error states separately; protected endpoints use the session.  
**User impact:** Search “does not work” intermittently with no actionable feedback, blocking template and food creation.  
**Reproduction steps:** Search a known item while endpoint times out/returns 401/500; UI receives `[]` and displays no-result behavior rather than error.  
**Root cause:** Broad catches erase transport/status information and repository method signatures do not accept authenticated session/context.  
**Affected files/components:** `lib/core/repositories/app_repositories.dart:1325-1374`, `1973-2014`; search editors in `workouts_page.dart` and `nutrition_page.dart`.  
**Backend/database involvement:** Confirm whether catalog search is public; document query/response/pagination.  
**Recommended fix:** Use typed search state and cancellable/debounced requests; preserve cache with a visible stale/offline marker; propagate failures; add auth if required; reset state appropriately on selection/navigation.  
**Dependencies:** Endpoint contract confirmation.  
**Tests required:** trim/case/partial, encoding, stale response ordering, cancellation, 401/422/500/timeout, cached offline, empty query, selection.  
**Estimated effort:** Medium

### JMB-008 — Nutrition logging is ambiguous and reports queued data as synced

**Priority:** P1  
**Area:** Nutrition UX and state  
**Status:** Confirmed  
**Observed behavior:** Selecting food fills an editor, but the only persistence control is a small header icon with tooltip “Save day” (`nutrition_page.dart:61-76`), distant from entries. On network failure the repository queues the entire day, returns ordinary logs, and UI says “Nutrition logs saved to Supabase” (`app_repositories.dart:2017-2050`). Hydration changes only local draft state and are not included in this persistence path.  
**Expected behavior:** A clear “Log food” action commits a reviewed entry, visibly confirms remote vs pending state, updates totals from the committed response, and persists hydration through a defined contract.  
**User impact:** Users cannot confidently tell whether selection equals logging, whether the whole day was saved, or why entries/water disappear later.  
**Reproduction steps:** Add/select a food and inspect available controls; take API offline and tap Save day; observe Supabase-success copy while an outbox item is queued. Restart after changing water.  
**Root cause:** Page-level diary editing, batch persistence, optimistic cache, and per-entry logging are mixed without an explicit mutation state.  
**Affected files/components:** `lib/features/nutrition/presentation/nutrition_page.dart:61-76`, `697-708`; `lib/core/navigation/app_state.dart:1029-1117`; `app_repositories.dart:2017-2213`.  
**Backend/database involvement:** Atomic nutrition contract from JMB-002 plus hydration/date endpoints.  
**Recommended fix:** After JMB-002, add explicit per-entry review/log CTA, pending/synced/error badges, local undo for deletion, clear meal grouping and date context, authoritative total refresh, and hydration persistence.  
**Dependencies:** JMB-002 first, then JMB-007.  
**Tests required:** full search→select→quantity→meal→log flow, pending/failed/retry, totals, edit/delete/undo, water restart, date, duplicate tap.  
**Estimated effort:** Large

### JMB-009 — Workout schedules silently become device-local

**Priority:** P1  
**Area:** Workout schedule integration  
**Status:** Confirmed  
**Observed behavior:** GET/POST/PATCH/DELETE `/workout-schedule` falls back to SharedPreferences for network failures or unsupported routes; a static flag permanently disables backend attempts for the process (`app_repositories.dart:1255-1290`, `1538-1652`). The UI returns a normal notification rather than a persistent sync warning. The endpoint is absent from the supplied backend endpoint document.  
**Expected behavior:** Remote and local schedule status is explicit; unsupported deployment is a release/configuration error, not invisible success.  
**User impact:** A schedule can vanish after reinstall/sign-in on another device and never reach reminders/program logic.  
**Reproduction steps:** Return 404 or disconnect on schedule POST; observe debug “using local schedule store,” then normal UI state; sign in elsewhere.  
**Root cause:** A compatibility fallback is used as permanent storage without sync metadata/reconciliation.  
**Affected files/components:** `lib/core/repositories/app_repositories.dart:1255-1290`, `1538-1652`; workout schedule panel.  
**Backend/database involvement:** Confirm/add endpoints, ownership, unique schedule semantics, and response schema.  
**Recommended fix:** Make deployment support explicit; either ship/test the backend contract or label schedules “On this device” and disable server-dependent claims. Add outbox/sync state only with idempotent reconciliation.  
**Dependencies:** API deployment inventory and JMB-001.  
**Tests required:** 404, timeout, cross-device reload, local-to-remote reconciliation, duplicate schedule, delete conflict, sign-out isolation.  
**Estimated effort:** Medium

### JMB-010 — Authentication and onboarding readiness have competing sources of truth

**Priority:** P1  
**Area:** Auth, session restoration, Riverpod state  
**Status:** Confirmed  
**Observed behavior:** Readiness is split among `authSessionProvider`, `isAuthenticatedProvider`, `hasCompletedOnboardingProvider`, `forceShowOnboardingProvider`, and `AppDraftState.session` (`app_state.dart:15-17`). FastAPI auth stores `_session` only in memory (`app_repositories.dart:421-424`), while Supabase mode restores via its SDK. `_requireSessionForAuthenticatedAction` can set authenticated state while healing a missing local session (`app_state.dart:1889`). Onboarding completion is inferred from selected profile fields (`1857-1868`), not the backend flag that the payload writes.  
**Expected behavior:** One session/readiness state machine represents unauthenticated, auth-valid/provisioning, onboarding-required, ready, expired, and error; server `onboarding_completed` remains canonical.  
**User impact:** FastAPI-mode cold starts sign users out; mismatched state may allow or block navigation incorrectly and produce hard-to-reproduce write races.  
**Reproduction steps:** Authenticate using FastAPI repository then recreate providers/process; `_session` is null. Return a populated profile with `onboarding_completed=false`, or a valid completed flag with one inferred field empty; gate is based on fields.  
**Root cause:** Boolean navigation flags shadow session/profile state instead of deriving from a canonical bootstrap result.  
**Affected files/components:** `lib/core/navigation/app_state.dart:15-17`, `138-167`, `1607-1673`, `1857-1930`; `lib/core/navigation/app_flow.dart:97-112`; `app_repositories.dart:421-625`.  
**Backend/database involvement:** Bootstrap response must include canonical onboarding and application-user state.  
**Recommended fix:** Introduce one sealed bootstrap state derived from the auth SDK and verified profile response; persist/refresh FastAPI sessions securely if that mode remains; never flip ready/authenticated inside downstream helpers.  
**Dependencies:** JMB-001.  
**Tests required:** cold restart both auth modes, refresh success/failure, provisioning retry, flag/profile disagreement, logout/delete reset, concurrent bootstrap/write.  
**Estimated effort:** Large

### JMB-011 — History and analytics are incomplete and partly mock-backed

**Priority:** P1  
**Area:** History, analytics, dashboard truthfulness  
**Status:** Confirmed  
**Observed behavior:** `/workout-logs` is reduced to one most-recent item (`app_repositories.dart:1294-1322`); History renders that single `draft.workoutLog`. `consistencyRepositoryProvider`, `atlasRepositoryProvider`, and the global `searchRepositoryProvider` always compose mock implementations (`3290-3324`); consistency is memory-only (`2674-2693`).  
**Expected behavior:** History is a paginated list of completed sessions; analytics are derived from authoritative dated workout/nutrition records with clear ranges and empty/error states.  
**User impact:** Streaks and progress can reset, values can be misleading, and users cannot inspect past workouts beyond the latest.  
**Reproduction steps:** Inspect provider composition; complete multiple logs and follow `loadWorkoutLog`; only one is retained. Restart and mock consistency resets.  
**Root cause:** Draft-era mock providers and a singular domain model remain in live composition.  
**Affected files/components:** `lib/core/repositories/app_repositories.dart:1294-1322`, `2674-2825`, `3290-3324`; `lib/features/history/presentation/history_page.dart:60-110`.  
**Backend/database involvement:** Needs paginated history/trends contracts and authoritative metric definitions.  
**Recommended fix:** Separate `activeSession`, `completedHistory`, and aggregates; implement live repositories; display data source/range; retain honest empty/error states.  
**Dependencies:** Reliable workout/nutrition writes.  
**Tests required:** multiple dated sessions, pagination, ranges, empty/error, restart, deletion recalculation, timezone boundary, cross-device.  
**Estimated effort:** Large

### JMB-012 — Secure normal/orphan account deletion cannot be verified

**Priority:** P1  
**Area:** Account lifecycle  
**Status:** Highly likely contract risk; runtime Unable to reproduce  
**Observed behavior:** Client calls JWT-authenticated `DELETE /account` (`app_repositories.dart:378-407`), but the endpoint is missing from the supplied backend endpoint index; its only detailed behavior is the frontend contract document (`docs/...:100-109`). No server source/test proves Auth admin deletion, related-data cascade, idempotency, or orphan handling.  
**Expected behavior:** Verified JWT identifies the account; related application data and Auth user are deleted securely and idempotently even when `public.users` is absent.  
**User impact:** Users may be unable to exercise account deletion, or deletion may leave Auth/data remnants.  
**Reproduction steps:** Static contract comparison. Live deletion was not attempted without a disposable account and reachable backend.  
**Root cause:** Endpoint/deployment and database cascade implementation are outside the audited repository and documentation is inconsistent.  
**Affected files/components:** `lib/core/repositories/app_repositories.dart:378-407`, `lib/features/profile/presentation/profile_page.dart:860-930`, backend/Supabase absent.  
**Backend/database involvement:** Auth admin API, JWT verification, ownership, cascades, orphan cleanup, audit logging.  
**Recommended fix:** Implement/verify in backend repository; use service-role only server-side; make steps idempotent; return a stable deletion receipt; integration-test normal/orphan/retry and confirm client clears all local state.  
**Dependencies:** JMB-001 and real schema inventory.  
**Tests required:** normal, orphan, repeated delete, expired/foreign token, partial related data, cascade verification, auth-user absence, local state clearing.  
**Estimated effort:** Medium

### JMB-013 — Technical diagnostics and payload details can be exposed to users

**Priority:** P1  
**Area:** Security, privacy, error handling  
**Status:** Confirmed  
**Observed behavior:** `_throwIfRequestFailed` includes `response.requestOptions.data.toString()` and response body in diagnostics (`app_repositories.dart:3925-3967`). Workout error UI explicitly formats `response_body`, source path, and suggested fixes for display; auth formatting can return the raw exception. Profile/onboarding payloads include personal metrics.  
**Expected behavior:** Logs are redacted and structured; users see a stable friendly message and correlation/error code, never raw request bodies, SQL/HTML, stack-like source paths, tokens, or personal payload echoes.  
**User impact:** Sensitive profile data and internal implementation details may be disclosed on screen or in captured logs/screenshots.  
**Reproduction steps:** Force a non-2xx workout/profile/auth response containing an internal body; follow exception formatting into the dialog/snackbar.  
**Root cause:** The same verbose diagnostic string is used for developer logging and presentation.  
**Affected files/components:** `lib/core/repositories/app_repositories.dart:3925-3967`, `4092-4112`; `lib/features/workouts/presentation/workouts_page.dart:1218-1257`; `lib/features/auth/presentation/auth_page.dart:126-138`.  
**Backend/database involvement:** Server should return safe stable codes and correlation IDs; logs must redact.  
**Recommended fix:** Create typed public vs diagnostic errors; allow-list safe metadata; redact bodies/headers/profile data; log diagnostics only in controlled development/telemetry; map codes to friendly retry guidance.  
**Dependencies:** Do early because it affects all subsequent observability work.  
**Tests required:** token/password/profile redaction, HTML/SQL body, long response, release-mode output, stable code mapping.  
**Estimated effort:** Medium

## 6. P2 — Medium-Priority Issues

### JMB-014 — Home contains a duplicate scrolling navigation footer

**Priority:** P2  
**Area:** Home/navigation  
**Status:** Confirmed  
**Observed behavior:** `HomeShell` provides the intended persistent five-item `BottomNavigationBar` (`home_shell.dart:26-62`). Home content also appends `_HomeNavigation`, four large buttons that set the same tab provider (`home_page.dart:104-109`, `933-1036`).  
**Expected behavior:** One persistent primary bottom navigation bar; contextual cards may deep-link only when they have distinct content purpose.  
**User impact:** Two footers compete, increase scrolling, and confuse information hierarchy.  
**Reproduction steps:** Scroll to the bottom of Home.  
**Root cause:** Page-level shortcut navigation duplicates shell navigation.  
**Affected files/components:** Files above; `JimPageScaffold` already reserves 120 px bottom padding.  
**Backend/database involvement:** None.  
**Recommended fix:** Remove `_HomeNavigation` from content; keep the original persistent shell bar unchanged.  
**Dependencies:** None.  
**Tests required:** one primary nav, each tab tap, Home scroll end unobscured, semantics.  
**Estimated effort:** Small

### JMB-015 — Home does not reuse the exact splash mascot

**Priority:** P2  
**Area:** Home/brand consistency  
**Status:** Confirmed  
**Observed behavior:** Splash uses shared `JimCompanionAvatar` with a Hero/rotation treatment (`app_flow.dart:180-188`). Auth, onboarding, profile, and history reuse it; Home does not reference it. The mascot is a reusable CustomPainter component (`lib/shared/components/jim_companion.dart:6-285`), not a missing external asset.  
**Expected behavior:** Home reuses the exact same component/visual treatment, adjusted only for layout size.  
**User impact:** The strongest brand cue disappears on the primary screen.  
**Reproduction steps:** Compare splash implementation to Home imports/hero section.  
**Root cause:** Home hero was built without the already-shared component.  
**Affected files/components:** `lib/core/navigation/app_flow.dart:180-188`, `lib/shared/components/jim_companion.dart`, `lib/features/home/presentation/home_page.dart:68-109`.  
**Backend/database involvement:** None.  
**Recommended fix:** Place the existing `JimCompanionAvatar` in Home’s hero/responsive composition; do not redraw, generate, or replace it.  
**Dependencies:** Coordinate with responsive tests.  
**Tests required:** exact widget reuse, small/large width, text scale, golden/semantic check.  
**Estimated effort:** Small

### JMB-016 — Startup hides failed core loads behind defaults

**Priority:** P2  
**Area:** State/error handling  
**Status:** Confirmed  
**Observed behavior:** Startup concurrently wraps profile-adjacent data, metrics, templates, schedule, log, foods, summary, and consistency with `_loadOrDefault`; timeouts and many 5xx failures become empty/default values (`app_state.dart:1689-1813`, `1824-1855`). App readiness continues without per-resource error state. Home uses `valueOrNull` for agent context.  
**Expected behavior:** Provisioning/profile failure blocks readiness; optional resources expose loaded/stale/error/retry independently.  
**User impact:** Empty templates, history, totals, or cards look like genuine “no data,” and users may overwrite stale server truth.  
**Reproduction steps:** Return 500 for templates/nutrition/history during bootstrap; app loads defaults without a resource-level failure explanation.  
**Root cause:** One aggregate draft cannot represent partial async state; compatibility defaults erase provenance.  
**Affected files/components:** `lib/core/navigation/app_state.dart:1689-1855`, Home `agentContextProvider` use.  
**Backend/database involvement:** Stable status/error envelope helps classification.  
**Recommended fix:** Model each resource as fresh/stale/error; block only identity-critical resources; show retry and prevent destructive writes based on unknown baselines.  
**Dependencies:** JMB-010 and safe error model.  
**Tests required:** independent 401/404/500/timeout, partial render, retry, stale cache label, no destructive save from unknown baseline.  
**Estimated effort:** Medium

### JMB-017 — Reported overflow conditions lack reproducible responsive coverage

**Priority:** P2  
**Area:** Responsive UI/accessibility  
**Status:** Possible; reported issue not reproduced in reachable screens  
**Observed behavior:** Splash/auth rendered at 320 × 568 without visible overflow or browser console errors. Authenticated screens could not be reached. Static inspection shows many dense Rows and eagerly expanded editors; only normal-size widget tests are present, with no systematic keyboard, landscape, textScale 2.0, long localization/user text, or large-data matrix.  
**Expected behavior:** All major flows remain usable on small phones, with keyboard, safe areas, orientation change, and accessible text scaling.  
**User impact:** Reported yellow/black overflow can hide fields or CTAs on common configurations.  
**Reproduction steps:** Not yet confirmed. Required matrix: 320/375/430 widths; short heights; portrait/landscape; keyboard on every form; text scaling 1.0/1.3/2.0; long template/food/profile strings; empty/loading/error/large lists.  
**Root cause:** Insufficient layout regression tests; likely candidates are dense set/macro input rows and fixed-height controls, but this remains a hypothesis until captured.  
**Affected files/components:** workout set/editor rows in `workouts_page.dart`, macro/meal editors in `nutrition_page.dart`, profile/onboarding form rows, Home four-button row (also removed by JMB-014).  
**Backend/database involvement:** None.  
**Recommended fix:** First add a deterministic responsive widget-test harness and capture the exact overflowing RenderFlex; then fix the local constraint with wrapping/breakpoints/flexible field widths. Do not blanket-wrap every screen.  
**Dependencies:** Reach authenticated fixtures without live credentials.  
**Tests required:** matrix above with `tester.takeException()` and overflow log assertions; golden snapshots for key breakpoints.  
**Estimated effort:** Medium

### JMB-018 — Onboarding state advances before local persistence succeeds

**Priority:** P2  
**Area:** Onboarding/local persistence  
**Status:** Confirmed  
**Observed behavior:** The persistence commit updates Riverpod state before awaiting SharedPreferences. If disk write fails, UI may have advanced while restart restores the earlier step. Backend submission ordering is otherwise improved: canonical profile is saved before Atlas and completion is gated.  
**Expected behavior:** Navigation-critical persistence either commits before advancement or carries a visible unsaved/retry state.  
**User impact:** Interrupted onboarding can unexpectedly regress after restart.  
**Reproduction steps:** Inject a failing SharedPreferences write during Next; observe in-memory step vs persisted snapshot.  
**Root cause:** Optimistic local state update has no rollback or durable-commit status.  
**Affected files/components:** `lib/features/onboarding/application/onboarding_controller.dart` persistence commit/navigation methods.  
**Backend/database involvement:** None until final submit.  
**Recommended fix:** Await durable save before advancing, or keep explicit `saving/error` state and rollback; preserve entered answer for retry.  
**Dependencies:** None.  
**Tests required:** write failure, retry, backward/forward, process restart per step, duplicate final submit.  
**Estimated effort:** Small

### JMB-019 — Offline health data is stored plaintext in SharedPreferences

**Priority:** P2  
**Area:** Privacy/local persistence  
**Status:** Confirmed  
**Observed behavior:** Offline outbox serializes full workout and food log payloads into SharedPreferences under a user-derived key (`app_repositories.dart:3064-3131`). SharedPreferences is not an encrypted sensitive-data store.  
**Expected behavior:** Minimize cached personal data, encrypt sensitive durable queues at rest, scope it to the current user, and delete it on logout/account deletion.  
**User impact:** Anyone with device backup/filesystem access can recover detailed exercise and eating history.  
**Reproduction steps:** Queue offline data and inspect application preferences on a test device.  
**Root cause:** Convenience persistence was used for a behavioral-data outbox without a privacy classification.  
**Affected files/components:** `OfflineOutboxStore`, local schedule/onboarding stores, logout/delete cleanup.  
**Backend/database involvement:** None, though server idempotency can reduce queued content.  
**Recommended fix:** Store only necessary fields in an encrypted platform-backed database/key; define retention; clear per-user data on logout/deletion; document threat model.  
**Dependencies:** Outbox redesign in JMB-003/JMB-002.  
**Tests required:** encryption/no plaintext, user isolation, logout/delete purge, migration from old keys, corruption.  
**Estimated effort:** Medium

### JMB-020 — Navigation is minimal and contains dead global search state

**Priority:** P2  
**Area:** Navigation/state architecture  
**Status:** Confirmed  
**Observed behavior:** MaterialApp exposes only Atlas and a debug onboarding preview beyond root; main tabs are an integer provider in one IndexedStack. There are no per-tab back stacks or active-workout/template routes. A global `SearchRepository` is always mock and `updateSearchQuery` has no UI caller.  
**Expected behavior:** Domain routes have typed arguments/restoration; deep links reach supported destinations; unused state is removed or wired.  
**User impact:** Back/deep-link semantics are weak, wrong-screen behavior is easier, and dead mock state obscures which search implementation is live.  
**Reproduction steps:** Inspect `lib/app/app.dart`, `home_shell.dart`, provider composition, and callers of `updateSearchQuery`.  
**Root cause:** Prototype tab navigation grew without a formal route/domain boundary.  
**Affected files/components:** `lib/app/app.dart`, `lib/core/navigation/app_flow.dart`, `home_shell.dart:16-30`, `app_state.dart`, `app_repositories.dart:2796-2840`, `3322-3324`.  
**Backend/database involvement:** None.  
**Recommended fix:** Add routes required by section 9, keep one shell nav, define back behavior/restoration, and delete unused global search state if feature-specific search remains canonical.  
**Dependencies:** JMB-004.  
**Tests required:** route map, deep link, back per tab, process restoration, active workout guard, unreachable-state scan.  
**Estimated effort:** Medium

### JMB-021 — Main screens and large editable collections build eagerly

**Priority:** P2  
**Area:** Performance/lifecycle  
**Status:** Confirmed architecture risk  
**Observed behavior:** `HomeShell` creates all five tab pages in an IndexedStack (`home_shell.dart:18-30`). Workouts and Nutrition spread all templates, meal sections, exercises, and sets into one page ListView rather than lazily built/slivered collections. Hidden tabs are retained and can initiate providers. Controllers/timers inspected are generally disposed correctly.  
**Expected behavior:** Preserve useful tab state while deferring unnecessary fetch/build work; virtualize large history/template/food lists; profile rebuild cost.  
**User impact:** Startup and input latency will worsen as logs/templates grow, especially on lower-end devices.  
**Reproduction steps:** Populate many templates/exercises/food entries and profile Flutter rebuild/layout counts and memory.  
**Root cause:** Screen composition assumes small prototype datasets.  
**Affected files/components:** `home_shell.dart:18-30`, `workouts_page.dart:47-253`, `nutrition_page.dart`, History.  
**Backend/database involvement:** Pagination needed for history/search/templates.  
**Recommended fix:** Measure first; lazy-create tabs where appropriate, paginate server collections, use builders/slivers, and isolate frequently edited rows/providers.  
**Dependencies:** Data model/route split.  
**Tests required:** performance fixture with hundreds of rows, rebuild counters, scroll/input benchmark, tab lifecycle.  
**Estimated effort:** Medium

## 7. P3 — Low-Priority Issues

### JMB-022 — Documentation and file boundaries do not match release complexity

**Priority:** P3  
**Area:** Maintainability/documentation  
**Status:** Confirmed  
**Observed behavior:** README remains Flutter boilerplate; the endpoint `.docx` and actual client routes differ; core repositories and app state are multi-thousand-line files containing networking, mapping, caching, queueing, validation, and provider composition. Unused assets and mock repositories remain in production composition.  
**Expected behavior:** A repository map, environment/runbook, authoritative API spec, generated models where appropriate, and smaller domain services make invariants reviewable.  
**User impact:** Indirect: changes are harder to review and regressions easier to introduce.  
**Reproduction steps:** Compare README/docs, section 10 inventory, and file responsibilities.  
**Root cause:** Prototype growth outpaced architecture documentation and modularization.  
**Affected files/components:** `README.md`, `BACKEND DOCUMENTATION.docx`, `lib/core/repositories/app_repositories.dart`, `lib/core/navigation/app_state.dart`, unused `plate_logo.png`/`statue_hero.png`.  
**Backend/database involvement:** OpenAPI and migration ownership documentation.  
**Recommended fix:** After functional stabilization, document supported modes/endpoints and split by domain without creating duplicate sources of truth.  
**Dependencies:** Avoid large refactor before P0/P1 behavior is covered.  
**Tests required:** Architecture/import rules and contract-generation checks where useful.  
**Estimated effort:** Medium

## 8. Core Flow Assessment

### Authentication

**Status:** Blocked for production verification.  
**What works:** Supabase SDK initialization; bootstrap deliberately clears ready state and calls the canonical profile route before authenticated navigation; auth page has blocking provisioning error and retry behavior with widget coverage.  
**What fails:** Backend invariant cannot be verified; FastAPI-mode session is memory-only; raw errors can surface.  
**Root cause:** Missing backend repository/deployment proof and duplicated readiness state.  
**Required fix:** JMB-001, JMB-010, JMB-013.  
**Dependencies:** Disposable integration environment and backend source.

### Onboarding

**Status:** Frontend path is substantially covered; end-to-end persistence unverified.  
**What works:** Dietary preference is a centralized enum with exactly omnivore/vegetarian/vegan/keto/other; selection is required, serialized by wire value, stored in onboarding state/persistence, and profile payload validation rejects missing/invalid state. Profile saves before Atlas; Atlas failure remains recoverable.  
**What fails:** Backend 422/transaction/flag behavior cannot be proven; durable local step commit is optimistic; gate later infers completion from fields.  
**Root cause:** Backend boundary plus two completion definitions.  
**Required fix:** Make backend flag canonical and make local advancement durable.  
**Dependencies:** JMB-001/JMB-010/JMB-018.

### Home

**Status:** Renders, but uses ambiguous/stale data and duplicate controls.  
**What works:** Clear dashboard structure, persistent shell, contextual links, bottom content padding.  
**What fails:** Duplicate footer, no mascot, silent agent fallback, and `hasWorkout` can be inferred from latest completed log rather than a current plan.  
**Root cause:** Aggregate draft mixes latest log/template/dashboard fallback.  
**Required fix:** JMB-014/JMB-015/JMB-016 and truthful plan state.  
**Dependencies:** Reliable data sources.

### Workout templates

**Status:** Basic create/edit/delete client mechanics exist; persistence reliability is insufficient.  
**What works:** Validation, exercise ID resolution, auth retry, rich payload, guarded save button, optional read-back, repository tests.  
**What fails:** Null server ID can be accepted, authoritative empty is ignored in favor of cache, unsaved draft is volatile, actual deployed contract unavailable.  
**Root cause:** Weak response validation and fallback semantics.  
**Required fix:** JMB-006.  
**Dependencies:** API contract and provisioning.

### Active workout

**Status:** Major feature incomplete.  
**What works:** A template can seed editable exercises/sets and in-progress fields.  
**What fails:** No dedicated route/page, rest timer, recovery, autosave, summary, or discard; builder remains visible; finish duplicated.  
**Root cause:** Domain concepts are conflated.  
**Required fix:** Section 9 / JMB-004/JMB-005.  
**Dependencies:** Active-session contract and state owner.

### Workout logging

**Status:** Online happy path has client coverage; failure truthfulness is broken.  
**What works:** Validation, auth header/retry wrapper, rich POST, response mapping, latest-log load.  
**What fails:** Offline returns success, duplicate replay risk, one-record history, missing application-user behavior unverified.  
**Root cause:** Mutation result lacks sync state/idempotency.  
**Required fix:** JMB-001/JMB-003/JMB-011.  
**Dependencies:** Backend ID and transaction contract.

### Nutrition logging

**Status:** Not safe for production mutation.  
**What works:** Meal grouping, quantity/macro editors, food selection, daily summary calculation, client repository tests.  
**What fails:** Non-atomic replacement, obscure Save day action, false remote success, no undo, no historical date selection, hydration not persisted.  
**Root cause:** Client-side diary replacement substitutes for a transactional log API.  
**Required fix:** JMB-002/JMB-008.  
**Dependencies:** Atomic backend API before UX polish.

### Search

**Status:** UI path exists but errors are materially broken.  
**What works:** Trim/lowercase, query encoding through Dio, debounce, stale-result gate, selectable results.  
**What fails:** All transport/status failures become empty; auth/pagination contract uncertain; unused global mock search coexists with feature search.  
**Root cause:** Broad catch and split search architecture.  
**Required fix:** JMB-007/JMB-020.  
**Dependencies:** Endpoint contract.

### Analytics

**Status:** Prototype only.  
**What works:** Basic empty-state coaching and derived local summaries.  
**What fails:** Only latest workout is stored for History, consistency/Atlas are mocks, no authoritative date-range model.  
**Root cause:** Mock provider composition and singular workout draft.  
**Required fix:** JMB-011.  
**Dependencies:** Reliable historical writes.

### Profile

**Status:** Frontend edit path exists; backend truth unverified.  
**What works:** Canonical profile model and payload mapping, dietary selector/wire enum, save error handling, logout/delete UI.  
**What fails:** Invalid/missing returned preference is displayed as Omnivore by default and can be overwritten on save; raw backend diagnostics can leak.  
**Root cause:** UI default hides malformed server state.  
**Required fix:** Display a repair/selection requirement for invalid profile state; typed safe errors.  
**Dependencies:** JMB-001/JMB-013.

### Account deletion

**Status:** Frontend adapter exists; end-to-end behavior unavailable.  
**What works:** Confirmation and local state reset paths have mock tests.  
**What fails:** Actual `/account`, Auth admin removal, cascade and orphan behavior are undocumented/unverified.  
**Root cause:** Missing backend source/spec parity.  
**Required fix:** JMB-012.  
**Dependencies:** Real schema and controlled accounts.

## 9. Workout Flow Redesign Requirements

This is an information-architecture correction, not a visual redesign.

### Corrected route map

```text
/app/workouts                         Saved templates, quick start, schedule summary
/app/workouts/templates/new           Template builder (new reusable structure)
/app/workouts/templates/:id/edit      Template builder (existing reusable structure)
/app/workouts/session/:sessionId      Dedicated active workout
/app/workouts/session/:sessionId/end  Review/finish summary
/app/workouts/history                  Paginated completed workouts
/app/workouts/history/:logId           Read-only completed workout detail
/app/program                           Generated program and generation status
```

The original persistent shell navigation remains. The active-workout route may sit above the shell so accidental tab switching cannot imply session completion; if tabs remain accessible, it needs a persistent “Workout in progress” affordance and back/discard guard.

### Domain and state ownership

- **Template:** reusable name, ordered exercises, default set targets, stable server template ID. Owned by a template editor provider with dirty/save/error state. Never contains live completion timestamps.
- **Active session:** one stable session ID, source template ID (optional), actual sets/reps/load/notes, started timestamp, rest-timer deadline, revision, local checkpoint, remote sync state. Owned by a keep-alive active-session controller/repository, not the template editor.
- **Completed workout:** immutable historical snapshot with server log ID, ended timestamp, totals, and sync status. Created exactly once when finish succeeds/idempotently reconciles.
- **History:** paginated collection of completed records plus detail cache. It must not reuse the active draft.
- **Generated program:** plan/schedule source with its own generation state. Starting a program day creates an active session; editing a template is an explicit separate action.

### Expected flows

```text
Workout tab → choose template/quick start → Start
→ create/resume session → dedicated active page
→ log sets + timestamp-based rest timer → checkpoint/autosave
→ Finish → review → idempotent completion
→ synced/pending result → history detail and analytics refresh
```

```text
Workout tab → Create template or explicit Edit
→ template builder → validate → guarded save/read-back
→ return to saved templates with authoritative ID
```

Required safeguards: only one active session per user unless product explicitly supports more; process-death recovery; discard confirmation; no template mutation from session edits; stable mutation IDs; pending-sync status; completion refresh invalidates history/analytics rather than overwriting an aggregate draft.

## 10. API Contract Mismatches

The “actual” column is based on the supplied endpoint-index document only. The live OpenAPI and server source were unavailable, so an undocumented call is **uncertain**, not proof of a 404.

| Frontend Call | Expected Contract | Actual Backend Contract | Problem | Priority |
| ------------- | ----------------- | ----------------------- | ------- | -------- |
| `POST /auth/register` | Credentials → token/session | Listed, schema unavailable | FastAPI session memory-only; provisioning linkage unknown | P1 |
| `POST /auth/login` | Credentials → refreshable session | Listed, schema unavailable | Cold restoration unavailable in FastAPI client mode | P1 |
| `GET /supabase/profile` | JWT-derived idempotent provision/reconcile; stable app user/profile | Listed as profile GET; reconciliation not documented in endpoint index | Central invariant cannot be verified | P0 |
| `POST /supabase/profile` | Validated canonical profile; optional atomic onboarding flag | Listed; transaction and enum behavior unavailable | Client contract exceeds verified backend evidence | P0 |
| `PATCH /atlas/profile` | Partial authenticated profile/metrics update | Not listed in endpoint index | Route/status uncertain | P1 |
| `POST /atlas/onboard` | JWT-derived onboarding including dietary preference | Listed | Real validation/transaction unavailable | P0 dependency |
| `GET /atlas/metrics` | Authenticated metrics shape | Not listed | Fallback may hide missing route | P2 |
| `POST /programs/generate` | Authenticated generation after profile save | Not listed | Deployability uncertain | P1 |
| `GET /agent/context` | Dashboard context | Listed | Failure becomes local draft/empty | P2 |
| `GET /workout-templates` | Authoritative list, including valid empty list | Listed | Client substitutes cache for empty | P1 |
| `POST /workout-templates` | Validated template → canonical object with `template_id` | Listed | Client accepts missing ID | P1 |
| `PATCH/DELETE /workout-templates/:id` | Owned update/delete | Listed generally | Ownership/RLS and response shape unavailable | P1 dependency |
| `GET/POST/PATCH/DELETE /workout-schedule[...]` | Authenticated cross-device schedule | Not listed | 404/network silently becomes local | P1 |
| `GET /exercises/search?q=` | Search results, documented auth/pagination | Search listed | Client has no auth and hides every failure | P1 |
| `GET /workout-logs` | Paginated completed history | Listed | Client keeps only newest item | P1 |
| `POST /workout-logs` | Idempotent completion returning stable ID | Listed | No transmitted idempotency status; offline false success | P1 |
| `PATCH /workout-logs/:id` | Owned metadata update | Listed generally | Actual nested-set semantics unavailable | P1 dependency |
| `GET /workout-logs/trends` | Dated aggregate trends | Not listed | Analytics route uncertain/fallback-prone | P1 |
| `GET /food/search?q=` | Search results, documented auth/pagination | Food search listed | Client hides errors and auth expectation | P1 |
| `GET /food-log` and summary | Authoritative dated log/summary | Food log listed | Client hardcodes today and has fallback aggregation | P2 |
| Multiple `DELETE/PATCH/POST /food-log[...]` | Atomic day mutation | Individual food-log routes listed; no atomic batch documented | Client cannot guarantee rollback or conflict safety | P0 |
| `POST /chat/stream` | Stream contract | Only standard chat listed | Route/stream framing uncertain | P2 |
| `DELETE /chat` | Authenticated history deletion | Listed | Server ownership unverified | P2 |
| `DELETE /account` | JWT-derived idempotent normal/orphan deletion | Not listed | Critical lifecycle contract unavailable | P1 |
| `GET /health` under configured `/api/v1` | Fast health response | Endpoint index says root `/health` | Prefix ambiguity; live call timed out | P1 release ops |

Additional documented but not clearly used by the current frontend include `/auth/me`, generic `/exercises` list/detail/create, `/workouts`, custom meals, meals, split recommendation, and Supabase workouts. This drift should be resolved from generated OpenAPI, not by maintaining another hand-written list.

Across calls, the frontend generally uses `Authorization: Bearer` through `_requestWithSessionRetry` for protected repositories, but search is an exception. Failure handling is inconsistent: mutations often throw verbose diagnostics, loads often default silently, schedule falls back locally, and offline writes return normal success-shaped objects.

## 11. State-Management Risks

1. **Auth duplication:** session exists in auth SDK/repository, `authSessionProvider`, and `AppDraftState.session`; readiness is separately stored as booleans.
2. **Onboarding duplication:** backend `onboarding_completed`, local onboarding persistence, inferred profile completeness, and `forceShowOnboardingProvider` can disagree.
3. **Workout conflation:** one `WorkoutLogDraft` represents active and latest completed workout; templates are held both as list and selected editor draft.
4. **Nutrition baseline risk:** local whole-day list can replace an unknown/stale remote baseline; cache and outbox have no revision.
5. **Offline mutation ambiguity:** repositories return domain objects without persisted/pending status.
6. **Cache-over-server risk:** template server `[]` loses to cache; recoverable loads lose provenance.
7. **Schedule divergence:** local store is both fallback and apparent success, without sync metadata.
8. **Startup partial-state erasure:** `_loadOrDefault` turns failures into genuine-looking empties.
9. **Mock production composition:** consistency, Atlas, and global search are always mock providers.
10. **Home aggregate ambiguity:** dashboard merges agent context and local draft, and latest completed log can imply an available workout plan.
11. **Profile enum masking:** invalid/missing dietary data is rendered as Omnivore in profile UI, which can overwrite malformed server state.
12. **Onboarding disk race:** visible step advances before SharedPreferences commit.
13. **Static capability flag:** one unsupported schedule response disables remote scheduling for the process, outside user/session scope.
14. **Outbox replay ordering:** per-item sequential replay has no server transaction/idempotency guarantee; crash after commit/before local removal can repeat.
15. **Navigation state:** integer tab provider is not route/restoration state; active-session navigation cannot be represented.

## 12. UI and Responsive Defects

| Screen/condition | Defect/evidence | Status | Direction |
| --- | --- | --- | --- |
| Home, bottom of scroll | Four `_HomeNavigation` buttons duplicate persistent shell bar | Confirmed | Remove content footer; retain shell bar |
| Home hero | Exact shared `JimCompanionAvatar` absent | Confirmed | Reuse existing component only |
| Workouts after Start | Active editor, schedule, library, and template builder on one scroll page | Confirmed | Dedicated active route |
| Workouts active | Two Finish/Log controls | Confirmed | One session-scoped primary finish action |
| Nutrition after selection | No adjacent obvious “Log food”; header Save day controls whole diary | Confirmed | Explicit entry review/log action after atomic API exists |
| Nutrition empty/large day | All meal sections/editors are eager and page is long | Confirmed | Progressive empty sections/lazy list without hiding meal grouping |
| Search API failure | Looks the same as zero matches | Confirmed | Distinct error/offline/no-result states |
| Bootstrap resource failure | Empty cards/lists look authoritative | Confirmed | Stale/error labels and retry |
| Small 320 × 568 splash/auth | No visible overflow or browser warning in inspected flow | Not reproduced | Preserve as regression fixture |
| Authenticated small screen, keyboard, text scale 2.0 | Not dynamically reachable; dense rows are candidates | Unable to verify | Add fixture-driven matrix before local fixes |
| Long template/exercise/food values | Fitted/Row constraints are inconsistent and untested | Possible | Capture exact RenderFlex and add breakpoints/wrapping |
| Content behind bottom nav | Shared scaffold reserves 120 px; no confirmed clipping | Not reproduced | Add scroll-end/safe-area assertions |

The audit intentionally does not recommend blanket `SingleChildScrollView` changes. Most pages already scroll. The likely defects are local horizontal constraints, fixed control heights, keyboard/text-scale combinations, and eager nested content.

## 13. Missing Test Coverage

| Flow | Existing Coverage | Missing Coverage | Priority |
| ---- | ----------------- | ---------------- | -------- |
| Signup/provisioning | Frontend mock/adapter and provisioning-gate tests | Real Auth + DB row, concurrency, migration, RLS | P0 |
| Dietary onboarding | Enum, persistence, validation, serialization widget/unit tests | Real backend 422/transaction and DB enum/default | P0 |
| Session bootstrap | Frontend repaired/missing/failure cases | Deployed orphan repair, cold restart both auth modes, refresh race | P0/P1 |
| Nutrition save | Payload/repository/UI unit coverage | Failure-after-delete rollback, conflict/revision, idempotent batch | P0 |
| Workout logging | State and repository payload/offline queue tests | UI pending state, lost-response replay, backend FK/provision repair | P1 |
| Template saving | Validation/payload/read-back unit tests | Missing-ID response, authoritative empty, restart/sign-out, live backend | P1 |
| Active workout | Inline state editing tests | Dedicated route, timer, autosave, lifecycle recovery, discard, summary | P1 |
| Food logging | Editors/repository tests | Complete CTA flow, pending/error/undo, hydration, date/history | P1 |
| Search | Some request gate/repository behavior | Error vs empty, auth, cancellation, pagination, both selection flows E2E | P1 |
| Account deletion | Frontend normal/orphan mock tests | Actual Auth admin/cascade/orphan/idempotency/security | P1 |
| Analytics/history | Basic widget/state tests | Multiple records, pagination, date ranges, live data sources | P1 |
| Bottom navigation | Basic shell behavior may be indirectly covered | Assert one primary nav and back/deep-link semantics | P2 |
| Mascot reuse | Component appears in other widget tests | Home exact-component regression/golden | P2 |
| Responsive overflow | Normal widget sizes | 320/375/430, landscape, keyboard, text scale, long/large/error states | P2 |
| Privacy/error redaction | Limited diagnostics tests | No-secret/profile redaction and release-mode presentation | P1 |
| Android build | None in this environment | CI build with configured SDK | P1 release |

## 14. Recommended Fix Order

### Stage 1 — Data integrity and authentication

- Address JMB-001, JMB-012, and the server half of JMB-010.
- Obtain the backend/Supabase repository, inventory the real schema/RLS/triggers, implement one provisioning service and safe migration, verify normal/orphan deletion.
- Address JMB-013 early so subsequent instrumentation is safe.
- Validation: disposable full-stack signup, retry, orphan repair, profile flag, RLS isolation, deletion and structured logs.

### Stage 2 — Core write reliability

- Address JMB-002 first, then JMB-003, JMB-006, JMB-009, and local privacy JMB-019.
- Add transaction/idempotency/version semantics server-side and typed mutation states client-side before changing success copy.
- Validation: injected failure at every mutation boundary, lost response, duplicate replay, restart, offline/online, expired token.

### Stage 3 — Workout architecture

- Address JMB-004 and JMB-005 using section 9; then update JMB-011’s workout history source.
- Domain/route split comes before active-workout visual polish.
- Validation: template edit vs start, durable active session, timer, one finish, completion idempotency, history/analytics refresh.

### Stage 4 — Nutrition and search

- With atomic nutrition available, address JMB-008 and JMB-007.
- Add explicit log action, truthful pending/error states, date/hydration semantics, cancellable typed search.
- Validation: complete entry journey, totals, edit/delete/undo, search error/no-result, offline recovery.

### Stage 5 — Navigation, dashboard, and analytics consistency

- Address JMB-010 client state machine, JMB-016, JMB-011, JMB-020, then JMB-014 and JMB-015.
- Keep the persistent footer; remove only the duplicate scrolling control; reuse exact mascot.
- Validation: cold bootstrap, partial resource failure, tab/back/deep link, honest history/metrics, one nav.

### Stage 6 — Responsive polish, performance, and hardening

- Reproduce/fix JMB-017 locally, measure and address JMB-021, then JMB-018/JMB-022 cleanup.
- Validation: device/text/keyboard/data-state matrix, performance fixtures, analyzer/tests/builds on all CI targets, full E2E release candidate.

## 15. Quick Demo-Stabilization Plan

### Must fix before a controlled product demo

- Verify API health and JMB-001 provisioning against a disposable test user; do not rely on the contract document.
- Prevent nutrition mutation unless JMB-002 is fixed, or use preseeded read-only nutrition data.
- Change offline write UX to pending/failed rather than “saved”; for a minimal demo safeguard, disable core submit when connectivity/backend health is unknown.
- Validate template create returns an ID and preload a known template.
- Remove the duplicate Home footer and reuse the exact mascot if Home visual expectations are part of the demo.
- Redact raw diagnostics from all user-visible errors.

### Acceptable temporary safeguards

- Run an explicit preflight against health, bootstrap/profile, template list, and workout-log endpoints.
- Use a dedicated disposable test account and reset it before the demo.
- Label schedule as device-local or hide schedule if backend support is not verified.
- Keep analytics labeled as preview or hide mock streak/Atlas values.
- Disable offline mode and warn before connectivity loss rather than claiming synchronization.

### Features to hide if still broken

- Nutrition Save day and deletion until atomic save is deployed.
- Account deletion in the demo build until a disposable end-to-end deletion passes (production cannot hide this compliance requirement).
- Schedule sync, generated program, trends, and streaming chat if their routes remain undocumented/unreachable.
- “Resume workout” claims until active-session recovery exists.

### Exact pre-demo retest

1. Fresh signup → exactly one Auth user and one application row.
2. Complete onboarding with vegetarian → profile/DB reads vegetarian after restart.
3. Home loads with one persistent footer and intended mascot.
4. Create template → response ID → reload/edit/start.
5. Complete one workout online → stable ID → history reload.
6. Search known exercise and food plus no-result/error cases.
7. If enabled, log/edit/delete food and verify totals/database atomically.
8. Refresh token/restart and reload same user.
9. Delete disposable account and confirm Auth plus related data removal.

## 16. Production-Readiness Checklist

- [ ] Real FastAPI repository, OpenAPI, schema, migrations, triggers, RLS, and backend tests reviewed.
- [ ] Idempotent JWT-derived provisioning/reconciliation deployed and concurrency-tested.
- [ ] Dietary enum/default/NOT NULL/uniqueness invariants verified in an existing environment migration.
- [ ] All downstream writes resolve application identity server-side.
- [ ] Normal and orphan account deletion verified, secure, and idempotent.
- [ ] Nutrition day mutation is atomic and conflict-safe.
- [ ] Workout/nutrition offline states are truthful and replay is server-idempotent.
- [ ] Core writes never display success before durable remote commit or explicit pending state.
- [ ] Template create requires a stable server ID and cache respects authoritative empty data.
- [ ] Schedule contract is deployed or feature is explicitly local-only.
- [ ] Dedicated recoverable active-workout session and one finish flow implemented.
- [ ] Workout history and analytics use authoritative multi-record data, not mocks.
- [ ] Search distinguishes loading, empty, cached/offline, and error; auth/pagination confirmed.
- [ ] Canonical auth/onboarding readiness state replaces duplicated booleans/inference.
- [ ] Startup resource errors remain observable and retryable.
- [ ] Raw request/response/profile/token data is redacted from UI and logs.
- [ ] Sensitive offline queues are encrypted/minimized and purged on logout/deletion.
- [ ] Exact shared mascot is present on Home; one persistent bottom navigation remains.
- [ ] Reported overflow reproduced and all major screens pass the responsive/accessibility matrix.
- [ ] iOS, Android, and web builds pass in CI.
- [ ] Full-stack integration/E2E passes signup → onboarding → restart → workout → program → nutrition → deletion and orphan repair.
- [ ] Monitoring/alerts cover provisioning, sync rejection, orphan repair, write failure, and deletion without sensitive payloads.
- [ ] Endpoint docs are generated/current and release runbook includes migrations/rollback/preflight.

## 17. Commands and Results

All results below are actual results from this audit. Secrets were not printed.

| Command/inspection | Result |
| --- | --- |
| `git status --short`, branch/HEAD/diff inspection | `main` at `e8d5cb4`; pre-existing dirty tree, 50-file diff plus untracked files; audit preserved it |
| Repository `rg`/`rg --files`, targeted `nl -ba` tracing | Flutter frontend located; no FastAPI/SQL migration/RLS/trigger/backend-test source found |
| `.env` variable-name/config inspection | Required client variable names present; values not recorded in report |
| `flutter analyze` | Exit 0, “No issues found”; dependency tool noted 49 newer incompatible versions |
| `dart format --output=none --set-exit-if-changed .` | Exit 0; 54 files checked, 0 changed |
| `flutter test` | Exit 0; all **113 tests passed** |
| `flutter build web --release` | Exit 0; release web build completed; Wasm dry run succeeded |
| `flutter build ios --simulator --debug` | Exit 0; built `Runner.app` |
| `flutter build apk --debug` | Exit 1; Android SDK not found and `ANDROID_HOME` missing |
| `flutter devices` | macOS and a wireless iPhone listed; LAN discovery/developer-mode warnings for device connectivity |
| `dart run tool/live_smoke_check.dart` | Exit 1; config variables detected, service root and API health timed out; protected checks skipped because no bearer token was supplied |
| OpenAPI reachability attempt against configured service | Timed out/no usable schema returned |
| Local `build/web` served and inspected in app browser at 320 × 568 | Splash used exact shared CustomPainter mascot; auth rendered/scrollable; no visible overflow or browser console warning/error in reachable flow; authenticated screens unavailable without credentials |
| Backend `pytest`, `ruff`, `mypy`, backend startup | Not run: repository contains no backend source/config |

No automated test result proves the deployed FastAPI/Supabase behavior; the passing Flutter suite relies on mocks/adapters for those boundaries.

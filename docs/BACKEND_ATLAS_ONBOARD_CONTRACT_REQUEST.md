# Backend Authentication and Onboarding Contract

## Repository boundary

This checkout contains the JimBro Flutter client only. The FastAPI source,
Supabase schema, migrations, triggers, and backend tests are not present. The
client contract below is therefore the required deployment companion for the
backend repository; it is not a substitute for a backend migration.

## Dietary preference

The canonical enum is exactly:

```text
omnivore
vegetarian
vegan
keto
other
```

Completed profile/onboarding requests always include one of these values as
`dietary_preference`. Missing, `null`, and unknown values must return HTTP 422
with `INVALID_DIETARY_PREFERENCE`; they must not be coerced to `omnivore`.

Provisioning that runs before onboarding data exists may use `omnivore` as the
temporary database-compatible value. A completed onboarding write replaces it
with the user's selection.

## Canonical application-user bootstrap

The Flutter bootstrap calls authenticated `GET /api/v1/supabase/profile`
before entering the authenticated application. This existing profile route
must call the backend's single idempotent user-provisioning service.

The service must:

- derive the Auth UUID and email from the verified bearer JWT;
- insert the missing `public.users` row with every required column populated,
  including provisional `dietary_preference = 'omnivore'`;
- return an existing row without overwriting it;
- use an upsert/transaction-safe equivalent backed by a unique Auth UUID;
- log `AUTH_USER_RECONCILED` when it repairs an orphan, without tokens or
  sensitive profile data.

The successful response must include a stable application-user identifier:

```json
{
  "success": true,
  "data": {
    "user_id": "application-user-id",
    "auth_user_id": "supabase-auth-uuid",
    "dietary_preference": "omnivore",
    "onboarding_completed": false,
    "reconciled": true
  }
}
```

If reconciliation fails, return a non-2xx response with
`USER_PROVISIONING_FAILED`. Do not return a synthetic profile or HTTP 200.

## Profile and Atlas onboarding

`POST /api/v1/supabase/profile` is the canonical profile write. It must validate
the entire request before mutation, ensure the application user exists, update
the dietary preference, and set `onboarding_completed = true` in the same
transaction only when the request includes that flag and all required profile
fields were saved.

`POST /api/v1/atlas/onboard` is bearer-authenticated. The request contains
profile fields, including `dietary_preference`, but never a password,
client-provided auth UUID, or resubmitted account email. FastAPI must derive
identity from the JWT.

Example request:

```json
{
  "username": "string",
  "age": 30,
  "height_cm": 180,
  "weight_kg": 80,
  "sex": "male",
  "activity_level": "moderately_active",
  "fitness_goal": "gain_muscle",
  "experience_level": "intermediate",
  "dietary_preference": "vegetarian",
  "available_time_min": 45,
  "equipment_access": "full_gym",
  "constraints_json": []
}
```

Atlas/program-generation failure may be returned as a separate recoverable
error after the canonical profile commits. It must not roll back a successfully
saved profile, and it must not claim profile success if the profile write failed.

## Downstream identity and deletion

Workout, schedule, nutrition, analytics, Atlas, and program endpoints must
resolve the application user from the verified JWT through the same
provisioning service. The Flutter client intentionally does not send `user_id`
for schedule writes.

`DELETE /api/v1/account` must be idempotent and JWT-derived. It must delete a
normal account and an orphaned Auth account. A missing `public.users` row is not
an error and must not prevent deletion of the Supabase Auth user.

## Migration invariants

The backend migration must be authored against the real schema and should:

1. ensure the enum/check constraint contains only the five values above;
2. repair any null dietary preferences to `omnivore` before enforcing `NOT NULL`;
3. give provisioning a valid `omnivore` default where the trigger/service runs
   before onboarding;
4. enforce uniqueness on the Supabase Auth UUID reference;
5. preserve existing valid values and intentional foreign-key cascades;
6. update any Auth trigger to populate all mandatory columns and make failures
   observable.

Required backend tests cover idempotent create/retry, orphan repair without
overwrite, all five dietary values, 422 for missing/null/invalid onboarding
values, failed-write onboarding flags, workout writes after repair, and normal
plus orphan account deletion.

# Backend Atlas Onboarding Contract Request

## Status

The JimBro Flutter frontend now preserves onboarding/profile consistency safely:

- `POST /atlas/onboard` is called only when the current email/password auth flow still has a transient in-memory password.
- Restored Supabase/FastAPI sessions do not expose plaintext password, so the frontend does not call `/atlas/onboard` in that state.
- When Atlas onboarding cannot be called, the app saves the canonical profile locally/in app state, uses local profile-based metrics as a fallback, and shows a sync-pending message.
- Passwords, bearer tokens, and environment values are not logged. Debug diagnostics only report non-secret status such as missing credential categories.

## Current Backend Blocker

The deployed backend currently requires this request body for `POST /atlas/onboard`:

```json
{
  "username": "string",
  "email": "string",
  "password": "string",
  "age": 13,
  "height_cm": 100,
  "weight_kg": 30,
  "sex": "male",
  "activity_level": "lightly_active",
  "fitness_goal": "maintain",
  "experience_level": "novice",
  "available_time_min": 15,
  "equipment_access": "full_gym",
  "constraints_json": ["knee_sensitive"]
}
```

Requiring `password` is incompatible with authenticated Supabase JWT sessions. After login or app restore, the frontend correctly has a bearer token/session, but it must not store or resend a plaintext password.

## Requested Backend Change

Update `POST /atlas/onboard` to authenticate from `Authorization: Bearer <supabase_jwt>` and derive user identity from the validated token/session.

The request body should require only onboarding/profile fields:

```json
{
  "age": 13,
  "height_cm": 100,
  "weight_kg": 30,
  "sex": "male",
  "activity_level": "lightly_active",
  "fitness_goal": "maintain",
  "experience_level": "novice",
  "available_time_min": 15,
  "equipment_access": "full_gym",
  "constraints_json": ["knee_sensitive"]
}
```

Optional fields:

```json
{
  "username": "string"
}
```

Backend should derive:

- `user_id` from the authenticated bearer token subject/session user.
- `email` from the authenticated token/session user.
- `username` from request body if supplied, otherwise profile/user metadata/email prefix.

Backend should not require:

- `password`
- frontend-resubmitted email
- frontend-resubmitted user id

## Proposed Response Shape

Return updated profile and Atlas metrics in one response when possible:

```json
{
  "success": true,
  "data": {
    "profile": {
      "user_id": "uuid",
      "username": "string",
      "email": "user@example.com",
      "age": 13,
      "height_cm": 100,
      "weight_kg": 30,
      "sex": "male",
      "activity_level": "lightly_active",
      "fitness_goal": "maintain",
      "experience_level": "novice",
      "available_time_min": 15,
      "equipment_access": "full_gym",
      "constraints_json": ["knee_sensitive"],
      "updated_at": "2026-06-17T00:00:00Z"
    },
    "metrics": {
      "bmr": 1600,
      "tdee": 2200,
      "target_calories": 2200,
      "macros": {
        "protein_g": 120,
        "carbs_g": 250,
        "fat_g": 70
      },
      "hydration_l": 2.5,
      "updated_at": "2026-06-17T00:00:00Z"
    }
  }
}
```

If metrics cannot be generated immediately, return the saved profile and a clear non-fatal metrics status:

```json
{
  "success": true,
  "data": {
    "profile": {
      "updated_at": "2026-06-17T00:00:00Z"
    },
    "metrics": null,
    "metrics_status": "pending"
  }
}
```

`GET /atlas/metrics` may continue returning `404 ATLAS_METRICS_NOT_FOUND` before generation exists; the frontend treats that as "metrics pending" and uses local estimates.

## Compatibility Notes

The frontend currently sends this legacy-safe payload only when a transient password exists:

```json
{
  "username": "string",
  "email": "user@example.com",
  "password": "<redacted>",
  "age": 13,
  "height_cm": 100,
  "weight_kg": 30,
  "sex": "male",
  "activity_level": "lightly_active",
  "fitness_goal": "maintain",
  "experience_level": "novice",
  "available_time_min": 15,
  "equipment_access": "full_gym",
  "constraints_json": ["knee_sensitive"]
}
```

Once the backend accepts bearer-authenticated onboarding without password, the frontend can remove `password` from the Atlas onboarding DTO entirely.

## Acceptance Criteria

- `POST /atlas/onboard` succeeds with a valid bearer token and no `password` field.
- Backend derives user id/email from the token/session.
- `username` is optional or derived.
- Backend returns saved profile with `updated_at`.
- Backend returns metrics when available, or a non-fatal pending status.
- `GET /atlas/metrics` 404 for missing metrics remains non-fatal and documented.
- No backend logs print bearer tokens or plaintext passwords.
- Existing authenticated clients using Supabase JWT can complete onboarding after app restore.

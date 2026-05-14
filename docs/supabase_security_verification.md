# Supabase Security Verification

This checklist verifies that the REVV Supabase project is safe enough for a wider TestFlight beta. It focuses on Data API grants, RLS, and migration bootstrap reliability.

## Current Linked Project State

Last verified: 2026-05-14.

Applied to the linked remote project:

- `20260501003000_data_api_grants.sql`
- `20260501004000_security_advisor_cleanup.sql`
- `20260501005000_revoke_anon_user_data.sql`

Verified posture:

- `anon` can read route catalog data and execute route discovery.
- `anon` cannot read user run data.
- `authenticated` can insert runs, run details, feedback, saved routes, and route records, with RLS owner policies still restricting rows to `auth.uid()`.
- `increment_route_run_count` is available to `authenticated` only. This is intentional for the no-login beta flow because Supabase anonymous users are still authenticated users with `auth.uid()`.

## Local Preflight

Run these before pushing migrations to a staging or production project.

```sh
flutter test test/supabase_migrations_security_test.dart
supabase db reset --no-seed
supabase db lint --local
```

Notes:

- `supabase db reset` requires Docker Desktop to be running.
- If local reset fails, do not push migrations until the failing SQL is fixed.
- The Flutter migration security test is intentionally static. It catches missing RLS/GRANT guardrails even when Docker is unavailable.

## Remote Dry Run

Use the linked staging project first.

```sh
supabase db push --dry-run --linked
```

Expected:

- The pending migration list includes only migrations that have not already been applied.
- No SQL error is printed.
- No app secrets are printed or committed.

## Remote Apply

Apply only after the dry run looks correct.

```sh
supabase db push --linked
supabase db advisors --linked --type security
```

If the advisor reports missing grants or RLS, fix the migration and re-run the local preflight before applying again.

Known advisor warnings after the cleanup migrations:

- `postgis` installed in `public`: existing project posture. Moving PostGIS to an `extensions` schema is a larger DB migration and should not be rushed immediately before TestFlight.
- `spatial_ref_sys` RLS disabled: PostGIS-managed reference table. Treat as a known extension warning unless Supabase recommends a project-specific fix.
- PostGIS `st_estimatedextent` security-definer warnings: extension-owned functions. Do not alter them casually in the release branch.
- `increment_route_run_count` security-definer warning: app-owned function, now revoked from `anon` and granted to `authenticated` only. Keep it for beta, then consider moving route usage counting behind an Edge Function or stricter server-side path later.
- Anonymous auth policy warnings: REVV currently uses anonymous Supabase users for no-login beta testing. These warnings are expected while anonymous sign-in is enabled, but user tables still use `auth.uid() = user_id`.
- Password/MFA warnings: not beta-blocking while email/password login is not exposed in the app.

## Manual SQL Verification

Run this in Supabase SQL Editor or with `supabase db query`.

```sql
select
  relname,
  relrowsecurity
from pg_class
where relnamespace = 'public'::regnamespace
  and relname in (
    'curvy_roads',
    'runs',
    'run_details',
    'route_records',
    'route_feedback',
    'saved_routes',
    'discovered_routes',
    'edge_rate_limits'
  )
order by relname;
```

Every row should have `relrowsecurity = true`.

```sql
select
  has_table_privilege('anon', 'public.curvy_roads', 'select') as anon_can_read_routes,
  has_table_privilege('anon', 'public.runs', 'select') as anon_can_read_runs,
  has_table_privilege('authenticated', 'public.runs', 'insert') as auth_can_insert_runs,
  has_table_privilege('authenticated', 'public.run_details', 'insert') as auth_can_insert_details,
  has_table_privilege('authenticated', 'public.route_feedback', 'insert') as auth_can_insert_feedback,
  has_table_privilege('authenticated', 'public.saved_routes', 'insert') as auth_can_insert_saved_routes;
```

Expected:

- `anon_can_read_routes = true`
- `anon_can_read_runs = false`
- Authenticated insert checks are `true`; RLS policies still restrict rows to `auth.uid() = user_id`.

```sql
select
  has_function_privilege(
    'anon',
    'public.find_curvy_roads(double precision,double precision,integer,double precision,integer)',
    'execute'
  ) as anon_can_find_routes,
  has_function_privilege(
    'authenticated',
    'public.increment_route_run_count(text)',
    'execute'
  ) as auth_can_increment_runs,
  has_function_privilege(
    'anon',
    'public.consume_edge_rate_limit(text,text,integer,integer)',
    'execute'
  ) as anon_can_consume_edge_rate_limit;
```

Expected:

- `anon_can_find_routes = true`
- `auth_can_increment_runs = true`
- `anon_can_consume_edge_rate_limit = false`

## App Smoke After Migration

Use a real build with `.env`.

```sh
flutter run --release --dart-define-from-file=.env
```

Verify:

- Supabase initializes without permission errors.
- Route finder loads Montreal routes.
- Run summary upload succeeds.
- Run detail upload succeeds, then local pending detail is removed.
- Turning off `클라우드 주행 기록 저장` prevents new detail uploads and purges pending payloads.

## Rollback Posture

For TestFlight beta, do not delete existing production data during migration work.

- Additive schema changes are preferred.
- RLS/GRANT fixes should be applied as new migrations.
- If a migration fails remotely, stop and inspect the SQL error before retrying.

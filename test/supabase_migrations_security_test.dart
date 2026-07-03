import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const coreMigration = 'supabase/migrations/20260501000000_security_rls.sql';
  const rateLimitMigration =
      'supabase/migrations/20260501001000_edge_rate_limits.sql';
  const routeContextMigration =
      'supabase/migrations/20260501002000_route_context_fields.sql';
  const grantsMigration =
      'supabase/migrations/20260501003000_data_api_grants.sql';
  const advisorCleanupMigration =
      'supabase/migrations/20260501004000_security_advisor_cleanup.sql';
  const revokeAnonMigration =
      'supabase/migrations/20260501005000_revoke_anon_user_data.sql';
  const regionRequestsMigration =
      'supabase/migrations/20260703070628_region_requests.sql';
  const activeMigrations = [
    coreMigration,
    rateLimitMigration,
    routeContextMigration,
    grantsMigration,
    advisorCleanupMigration,
    revokeAnonMigration,
    regionRequestsMigration,
  ];

  const userTables = [
    'runs',
    'run_details',
    'route_records',
    'route_feedback',
    'saved_routes',
    'discovered_routes',
  ];

  test('core migration creates user tables with RLS enabled', () {
    final sql = _readLower(coreMigration);

    for (final table in userTables) {
      expect(
        sql,
        contains('create table if not exists public.$table'),
        reason: '$table must be bootstrap-created by active migrations.',
      );
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
        reason: '$table must have RLS enabled in active migrations.',
      );
      expect(
        sql,
        contains('auth.uid() = user_id'),
        reason: '$table owner policy must scope access to auth.uid().',
      );
    }
  });

  test('security test inventory covers every active migration file', () {
    final migrationFiles =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .map((file) => file.path.replaceAll(r'\', '/'))
            .toList()
          ..sort();

    expect(migrationFiles, activeMigrations);
  });

  test('every created public table has RLS enabled in active migrations', () {
    final sql = activeMigrations.map(_readLower).join('\n');
    final createdTables = RegExp(
      r'create table if not exists public\.([a-z_]+)',
    ).allMatches(sql).map((match) => match.group(1)!).toSet();

    expect(createdTables, isNotEmpty);
    for (final table in createdTables) {
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
        reason: '$table must enable RLS in active migrations.',
      );
    }
  });

  test('route table is read-only through anon/authenticated Data API', () {
    final sql = _readLower(coreMigration);

    expect(
      sql,
      contains('alter table public.curvy_roads enable row level security'),
    );
    expect(sql, contains('create policy curvy_public_read'));
    expect(sql, contains('for select'));
    expect(sql, contains('to anon, authenticated'));
    expect(sql, isNot(contains('grant insert on public.curvy_roads to anon')));
    expect(
      sql,
      isNot(
        contains('grant select, insert, update, delete on public.curvy_roads'),
      ),
    );
  });

  test('Data API grants are explicit for app tables and RPCs', () {
    final sql = _readLower(grantsMigration);

    expect(sql, contains('grant usage on schema public'));
    expect(sql, contains('grant select on public.curvy_roads'));
    for (final table in userTables) {
      expect(sql, contains('public.$table'));
    }
    expect(sql, contains('to authenticated, service_role'));
    expect(sql, contains('grant execute on function public.find_curvy_roads'));
    expect(
      sql,
      contains('grant execute on function public.increment_route_run_count'),
    );
  });

  test('route context migration keeps route discovery read-only', () {
    final sql = _readLower(routeContextMigration);
    final grantsSql = _readLower(grantsMigration);

    expect(sql, contains('alter table curvy_roads'));
    expect(sql, contains('create or replace function find_curvy_roads'));
    expect(sql, contains('from curvy_roads'));
    expect(sql, isNot(contains('create table')));
    expect(
      sql,
      isNot(contains('grant select, insert, update, delete')),
      reason: 'Route context migration must not grant route writes.',
    );
    expect(
      grantsSql,
      contains('grant execute on function public.find_curvy_roads'),
    );
  });

  test('Edge rate-limit table is not client-accessible', () {
    final sql = _readLower(rateLimitMigration);

    expect(
      sql,
      contains('alter table public.edge_rate_limits enable row level security'),
    );
    expect(sql, contains('edge_rate_limits_no_client_access'));
    expect(sql, contains('for all using (false) with check (false)'));
    expect(
      sql,
      contains(
        'revoke all on function public.consume_edge_rate_limit(text, text, integer, integer)',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.consume_edge_rate_limit(text, text, integer, integer)',
      ),
    );
    expect(sql, contains('to service_role'));
  });

  test('Security advisor cleanup locks down app-owned functions', () {
    final sql = _readLower(advisorCleanupMigration);

    expect(sql, contains('alter function public.find_curvy_roads'));
    expect(sql, contains('set search_path = public'));
    expect(sql, contains('alter function public.set_curvy_roads_geometries()'));
    expect(
      sql,
      contains('alter function public.increment_route_run_count(text)'),
    );
    expect(
      sql,
      contains('revoke all on function public.increment_route_run_count(text)'),
    );
    expect(sql, contains('from public, anon'));
    expect(
      sql,
      contains(
        'grant execute on function public.increment_route_run_count(text)',
      ),
    );
    expect(sql, contains('to authenticated, service_role'));
    expect(sql, contains('to_regprocedure(\'public.rls_auto_enable()\')'));
  });

  test('anonymous role is explicitly revoked from user data tables', () {
    final sql = _readLower(revokeAnonMigration);

    expect(sql, contains('revoke all'));
    expect(sql, contains('from public, anon'));
    for (final table in userTables) {
      expect(sql, contains('public.$table'));
    }
    expect(sql, contains('grant select, insert, update, delete'));
    expect(sql, contains('to authenticated, service_role'));
  });

  test(
    'region requests allow anonymous insert only with rounded coordinates',
    () {
      final sql = _readLower(regionRequestsMigration);

      expect(
        sql,
        contains('create table if not exists public.region_requests'),
      );
      expect(
        sql,
        contains(
          'alter table public.region_requests enable row level security',
        ),
      );
      expect(sql, contains('create policy region_requests_anon_insert'));
      expect(sql, contains('for insert'));
      expect(sql, contains('to anon'));
      expect(sql, contains('with check (true)'));
      expect(sql, contains('lat_rounded'));
      expect(sql, contains('lng_rounded'));
      expect(sql, contains('numeric(4,1)'));
      expect(sql, isNot(contains('device')));
      expect(sql, isNot(contains('user_id')));
      expect(sql, isNot(contains('grant select')));
      expect(sql, isNot(contains('grant update')));
      expect(sql, isNot(contains('grant delete')));
      expect(sql, contains('grant insert on public.region_requests to anon'));
    },
  );
}

String _readLower(String path) => File(path).readAsStringSync().toLowerCase();

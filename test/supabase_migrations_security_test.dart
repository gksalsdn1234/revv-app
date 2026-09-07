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
  const crewWalkieMigration =
      'supabase/migrations/20260705063752_crew_walkie.sql';
  const crewWalkieRealtimeMigration =
      'supabase/migrations/20260705070001_crew_walkie_realtime.sql';
  const crewWalkiePresenceMigration =
      'supabase/migrations/20260706090000_crew_walkie_presence.sql';
  const learningLoopMigration =
      'supabase/migrations/20260707120000_learning_loop.sql';
  const v2DataShellsMigration =
      'supabase/migrations/20260707200000_v2_data_shells.sql';
  const telemetrySummaryMigration =
      'supabase/migrations/20260707220000_telemetry_summary.sql';
  const findCurvyRoadsSlimMigration =
      'supabase/migrations/20260712100000_find_curvy_roads_slim.sql';
  const exploredCellsMigration =
      'supabase/migrations/20260712201817_explored_cells.sql';
  const releaseHardeningMigration =
      'supabase/migrations/20260713082759_harden_release_data_boundaries.sql';
  const boundedRouteSearchMigration =
      'supabase/migrations/20260713120000_bound_route_search_and_canonical_geometry.sql';
  const accountDeletionMigration =
      'supabase/migrations/20260714062931_harden_account_deletion_and_rate_limit_retention.sql';
  const routeMapCoverageMigration =
      'supabase/migrations/20260715054211_expand_route_map_coverage.sql';
  const mapOnlyBoundaryMigration =
      'supabase/migrations/20260715141945_keep_map_segments_below_recommendation_threshold.sql';
  const quebecRegionRepairMigration =
      'supabase/migrations/20260716040000_repair_empty_quebec_regions.sql';
  const westernRoutePublicationMigration =
      'supabase/migrations/20260716043420_western_route_publication_v2.sql';
  const westernPublicationFixture =
      'supabase/tests/western_route_publication_v2.sql';
  const westernCatalogAllocationFixture =
      'supabase/tests/western_route_catalog_allocation_v2.sql';
  const westernLegacyBackfillFixture =
      'supabase/tests/western_route_publication_legacy_backfill.sql';
  const westernLegacyRejectFixture =
      'supabase/tests/western_route_publication_legacy_rejects_unmapped.sql';
  const activeMigrations = [
    coreMigration,
    rateLimitMigration,
    routeContextMigration,
    grantsMigration,
    advisorCleanupMigration,
    revokeAnonMigration,
    regionRequestsMigration,
    crewWalkieMigration,
    crewWalkieRealtimeMigration,
    'supabase/migrations/20260706041351_crew_walkie.sql',
    'supabase/migrations/20260706041413_crew_walkie_realtime.sql',
    'supabase/migrations/20260706042642_crew_walkie_fix_trigger_definer.sql',
    'supabase/migrations/20260706042937_crew_walkie_code_no_pgcrypto.sql',
    'supabase/migrations/20260706043442_crew_walkie_create_rpc.sql',
    'supabase/migrations/20260706065221_crew_walkie_presence.sql',
    crewWalkiePresenceMigration,
    learningLoopMigration,
    'supabase/migrations/20260707144026_learning_loop.sql',
    v2DataShellsMigration,
    telemetrySummaryMigration,
    'supabase/migrations/20260709045102_v2_data_shells.sql',
    'supabase/migrations/20260709051344_telemetry_summary.sql',
    findCurvyRoadsSlimMigration,
    'supabase/migrations/20260712180148_region_requests.sql',
    'supabase/migrations/20260712180201_increment_route_run_count.sql',
    'supabase/migrations/20260712180335_find_curvy_roads_slim.sql',
    exploredCellsMigration,
    releaseHardeningMigration,
    boundedRouteSearchMigration,
    accountDeletionMigration,
    routeMapCoverageMigration,
    mapOnlyBoundaryMigration,
    quebecRegionRepairMigration,
    westernRoutePublicationMigration,
    'supabase/migrations/20260907120251_route_lightweight_overview.sql',
    'supabase/migrations/20260907131716_route_catalog_ordinal_lookup.sql',
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

  test(
    'account deletion cascades user data and retains no raw rate-limit ids',
    () {
      final sql = _readLower(accountDeletionMigration);

      expect(sql, contains('references auth.users(id) on delete cascade'));
      expect(sql, contains('references public.runs(id) on delete cascade'));
      expect(sql, contains('references auth.users(id) on delete set null'));
      expect(sql, contains("updated_at < current_window - interval '1 day'"));
      expect(sql, contains('truncate table public.edge_rate_limits'));
      expect(sql, contains('pg_advisory_xact_lock'));
      expect(sql, contains('normalized_client_key'));
      expect(sql, contains("extensions.digest(client_key_input, 'sha256')"));
      expect(sql, contains("'db-user:' || encode("));
      expect(
        sql,
        contains("extensions.digest(current_user_id::text, 'sha256')"),
      );
      expect(sql, contains('route_feedback_user_run_unique'));
      expect(sql, contains('to service_role'));
    },
  );

  test('slim find_curvy_roads migration keeps explicit function grants', () {
    final sql = _readLower(findCurvyRoadsSlimMigration);

    expect(sql, contains('revoke all on function find_curvy_roads'));
    expect(sql, contains('grant execute on function find_curvy_roads'));
    expect(sql, contains('to anon, authenticated, service_role'));
    expect(
      sql,
      isNot(contains('security definer')),
      reason: 'find_curvy_roads must stay invoker-rights (plain sql).',
    );
  });

  test('release route search requires auth and clamps database work', () {
    final sql = _readLower(boundedRouteSearchMigration);

    expect(sql, contains('rename to find_curvy_roads_unbounded_internal'));
    expect(sql, contains('security definer'));
    expect(sql, contains('authentication required'));
    expect(
      sql,
      contains('least(greatest(coalesce(radius_m, 50000), 1000), 160000)'),
    );
    expect(sql, contains('least(greatest(coalesce(max_results, 30), 1), 120)'));
    expect(sql, contains('from public, anon'));
    expect(
      sql,
      contains('revoke insert on public.crew_channels from authenticated'),
    );
    expect(sql, contains('jsonb_array_length(nodes) between 2 and 1200'));
    expect(sql, contains('pg_column_size(nodes) <= 1048576'));
  });

  test('map coverage RPC is authenticated, bounded, and spatially diverse', () {
    final sql = _readLower(routeMapCoverageMigration);

    expect(sql, contains('function public.find_curvy_map_segments'));
    expect(sql, contains('authentication required'));
    expect(sql, contains('st_dwithin'));
    expect(sql, contains('st_geohash'));
    expect(sql, contains('row_number() over'));
    expect(sql, contains('partition by'));
    expect(
      sql,
      contains('least(greatest(coalesce(radius_m, 50000), 1000), 160000)'),
    );
    expect(
      sql,
      contains('least(greatest(coalesce(min_distance_km, 0.3), 0.3), 4.0)'),
    );
    expect(sql, contains('least(greatest(coalesce(max_results, 30), 1), 60)'));
    expect(sql, contains("set statement_timeout = '8s'"));
    expect(sql, contains('from public, anon'));
    expect(sql, contains('to authenticated, service_role'));
    expect(sql, isNot(contains('security definer')));
  });

  test('map supplement stays below the recommendation distance threshold', () {
    final sql = _readLower(mapOnlyBoundaryMigration);

    expect(
      sql,
      contains('create or replace function public.find_curvy_map_segments'),
    );
    expect(sql, contains('road.distance_km < 4.0'));
    expect(sql, contains('from public, anon'));
    expect(sql, contains('to authenticated, service_role'));
  });

  test('quebec region repair is receipt-bound and fails closed', () {
    final sql = _readLower(quebecRegionRepairMigration);

    expect(
      sql,
      contains(
        'e586c43de9425a47c54f20d0b68fb8a3161aef264e5771b47b152046fd999217',
      ),
      reason: 'repair must bind the pinned preflight target snapshot sha256.',
    );
    expect(
      RegExp(r"'[0-9a-f]{64}'").allMatches(sql).length,
      230,
      reason: 'repair must embed the immutable 230-row id receipt.',
    );
    expect(sql, contains("repaired_region constant text := 'quebec'"));
    expect(sql, contains('receipt row missing from curvy_roads'));
    expect(sql, contains('refusing to overwrite'));
    expect(sql, contains('outside the repair receipt'));
    expect(sql, contains('idempotent no-op'));
    expect(sql, contains('get diagnostics updated_count = row_count'));
    expect(sql, isNot(contains('delete from')));
    expect(sql, isNot(contains('truncate')));
    expect(sql, isNot(contains('drop table')));
  });

  test('western publication maps every legacy province and fails closed', () {
    final sql = _readLower(westernRoutePublicationMigration);

    const legacyProvinceMap = {
      'alberta': 'ab',
      'british_columbia': 'bc',
      'manitoba': 'mb',
      'new_brunswick': 'nb',
      'newfoundland_and_labrador': 'nl',
      'nova_scotia': 'ns',
      'northwest_territories': 'nt',
      'nunavut': 'nu',
      'ontario': 'on',
      'prince_edward_island': 'pe',
      'quebec': 'qc',
      'saskatchewan': 'sk',
      'yukon': 'yt',
    };
    for (final entry in legacyProvinceMap.entries) {
      expect(sql, contains("= '${entry.key}' then '${entry.value}'"));
    }
    expect(sql, contains('legacy province mapping failed'));
    expect(sql, contains('alter column province_code set not null'));
    expect(sql, contains('curvy_roads_province_code_allowed'));
    expect(sql, contains('idx_curvy_roads_province_code'));
  });

  test('western publication isolates generated rows from legacy clients', () {
    final sql = _readLower(westernRoutePublicationMigration);

    expect(sql, contains('drop policy if exists curvy_public_read'));
    expect(sql, contains("publication_kind = 'legacy'"));
    expect(sql, contains('generation_batch_id is null'));
    expect(
      sql,
      contains('create or replace function public.find_curvy_roads('),
    );
    expect(sql, contains('create function public.find_curvy_map_segments('));
    expect(sql, contains('create function public.find_curvy_roads_v2('));
    expect(sql, contains('create function public.get_route_nodes_v2('));
    expect(sql, contains('create function public.get_route_catalog_v2('));
    expect(sql, contains("batch.status = 'active'"));
    expect(sql, contains("auth.jwt() ->> 'role'"));
    expect(sql, contains('from public, anon, authenticated, service_role'));
    expect(sql, contains('from public, anon'));
    expect(sql, contains('to authenticated, service_role'));
    expect(sql, contains('revv_private.find_visible_curvy_roads'));
    expect(sql, contains('include_generated'));
    expect(sql, contains("batch.status = 'active'"));
    expect(sql, contains('road.publication_kind = \'legacy\''));
  });

  test('western publication protects manifests, state, and catalog', () {
    final sql = _readLower(westernRoutePublicationMigration);

    for (final table in [
      'route_generation_batches',
      'route_generation_sources',
      'route_catalog_state',
      'route_batch_transition_receipts',
    ]) {
      expect(sql, contains('create table public.$table'));
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
      expect(sql, contains('revoke all on table public.$table'));
    }
    expect(sql, contains("status in ('shadow', 'active', 'disabled')"));
    expect(sql, contains("cohort_kind in ('pilot', 'expansion')"));
    expect(sql, contains('cardinality(route_ids) <= 650'));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('pg_advisory_xact_lock_shared'));
    expect(sql, contains("'revv-route-batch:'"));
    expect(sql, contains('shadow->active->disabled'));
    expect(sql, contains('disabled batch is immutable'));
    expect(sql, contains('route transition receipts are immutable'));
    expect(sql, contains('route id cohort mismatch'));
    expect(sql, contains("length(road.id)::text || ':' || road.id"));
    expect(sql, contains(r"id ~ '^[a-za-z0-9][a-za-z0-9._:-]{7,191}$'"));
    expect(sql, contains('source_hub_id'));
    expect(sql, contains('primary key (batch_id, hub_id)'));
    expect(sql, isNot(contains('match full')));
    expect(
      sql,
      contains(
        'unique (batch_id, hub_id, province_code, source_pbf_sha256, source_graph_sha256)',
      ),
    );
    expect(sql, contains('catalog contains unclassified eligible routes'));
    expect(
      sql,
      contains('grant execute on function public.admin_transition_route_batch'),
    );
    expect(sql, contains('to service_role'));
    expect(
      sql,
      isNot(
        matches(
          RegExp(
            r'grant\s+execute\s+on\s+function\s+public\.admin_transition_route_batch[^;]*to\s+authenticated',
          ),
        ),
      ),
    );
  });

  test('western publication fixtures cover lifecycle and client isolation', () {
    final sql = _readLower(westernPublicationFixture);

    expect(sql, contains('same-province per-hub graph sources were collapsed'));
    expect(sql, contains('shadow cohort suppressed the visible legacy'));
    expect(sql, contains('same-state active transition'));
    expect(sql, contains('same-state disabled transition'));
    expect(sql, contains('partial cohort unexpectedly activated'));
    expect(
      sql,
      contains('same-count route id hash mismatch unexpectedly activated'),
    );
    expect(sql, contains('wrong manifest checksum unexpectedly succeeded'));
    expect(sql, contains('shadow to disabled unexpectedly succeeded'));
    expect(sql, contains('active pilot missing from v2 recommendation rpc'));
    expect(sql, contains('active pilot missing from v2 node rpc'));
    expect(
      sql,
      contains('active pilot missing from authenticated catalog rpc'),
    );
    expect(
      sql,
      contains('authenticated client activation unexpectedly succeeded'),
    );
    expect(
      sql,
      contains('authenticated direct catalog select unexpectedly succeeded'),
    );
    expect(sql, contains('generated route delete unexpectedly succeeded'));
    expect(sql, contains('source provenance delete unexpectedly succeeded'));
    expect(sql, contains('transition receipt delete unexpectedly succeeded'));
    expect(sql, contains('multi-province provenance unexpectedly succeeded'));
    expect(sql, contains('malformed generated id unexpectedly succeeded'));
    expect(sql, contains('wildcard route id unexpectedly succeeded'));
    expect(sql, contains('control-character route id unexpectedly succeeded'));
    expect(
      sql,
      contains('legacy map segment was suppressed by generated cohorts'),
    );
    expect(sql, contains('explain (costs off)'));
    expect(
      sql,
      contains(
        '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000001"}',
      ),
    );
  });

  test('western catalog fixture locks deterministic three-phase allocation', () {
    final migration = _readLower(westernRoutePublicationMigration);
    final fixture = _readLower(westernCatalogAllocationFixture);

    expect(migration, contains('revv_catalog_candidates'));
    expect(migration, contains('revv_catalog_regions'));
    expect(
      migration,
      contains(
        '(region.capacity - region.selected_count)::numeric / region.capacity desc',
      ),
    );
    expect(migration, contains("distance_km >= 4.0 then 'recommendation'"));
    expect(migration, contains('selection_order'));
    expect(
      migration,
      contains('capacity integer not null check (capacity between 1 and 80)'),
    );
    expect(migration, contains('exhausted boolean not null default false'));
    expect(fixture, contains('synthetic ab400/bc400/mb10/sk10'));
    expect(fixture, contains('single 100-row geohash did not clamp to 3'));
    expect(fixture, contains('recommendation/map 3:2 quota or fallback'));
    expect(fixture, contains('identical rebuild was not byte-deterministic'));
    expect(fixture, contains('route-id-only catalog did not clamp to 650'));
    expect(fixture, contains('route-id-only catalog payload exceeded 2 mib'));
    expect(
      fixture,
      contains('authenticated direct catalog select unexpectedly succeeded'),
    );
  });

  test(
    'western legacy replay fixtures prove exact and fail-closed mapping',
    () {
      final backfillSql = _readLower(westernLegacyBackfillFixture);
      final rejectSql = _readLower(westernLegacyRejectFixture);

      for (final code in [
        'ab',
        'bc',
        'mb',
        'nb',
        'nl',
        'ns',
        'nt',
        'nu',
        'on',
        'pe',
        'qc',
        'sk',
        'yt',
      ]) {
        expect(backfillSql, contains("'legacy-province-$code', '$code'"));
      }
      expect(
        backfillSql,
        contains('legacy 13-code province backfill mismatch'),
      );
      expect(
        backfillSql,
        contains('shared-geohash sparse-province catalog mismatch'),
      );
      expect(
        backfillSql,
        contains('shared-geohash backfill weakened the global cell cap'),
      );
      expect(
        backfillSql,
        contains(
          'shared-geohash sparse-province rebuild was not deterministic',
        ),
      );
      expect(rejectSql, contains("'atlantis'"));
      expect(rejectSql, contains("'legacy-null-region'"));
      expect(rejectSql, contains('null'));
      expect(
        rejectSql,
        contains(
          'unmapped legacy fixture unexpectedly passed publication migration',
        ),
      );
    },
  );

  test('explored cells are owner scoped and anonymous Data API is revoked', () {
    final sql = _readLower(exploredCellsMigration);

    expect(sql, contains('create table if not exists public.explored_cells'));
    expect(
      sql,
      contains('alter table public.explored_cells enable row level security'),
    );
    expect(sql, contains('primary key (user_id, cell_id)'));
    expect(sql, contains('using ((select auth.uid()) = user_id)'));
    expect(sql, contains('with check ((select auth.uid()) = user_id)'));
    expect(
      sql,
      contains('revoke all on table public.explored_cells from anon'),
    );
    expect(
      sql,
      contains(
        'grant select, insert, update, delete on table public.explored_cells to authenticated',
      ),
    );
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

  test('crew walkie tables are minimal and protected by RLS', () {
    final sql = _readLower(crewWalkieMigration);

    for (final table in ['crew_channels', 'crew_channel_members']) {
      expect(
        sql,
        contains('create table if not exists public.$table'),
        reason: '$table must be created by the walkie migration.',
      );
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
        reason: '$table must have RLS enabled.',
      );
    }

    expect(sql, contains('id uuid primary key default gen_random_uuid()'));
    expect(sql, contains('code text not null unique'));
    expect(sql, contains('owner_id uuid not null'));
    expect(
      sql,
      contains(
        "expires_at timestamptz not null default (now() + interval '24 hours')",
      ),
    );
    expect(sql, contains('primary key (channel_id, member_id)'));
    expect(sql, isNot(contains('audio')));
    expect(sql, isNot(contains('location')));
    expect(sql, isNot(contains('speed')));
    expect(sql, isNot(contains('heading')));
  });

  test('crew walkie grants exclude anon and allow authenticated access', () {
    final sql = _readLower(crewWalkieMigration);

    expect(
      sql,
      contains(
        'revoke all on public.crew_channels, public.crew_channel_members',
      ),
    );
    expect(sql, contains('from public, anon'));
    expect(sql, contains('grant select, insert on public.crew_channels'));
    expect(sql, contains('to authenticated'));
    expect(
      sql,
      contains('grant select, delete on public.crew_channel_members'),
    );
    expect(
      sql,
      isNot(
        matches(
          RegExp(
            r'grant\s+[^;]*\bon\s+public\.crew_(?:channels|channel_members)\b[^;]*\bto\s+anon\b',
            multiLine: true,
          ),
        ),
      ),
    );
    expect(
      sql,
      isNot(contains('grant insert on public.crew_channel_members')),
      reason: 'member inserts must only be possible through join_crew_channel.',
    );
  });

  test('crew walkie policies scope reads and writes to membership', () {
    final sql = _readLower(crewWalkieMigration);

    expect(sql, contains('create policy crew_channels_member_select'));
    expect(sql, contains('using (public.is_current_crew_channel_member(id))'));
    expect(sql, contains('create policy crew_channels_owner_insert'));
    expect(sql, contains('owner_id = (select auth.uid())'));
    expect(sql, contains('create policy crew_channel_members_channel_select'));
    expect(
      sql,
      contains('using (public.is_current_crew_channel_member(channel_id))'),
    );
    expect(sql, contains('create policy crew_channel_members_self_delete'));
    expect(sql, contains('using (member_id = (select auth.uid()))'));
    expect(
      sql,
      isNot(contains('create policy crew_channel_members_insert')),
      reason: 'member insert policy would bypass the RPC-only join path.',
    );
  });

  test('crew walkie join RPC is security definer and rate limited', () {
    final sql = _readLower(crewWalkieMigration);

    expect(
      sql,
      contains('create or replace function public.join_crew_channel('),
    );
    expect(sql, contains('security definer'));
    expect(sql, contains('set search_path = public, pg_temp'));
    expect(sql, contains(r"normalized_code !~ '^[a-hj-np-z2-9]{8}$'"));
    expect(sql, contains('expires_at > now()'));
    expect(sql, contains('public.consume_edge_rate_limit('));
    expect(sql, contains("'join_crew_channel'"));
    expect(sql, contains('current_user_id::text'));
    expect(sql, contains('10'));
    expect(sql, contains('60'));
    expect(sql, contains('member_id,'));
    expect(sql, contains('current_user_id,'));
    expect(
      sql,
      contains('revoke all on function public.join_crew_channel(text, text)'),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.join_crew_channel(text, text)',
      ),
    );
    expect(sql, contains('to authenticated, service_role'));
  });

  test('crew walkie channel codes are server generated', () {
    final sql = _readLower(crewWalkieMigration);

    expect(
      sql,
      contains(
        'create or replace function public.generate_crew_channel_code()',
      ),
    );
    expect(
      sql,
      contains("alphabet constant text := 'abcdefghjklmnpqrstuvwxyz23456789'"),
    );
    expect(sql, contains('floor(random() * length(alphabet))'));
    expect(sql, contains('create trigger crew_channels_prepare_insert'));
    expect(sql, contains('new.code := generated_code'));
    expect(sql, contains("new.expires_at := now() + interval '24 hours'"));
    // 트리거는 owner 권한으로 실행돼야 revoke된 generate 함수를 호출할 수 있다.
    // (없으면 authenticated 유저의 방 생성이 permission denied로 실패)
    expect(
      sql,
      contains(
        'create or replace function public.prepare_crew_channel_insert()\n'
        'returns trigger\n'
        'language plpgsql\n'
        'security definer',
      ),
    );
  });

  test('crew walkie realtime policies authorize member broadcasts only', () {
    final sql = _readLower(crewWalkieRealtimeMigration);

    expect(sql, contains('on realtime.messages'));
    expect(sql, contains('create policy crew_walkie_realtime_receive'));
    expect(sql, contains('for select'));
    expect(sql, contains('create policy crew_walkie_realtime_send'));
    expect(sql, contains('for insert'));
    expect(sql, contains('to authenticated'));
    expect(sql, contains("realtime.messages.extension = 'broadcast'"));
    expect(sql, contains('from public.crew_channel_members'));
    expect(sql, contains('member_id = (select auth.uid())'));
    expect(
      sql,
      contains("(select realtime.topic()) = ('crew:' || channel_id::text)"),
    );
    // Non-members intentionally fail closed: no membership row means no policy
    // passes for the private crew:{channelId} topic.
    expect(sql, isNot(contains('to anon')));
    expect(sql, isNot(contains('using (true)')));
    expect(sql, isNot(contains('with check (true)')));
  });

  test('crew walkie presence policies authorize members for both topics', () {
    final sql = _readLower(crewWalkiePresenceMigration);

    // 20260705070001을 대체: presence extension 허용 + 오디오 토픽 분리.
    expect(sql, contains('on realtime.messages'));
    expect(sql, contains('create policy crew_walkie_realtime_receive'));
    expect(sql, contains('for select'));
    expect(sql, contains('create policy crew_walkie_realtime_send'));
    expect(sql, contains('for insert'));
    expect(sql, contains('to authenticated'));
    expect(
      sql,
      contains("realtime.messages.extension in ('broadcast', 'presence')"),
    );
    expect(sql, contains('from public.crew_channel_members'));
    expect(sql, contains('member_id = (select auth.uid())'));
    expect(sql, contains("'crew:' || channel_id::text,"));
    expect(sql, contains("'crew:' || channel_id::text || ':audio'"));
    // Non-members stay fail-closed on both topics.
    expect(sql, isNot(contains('to anon')));
    expect(sql, isNot(contains('using (true)')));
    expect(sql, isNot(contains('with check (true)')));
  });

  test('learning loop logs are owner-only append-only and anon-blocked', () {
    final sql = _readLower(learningLoopMigration);

    expect(
      sql,
      contains('create table if not exists public.recommendation_logs'),
    );
    expect(sql, contains('create table if not exists public.user_preferences'));
    expect(
      sql,
      contains(
        'alter table public.recommendation_logs enable row level security',
      ),
    );
    expect(
      sql,
      contains('alter table public.user_preferences enable row level security'),
    );
    expect(
      sql,
      contains('event text not null check (event in (\'shown\', \'chosen\'))'),
    );
    expect(
      sql,
      contains(
        'mode text not null check (mode in (\'destination\', \'chain\', \'free\'))',
      ),
    );
    expect(sql, contains('route_ids jsonb not null default \'[]\'::jsonb'));
    expect(sql, contains('recommendation_logs_owner_insert'));
    expect(sql, contains('for insert to authenticated'));
    expect(sql, contains('with check (user_id = (select auth.uid()))'));
    expect(sql, contains('recommendation_logs_owner_select'));
    expect(sql, contains('for select to authenticated'));
    expect(sql, contains('using (user_id = (select auth.uid()))'));
    expect(sql, isNot(contains('for update')));
    expect(sql, isNot(contains('for delete')));
    expect(
      sql,
      contains(
        'grant insert, select on public.recommendation_logs to authenticated',
      ),
    );
    expect(sql, contains('revoke all on public.recommendation_logs from anon'));
    expect(
      sql,
      contains('grant all on public.user_preferences to authenticated'),
    );
    expect(sql, contains('revoke all on public.user_preferences from anon'));
    expect(sql, isNot(contains('using (true)')));
  });

  test('v2 data shells stay fail-closed for client writes', () {
    final sql = _readLower(v2DataShellsMigration);

    // photo_spots: 로그인 조회 + 본인 insert만, update/delete 정책 없음
    expect(sql, contains('create table if not exists public.photo_spots'));
    expect(
      sql,
      contains('alter table public.photo_spots enable row level security'),
    );
    expect(sql, contains('created_by = (select auth.uid())'));
    expect(sql, isNot(contains('photo_spots_owner_update')));
    expect(sql, contains('revoke update, delete on public.photo_spots'));
    expect(sql, contains('revoke all on public.photo_spots from anon'));

    // route_scores: 읽기 전용 공개, 쓰기는 service_role뿐
    expect(sql, contains('create table if not exists public.route_scores'));
    expect(
      sql,
      contains('alter table public.route_scores enable row level security'),
    );
    expect(
      sql,
      contains(
        'revoke insert, update, delete on public.route_scores from anon, authenticated',
      ),
    );
  });

  test('release hardening binds popularity updates to owned runs', () {
    final sql = _readLower(releaseHardeningMigration);

    expect(
      sql,
      contains('create table if not exists public.route_run_receipts'),
    );
    expect(sql, contains('run_id text primary key'));
    expect(
      sql,
      contains(
        'create or replace function public.increment_route_run_count(\n'
        '  route_id_input text,\n'
        '  run_id_input text',
      ),
    );
    expect(sql, contains('r.user_id = current_user_id'));
    expect(sql, contains('r.route_id = route_id_input'));
    expect(sql, contains('on conflict (run_id) do nothing'));
    expect(
      sql,
      contains(
        'revoke all on function public.increment_route_run_count(text, text)',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.increment_route_run_count(text, text)',
      ),
    );
  });

  test('release hardening binds run details to the parent owner', () {
    final sql = _readLower(releaseHardeningMigration);

    expect(sql, contains('drop policy if exists run_details_owner'));
    expect(sql, contains('create policy run_details_owner'));
    expect(sql, contains('r.id = run_details.run_id'));
    expect(sql, contains('r.user_id = (select auth.uid())'));
    expect(sql, contains('run_details.user_id = (select auth.uid())'));
  });

  test('release hardening expires crew database and realtime access', () {
    final sql = _readLower(releaseHardeningMigration);

    expect(
      sql,
      contains(
        'create or replace function public.is_current_crew_channel_member',
      ),
    );
    expect(sql, contains('c.expires_at > now()'));
    expect(sql, contains('create policy crew_walkie_realtime_receive'));
    expect(sql, contains('create policy crew_walkie_realtime_send'));
    expect(sql, contains('join public.crew_channels c'));
  });

  test('release hardening forces photo proposals into untrusted defaults', () {
    final sql = _readLower(releaseHardeningMigration);

    expect(sql, contains('drop policy if exists photo_spots_owner_insert'));
    expect(sql, contains("source = 'user'"));
    expect(sql, contains("status = 'candidate'"));
    expect(sql, contains('vote_count = 0'));
    expect(sql, contains('lat between -90 and 90'));
    expect(sql, contains('lng between -180 and 180'));
  });

  test('release hardening bounds database write amplification', () {
    final sql = _readLower(releaseHardeningMigration);

    expect(sql, contains('enforce_authenticated_write_rate'));
    expect(sql, contains("'region-request', '20', '86400'"));
    expect(sql, contains("'photo-spot', '20', '86400'"));
    expect(sql, contains("'recommendation-log', '500', '86400'"));
    expect(sql, contains("'explored-cell', '5000', '86400'"));
    expect(sql, contains("'telemetry-summary', '200', '86400'"));
    expect(sql, contains("'crew-create'"));
    expect(sql, contains("set statement_timeout = '8s'"));
    expect(sql, contains('revoke all on public.region_requests from anon'));
  });

  test(
    'telemetry summary is owner-only append-only and stores summaries only',
    () {
      final sql = _readLower(telemetrySummaryMigration);

      expect(
        sql,
        contains('create table if not exists public.telemetry_summary'),
      );
      expect(sql, contains('run_id text primary key'));
      expect(
        sql,
        contains(
          'alter table public.telemetry_summary enable row level security',
        ),
      );
      expect(sql, contains('telemetry_summary_owner_insert'));
      expect(sql, contains('for insert to authenticated'));
      expect(sql, contains('with check (user_id = (select auth.uid()))'));
      expect(sql, contains('telemetry_summary_owner_select'));
      expect(sql, contains('for select to authenticated'));
      expect(sql, contains('using (user_id = (select auth.uid()))'));
      expect(
        sql,
        contains(
          'grant insert, select on public.telemetry_summary to authenticated',
        ),
      );
      expect(
        sql,
        contains(
          'revoke update, delete on public.telemetry_summary from authenticated',
        ),
      );
      expect(sql, contains('revoke all on public.telemetry_summary from anon'));
      expect(sql, contains('hard_brake_count integer'));
      expect(sql, contains('harsh_steer_count integer'));
      expect(sql, contains('smooth_ratio double precision'));
      expect(sql, contains('p95_lateral_g double precision'));
      expect(sql, contains('sample_seconds integer'));
      expect(sql, isNot(contains('telemetry_json')));
      expect(sql, isNot(contains('gps')));
      expect(sql, isNot(contains('lat ')));
      expect(sql, isNot(contains('lng ')));
    },
  );
}

String _readLower(String path) => File(path).readAsStringSync().toLowerCase();

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
    crewWalkiePresenceMigration,
    learningLoopMigration,
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
}

String _readLower(String path) => File(path).readAsStringSync().toLowerCase();

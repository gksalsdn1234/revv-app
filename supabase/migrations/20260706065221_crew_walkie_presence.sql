-- 워키토키 presence 인가 + 오디오 토픽 분리 반영.
-- 기존 정책(20260705070001)은 extension='broadcast'만 허용해 presence(track/sync)가
-- :unauthorized로 거부됐다(온라인 0명 버그). 멤버에 한해 broadcast/presence 두
-- extension과 두 토픽(crew:<id> = presence, crew:<id>:audio = PTT broadcast)을
-- 허용한다. 비멤버는 그대로 fail-closed.

drop policy if exists crew_walkie_realtime_receive on realtime.messages;
create policy crew_walkie_realtime_receive on realtime.messages
  for select
  to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and exists (
      select 1
        from public.crew_channel_members
       where member_id = (select auth.uid())
         and (select realtime.topic()) in (
           'crew:' || channel_id::text,
           'crew:' || channel_id::text || ':audio'
         )
    )
  );

drop policy if exists crew_walkie_realtime_send on realtime.messages;
create policy crew_walkie_realtime_send on realtime.messages
  for insert
  to authenticated
  with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and exists (
      select 1
        from public.crew_channel_members
       where member_id = (select auth.uid())
         and (select realtime.topic()) in (
           'crew:' || channel_id::text,
           'crew:' || channel_id::text || ':audio'
         )
    )
  );;

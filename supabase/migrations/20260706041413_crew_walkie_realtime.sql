drop policy if exists crew_walkie_realtime_receive on realtime.messages;
create policy crew_walkie_realtime_receive on realtime.messages
  for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and exists (
      select 1
        from public.crew_channel_members
       where member_id = (select auth.uid())
         and (select realtime.topic()) = ('crew:' || channel_id::text)
    )
  );

drop policy if exists crew_walkie_realtime_send on realtime.messages;
create policy crew_walkie_realtime_send on realtime.messages
  for insert
  to authenticated
  with check (
    realtime.messages.extension = 'broadcast'
    and exists (
      select 1
        from public.crew_channel_members
       where member_id = (select auth.uid())
         and (select realtime.topic()) = ('crew:' || channel_id::text)
    )
  );;

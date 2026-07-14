-- join처럼 방 생성도 security definer RPC로. owner_id를 서버에서 auth.uid()로 채워
-- 클라이언트 uid 의존과 RLS insert WITH CHECK 취약점을 제거한다.
create or replace function public.create_crew_channel(
  name_input text default ''
)
returns public.crew_channels
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_user_id uuid := (select auth.uid());
  created_channel public.crew_channels%rowtype;
begin
  if current_user_id is null then
    raise exception 'authentication required'
      using errcode = '28000';
  end if;

  insert into public.crew_channels (name, owner_id)
  values (left(btrim(coalesce(name_input, '')), 60), current_user_id)
  returning * into created_channel;

  -- 생성자를 첫 멤버로 등록 (이름 없으면 크루원 1)
  insert into public.crew_channel_members (channel_id, member_id, display_name)
  values (created_channel.id, current_user_id, '크루원 1')
  on conflict (channel_id, member_id) do nothing;

  return created_channel;
end;
$$;

revoke all on function public.create_crew_channel(text) from public, anon;
grant execute on function public.create_crew_channel(text) to authenticated, service_role;;

-- gen_random_bytes(pgcrypto)는 함수 search_path(public,pg_temp)에서 안 잡힌다.
-- 코어 random()으로 교체 — 짧은 수명 참여코드라 충분하고 join은 레이트리밋됨.
create or replace function public.generate_crew_channel_code()
returns text
language plpgsql
set search_path = public, pg_temp
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  generated_code text := '';
  char_index integer;
begin
  for char_index in 1..8 loop
    generated_code := generated_code ||
      substr(alphabet, floor(random() * length(alphabet))::int + 1, 1);
  end loop;

  return generated_code;
end;
$$;;

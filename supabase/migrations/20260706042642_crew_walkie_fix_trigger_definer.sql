-- 트리거 함수가 호출자(authenticated) 권한으로 generate_crew_channel_code를
-- 호출하다 permission denied. security definer로 바꿔 owner 권한으로 실행한다.
alter function public.prepare_crew_channel_insert() security definer;;

\set ON_ERROR_STOP on

begin;

insert into public.curvy_roads (
  id, name, center_lat, center_lng, center_point, nodes,
  distance_km, winding_score, region
) values
  (
    'legacy-unknown-region', 'Unknown region', 50.0, -110.0,
    st_setsrid(st_makepoint(-110.0, 50.0), 4326)::geography,
    '[{"lat":50.0,"lng":-110.0},{"lat":50.01,"lng":-110.01}]'::jsonb,
    6.0, 40.0, 'Atlantis'
  ),
  (
    'legacy-null-region', 'Null region', 50.1, -110.1,
    st_setsrid(st_makepoint(-110.1, 50.1), 4326)::geography,
    '[{"lat":50.1,"lng":-110.1},{"lat":50.11,"lng":-110.11}]'::jsonb,
    6.0, 40.0, null
  );

\ir ../migrations/20260716043420_western_route_publication_v2.sql

do $$
begin
  raise exception 'unmapped legacy fixture unexpectedly passed publication migration';
end;
$$;

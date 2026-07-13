create table if not exists public.explored_cells (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  cell_id text not null check (
    char_length(cell_id) = 7
    and cell_id ~ '^[0123456789bcdefghjkmnpqrstuvwxyz]{7}$'
  ),
  explored_at timestamptz not null default now(),
  primary key (user_id, cell_id)
);

alter table public.explored_cells enable row level security;

drop policy if exists explored_cells_owner_select on public.explored_cells;
create policy explored_cells_owner_select on public.explored_cells
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists explored_cells_owner_insert on public.explored_cells;
create policy explored_cells_owner_insert on public.explored_cells
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists explored_cells_owner_update on public.explored_cells;
create policy explored_cells_owner_update on public.explored_cells
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists explored_cells_owner_delete on public.explored_cells;
create policy explored_cells_owner_delete on public.explored_cells
  for delete to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.explored_cells from anon;
grant select, insert, update, delete on table public.explored_cells to authenticated;
grant all on table public.explored_cells to service_role;

-- Run this once in Supabase > SQL Editor if you already ran the old schema.sql.
-- 1) Fixes "function gen_random_bytes(integer) does not exist" when creating a private room.
create or replace function public.create_room(p_minutes int, p_inc int) returns public.games
language plpgsql security definer set search_path = public as $$
declare g public.games; c text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  c := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 5));
  insert into public.games (white_id, is_private, code, minutes, inc_ms, white_ms, black_ms)
    values (auth.uid(), true, c, p_minutes, p_inc * 1000, p_minutes * 60000, p_minutes * 60000) returning * into g;
  return g;
end $$;

-- 2) Cloud save for puzzles / stats / settings / game history.
create table if not exists public.user_progress (
  user_id uuid primary key references auth.users(id) on delete cascade,
  stats jsonb not null default '{}'::jsonb,
  settings jsonb not null default '{}'::jsonb,
  history jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.user_progress enable row level security;
drop policy if exists "own progress read" on public.user_progress;
create policy "own progress read" on public.user_progress for select to authenticated using (user_id = auth.uid());
drop policy if exists "own progress insert" on public.user_progress;
create policy "own progress insert" on public.user_progress for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "own progress update" on public.user_progress;
create policy "own progress update" on public.user_progress for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

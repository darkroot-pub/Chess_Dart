-- DarkChess online schema. Run once in Supabase Dashboard > SQL Editor.
create extension if not exists pgcrypto;

-- ============================ tables ============================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  rating int not null default 1200,
  games_played int not null default 0,
  wins int not null default 0,
  losses int not null default 0,
  draws int not null default 0,
  last_seen timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  code text unique,                       -- private room code
  is_private boolean not null default false,
  status text not null default 'waiting' check (status in ('waiting','active','finished')),
  white_id uuid references public.profiles(id),
  black_id uuid references public.profiles(id),
  fen text not null default 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  turn text not null default 'w',
  moves text[] not null default '{}',     -- UCI moves
  minutes int not null default 5,
  inc_ms int not null default 0,
  white_ms int not null default 300000,
  black_ms int not null default 300000,
  last_move_at timestamptz not null default now(),
  draw_offer_by uuid,
  result text,                            -- '1-0' | '0-1' | '1/2-1/2'
  reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.game_moves (
  id bigserial primary key,
  game_id uuid not null references public.games(id) on delete cascade,
  ply int not null,
  uci text not null,
  san text,
  fen_after text not null,
  player_id uuid not null,
  created_at timestamptz not null default now()
);

create table if not exists public.friendships (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id)
);

create or replace view public.leaderboard as
  select id, username, rating, games_played, wins from public.profiles
  order by rating desc;

-- ============================ new-user trigger ============================
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare base text; final_name text;
begin
  base := coalesce(nullif(trim(new.raw_user_meta_data->>'username'), ''), 'Guest' || substr(new.id::text, 1, 5));
  final_name := left(base, 20);
  if exists (select 1 from public.profiles where username = final_name) then
    final_name := left(final_name, 14) || substr(new.id::text, 1, 5);
  end if;
  insert into public.profiles (id, username) values (new.id, final_name);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================ RLS ============================
alter table public.profiles enable row level security;
alter table public.games enable row level security;
alter table public.game_moves enable row level security;
alter table public.friendships enable row level security;

drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select to authenticated using (true);
drop policy if exists "own username" on public.profiles;
create policy "own username" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
-- only the username column may be changed by clients; rating/stats are written by the server
revoke update on public.profiles from authenticated, anon;
grant update (username) on public.profiles to authenticated;

drop policy if exists "players read their games" on public.games;
create policy "players read their games" on public.games for select to authenticated
  using (auth.uid() = white_id or auth.uid() = black_id);
-- no insert/update/delete policies on games: clients can only use the RPCs and the edge function

drop policy if exists "players read moves" on public.game_moves;
create policy "players read moves" on public.game_moves for select to authenticated
  using (exists (select 1 from public.games g where g.id = game_id and (g.white_id = auth.uid() or g.black_id = auth.uid())));

drop policy if exists "own friendships" on public.friendships;
create policy "own friendships" on public.friendships for select to authenticated using (user_id = auth.uid());
drop policy if exists "add friends" on public.friendships;
create policy "add friends" on public.friendships for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "remove friends" on public.friendships;
create policy "remove friends" on public.friendships for delete to authenticated using (user_id = auth.uid());

grant select on public.leaderboard to authenticated;

-- ============================ RPCs (security definer) ============================
create or replace function public.touch_presence() returns void
language sql security definer set search_path = public as $$
  update public.profiles set last_seen = now() where id = auth.uid();
$$;

create or replace function public.quick_match(p_minutes int, p_inc int) returns public.games
language plpgsql security definer set search_path = public as $$
declare g public.games;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  -- drop my own stale waiting games
  delete from public.games where status = 'waiting' and white_id = auth.uid() and created_at < now() - interval '2 minutes';
  select * into g from public.games
   where status = 'waiting' and not is_private and white_id <> auth.uid()
     and minutes = p_minutes and inc_ms = p_inc * 1000
   order by created_at limit 1 for update skip locked;
  if found then
    update public.games set black_id = auth.uid(), status = 'active', last_move_at = now()
      where id = g.id returning * into g;
    return g;
  end if;
  insert into public.games (white_id, minutes, inc_ms, white_ms, black_ms)
    values (auth.uid(), p_minutes, p_inc * 1000, p_minutes * 60000, p_minutes * 60000) returning * into g;
  return g;
end $$;

create or replace function public.create_room(p_minutes int, p_inc int) returns public.games
language plpgsql security definer set search_path = public as $$
declare g public.games; c text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  -- gen_random_uuid() is built in (pgcrypto's gen_random_bytes lives in another schema and is not found here)
  c := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 5));
  insert into public.games (white_id, is_private, code, minutes, inc_ms, white_ms, black_ms)
    values (auth.uid(), true, c, p_minutes, p_inc * 1000, p_minutes * 60000, p_minutes * 60000) returning * into g;
  return g;
end $$;

create or replace function public.join_room(p_code text) returns public.games
language plpgsql security definer set search_path = public as $$
declare g public.games;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select * into g from public.games where code = upper(trim(p_code)) and status = 'waiting' for update;
  if not found then raise exception 'Room not found or already started'; end if;
  if g.white_id = auth.uid() then raise exception 'You created this room'; end if;
  update public.games set black_id = auth.uid(), status = 'active', last_move_at = now()
    where id = g.id returning * into g;
  return g;
end $$;

create or replace function public.cancel_game(p_game uuid) returns void
language sql security definer set search_path = public as $$
  delete from public.games where id = p_game and status = 'waiting' and white_id = auth.uid();
$$;

revoke all on function public.touch_presence, public.quick_match, public.create_room, public.join_room, public.cancel_game from public, anon;
grant execute on function public.touch_presence, public.quick_match, public.create_room, public.join_room, public.cancel_game to authenticated;

-- ============================ cloud progress (puzzles, stats, settings, history) ============================
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

-- ============================ Realtime ============================
alter table public.games replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.games;
exception when duplicate_object then null; end $$;
-- Run once in Supabase > SQL Editor (safe to run again).
-- Adds: profile photos + Google name auto-fill, friend challenges / invitations.

-- ---------- profile photo ----------
alter table public.profiles add column if not exists avatar_url text;
grant update (username, avatar_url) on public.profiles to authenticated;

-- new users: take username + photo from Google (or email sign-up) metadata
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare base text; final_name text; pic text;
begin
  base := coalesce(
    nullif(trim(new.raw_user_meta_data->>'username'), ''),
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    'Guest' || substr(new.id::text, 1, 5));
  final_name := left(base, 20);
  if exists (select 1 from public.profiles where username = final_name) then
    final_name := left(final_name, 14) || substr(new.id::text, 1, 5);
  end if;
  pic := coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture');
  insert into public.profiles (id, username, avatar_url) values (new.id, final_name, pic);
  return new;
end $$;

-- ---------- challenges ----------
create table if not exists public.challenges (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  minutes int not null default 5,
  inc int not null default 0,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  game_id uuid references public.games(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.challenges enable row level security;
drop policy if exists "see my challenges" on public.challenges;
create policy "see my challenges" on public.challenges for select to authenticated
  using (from_id = auth.uid() or to_id = auth.uid());
-- no insert/update/delete policies: only the functions below may change challenges

create or replace function public.send_challenge(p_to uuid, p_minutes int, p_inc int) returns public.challenges
language plpgsql security definer set search_path = public as $$
declare c public.challenges;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_to = auth.uid() then raise exception 'You cannot challenge yourself'; end if;
  if not exists (select 1 from public.profiles where id = p_to) then raise exception 'Player not found'; end if;
  update public.challenges set status = 'cancelled'
    where from_id = auth.uid() and to_id = p_to and status = 'pending';
  insert into public.challenges (from_id, to_id, minutes, inc) values (auth.uid(), p_to, p_minutes, p_inc)
    returning * into c;
  return c;
end $$;

create or replace function public.respond_challenge(p_id uuid, p_accept boolean) returns public.challenges
language plpgsql security definer set search_path = public as $$
declare c public.challenges; g public.games; w uuid; b uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select * into c from public.challenges
    where id = p_id and to_id = auth.uid() and status = 'pending' for update;
  if not found then raise exception 'Challenge expired or already answered'; end if;
  if not p_accept then
    update public.challenges set status = 'declined' where id = c.id returning * into c;
    return c;
  end if;
  if random() < 0.5 then w := c.from_id; b := c.to_id; else w := c.to_id; b := c.from_id; end if;
  insert into public.games (white_id, black_id, status, minutes, inc_ms, white_ms, black_ms, last_move_at)
    values (w, b, 'active', c.minutes, c.inc * 1000, c.minutes * 60000, c.minutes * 60000, now())
    returning * into g;
  update public.challenges set status = 'accepted', game_id = g.id where id = c.id returning * into c;
  -- both players become friends
  insert into public.friendships (user_id, friend_id) values (c.from_id, c.to_id), (c.to_id, c.from_id)
    on conflict do nothing;
  return c;
end $$;

create or replace function public.cancel_challenge(p_id uuid) returns void
language sql security definer set search_path = public as $$
  update public.challenges set status = 'cancelled' where id = p_id and from_id = auth.uid() and status = 'pending';
$$;

revoke all on function public.send_challenge, public.respond_challenge, public.cancel_challenge from public, anon;
grant execute on function public.send_challenge, public.respond_challenge, public.cancel_challenge to authenticated;

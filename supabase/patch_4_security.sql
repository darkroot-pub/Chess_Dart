-- =====================================================================================
-- DarkChess patch 4: security hardening + atomic game engine + safe cloud sync.
-- Run in Supabase > SQL Editor AFTER schema.sql, patch_2 and patch_3. Safe to re-run.
-- Non-destructive: nothing is dropped or truncated; new constraints are added NOT VALID
-- first (so old rows can never block the migration) and validated when the data allows it.
-- =====================================================================================

-- ------------------------------------------------------------------ 1. integrity
do $$ begin
  alter table public.games add constraint games_minutes_chk  check (minutes between 1 and 180) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.games add constraint games_inc_chk      check (inc_ms between 0 and 60000) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.games add constraint games_clock_chk    check (white_ms >= 0 and black_ms >= 0) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.games add constraint games_turn_chk     check (turn in ('w','b')) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.games add constraint games_result_chk   check (result is null or result in ('1-0','0-1','1/2-1/2')) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.games add constraint games_players_chk  check (white_id is null or black_id is null or white_id <> black_id) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.games add constraint games_code_chk     check (code is null or code ~ '^[A-Z0-9]{5,12}$') not valid;
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.game_moves add constraint game_moves_ply_chk check (ply > 0) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.game_moves add constraint game_moves_player_fk foreign key (player_id) references public.profiles(id) on delete cascade not valid;
exception when duplicate_object then null; end $$;
-- duplicate or replayed moves can never be stored twice
create unique index if not exists game_moves_game_ply_uidx on public.game_moves (game_id, ply);

do $$ begin
  alter table public.friendships add constraint friendships_self_chk check (user_id <> friend_id) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.challenges add constraint challenges_tc_chk   check (minutes between 1 and 180 and inc between 0 and 60) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.challenges add constraint challenges_self_chk check (from_id <> to_id) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.profiles add constraint profiles_username_chk check (char_length(username) between 1 and 24) not valid;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.profiles add constraint profiles_stats_chk    check (rating between 0 and 4000 and games_played >= 0 and wins >= 0 and losses >= 0 and draws >= 0) not valid;
exception when duplicate_object then null; end $$;
-- avatar must be an https URL of sane length (blocks javascript:/http:/data: and megabyte payloads)
do $$ begin
  alter table public.profiles add constraint profiles_avatar_chk   check (avatar_url is null or (avatar_url ~* '^https://' and char_length(avatar_url) <= 500)) not valid;
exception when duplicate_object then null; end $$;

-- try to validate everything; if old rows violate a rule the constraint just stays NOT VALID (still enforced for new rows)
do $$
declare r record;
begin
  for r in select conrelid::regclass as t, conname from pg_constraint
           where not convalidated and connamespace = 'public'::regnamespace loop
    begin
      execute format('alter table %s validate constraint %I', r.t, r.conname);
    exception when others then
      raise notice 'constraint % on % left NOT VALID: %', r.conname, r.t, sqlerrm;
    end;
  end loop;
end $$;

create index if not exists games_white_idx     on public.games (white_id);
create index if not exists games_black_idx     on public.games (black_id);
create index if not exists games_waiting_idx   on public.games (minutes, inc_ms, created_at) where status = 'waiting' and not is_private;
create index if not exists games_status_idx    on public.games (status, created_at);
create index if not exists challenges_to_idx   on public.challenges (to_id, status, created_at desc);
create index if not exists challenges_from_idx on public.challenges (from_id, status, created_at desc);
create index if not exists friendships_friend_idx on public.friendships (friend_id);
create index if not exists profiles_last_seen_idx on public.profiles (last_seen);

-- ------------------------------------------------------------------ 2. table privileges (defence in depth on top of RLS)
revoke all on public.games, public.game_moves, public.challenges, public.profiles, public.friendships, public.user_progress from anon;
revoke insert, update, delete, truncate on public.games, public.game_moves, public.challenges from authenticated;
revoke all on public.leaderboard from anon;
do $$ begin
  alter view public.leaderboard set (security_invoker = true);
exception when others then null; end $$;

drop policy if exists "add friends" on public.friendships;
create policy "add friends" on public.friendships for insert to authenticated
  with check (user_id = auth.uid() and friend_id <> auth.uid());

-- ------------------------------------------------------------------ 3. rate limiting
create table if not exists public.rate_events (
  id bigserial primary key,
  user_id uuid not null,
  kind text not null,
  at timestamptz not null default now()
);
create index if not exists rate_events_idx on public.rate_events (user_id, kind, at desc);
alter table public.rate_events enable row level security;       -- no policies: unreachable for clients
revoke all on public.rate_events from anon, authenticated;

-- Raises when the user already did p_max of p_kind inside p_window. Otherwise records one event.
create or replace function public._rate_hit(p_user uuid, p_kind text, p_max int, p_window interval) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  select count(*) into n from public.rate_events where user_id = p_user and kind = p_kind and at > now() - p_window;
  if n >= p_max then raise exception 'Too many requests. Please wait a moment and try again.'; end if;
  insert into public.rate_events (user_id, kind) values (p_user, p_kind);
  if random() < 0.02 then delete from public.rate_events where at < now() - interval '1 day'; end if;
end $$;

-- Counts a failure only (used for brute-force protection); never raises.
create or replace function public._rate_count(p_user uuid, p_kind text, p_window interval) returns int
language sql security definer set search_path = public, pg_temp as $$
  select count(*)::int from public.rate_events where user_id = p_user and kind = p_kind and at > now() - p_window;
$$;

create or replace function public._rate_note(p_user uuid, p_kind text) returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into public.rate_events (user_id, kind) values (p_user, p_kind);
$$;

-- ------------------------------------------------------------------ 4. validation helpers
create or replace function public._check_tc(p_minutes int, p_inc int) returns void
language plpgsql immutable set search_path = public, pg_temp as $$
begin
  if p_minutes is null or p_minutes < 1 or p_minutes > 180 then raise exception 'Invalid time control (minutes must be 1-180)'; end if;
  if p_inc is null or p_inc < 0 or p_inc > 60 then raise exception 'Invalid time control (increment must be 0-60 seconds)'; end if;
end $$;

-- 8 characters from a 32-symbol alphabet (no 0/O/1/I): 40 bits from the database CSPRNG, uniform (256 = 8 x 32).
create or replace function public._room_code() returns text
language plpgsql volatile set search_path = public, pg_temp as $$
declare alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea; c text; i int;
begin
  loop
    b := uuid_send(gen_random_uuid());
    c := '';
    for i in 0..7 loop
      c := c || substr(alphabet, (get_byte(b, i) & 31) + 1, 1);
    end loop;
    exit when not exists (select 1 from public.games where code = c);
  end loop;
  return c;
end $$;

-- Removes dead lobbies and never-played games. Cheap, called from the lobby RPCs (no pg_cron needed).
create or replace function public._expire_stale() returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.games where status = 'waiting' and not is_private and created_at < now() - interval '10 minutes';
  delete from public.games where status = 'waiting' and is_private and created_at < now() - interval '30 minutes';
  update public.games set status = 'finished', reason = 'Abandoned', draw_offer_by = null
   where status = 'active' and cardinality(moves) = 0 and last_move_at < now() - interval '30 minutes';
  update public.challenges set status = 'cancelled' where status = 'pending' and created_at < now() - interval '10 minutes';
end $$;

-- ------------------------------------------------------------------ 5. lobby RPCs (validated, rate limited, race free)
create or replace function public.quick_match(p_minutes int, p_inc int) returns public.games
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; me uuid := auth.uid();
begin
  if me is null then raise exception 'Not signed in'; end if;
  perform public._check_tc(p_minutes, p_inc);
  perform public._rate_hit(me, 'quick_match', 30, interval '1 minute');
  perform public._expire_stale();
  -- one queue per time control; the advisory lock stops two simultaneous searchers from both creating a game and never meeting
  perform pg_advisory_xact_lock(hashtext('qm:' || p_minutes || ':' || p_inc));
  -- re-polling returns my own waiting game instead of creating duplicates
  select * into g from public.games where status = 'waiting' and not is_private and white_id = me
     and minutes = p_minutes and inc_ms = p_inc * 1000 order by created_at limit 1;
  if found then return g; end if;
  delete from public.games where status = 'waiting' and not is_private and white_id = me;
  select * into g from public.games
   where status = 'waiting' and not is_private and white_id <> me
     and minutes = p_minutes and inc_ms = p_inc * 1000
   order by created_at limit 1 for update skip locked;
  if found then
    update public.games set black_id = me, status = 'active', last_move_at = clock_timestamp()
      where id = g.id returning * into g;
    return g;
  end if;
  insert into public.games (white_id, minutes, inc_ms, white_ms, black_ms)
    values (me, p_minutes, p_inc * 1000, p_minutes * 60000, p_minutes * 60000) returning * into g;
  return g;
end $$;

create or replace function public.create_room(p_minutes int, p_inc int) returns public.games
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; me uuid := auth.uid();
begin
  if me is null then raise exception 'Not signed in'; end if;
  perform public._check_tc(p_minutes, p_inc);
  perform public._rate_hit(me, 'create_room', 10, interval '1 minute');
  perform public._expire_stale();
  -- at most 3 open private rooms per player; older ones are dropped
  delete from public.games where id in (
    select id from public.games where status = 'waiting' and is_private and white_id = me order by created_at desc offset 2);
  insert into public.games (white_id, is_private, code, minutes, inc_ms, white_ms, black_ms)
    values (me, true, public._room_code(), p_minutes, p_inc * 1000, p_minutes * 60000, p_minutes * 60000) returning * into g;
  return g;
end $$;

-- Returns NULL (not an error) for an unknown/expired/invalid code so that the failed attempt is still recorded
-- (an exception would roll the counter back and make brute-forcing free). The app turns NULL into "Room not found".
create or replace function public.join_room(p_code text) returns public.games
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; me uuid := auth.uid(); c text := upper(trim(coalesce(p_code, '')));
begin
  if me is null then raise exception 'Not signed in'; end if;
  if public._rate_count(me, 'join_fail', interval '10 minutes') >= 10 then
    raise exception 'Too many wrong room codes. Try again in a few minutes.';
  end if;
  if c !~ '^[A-Z0-9]{5,12}$' then perform public._rate_note(me, 'join_fail'); return null; end if;
  select * into g from public.games
   where code = c and status = 'waiting' and is_private and created_at > now() - interval '30 minutes' for update;
  if not found then perform public._rate_note(me, 'join_fail'); return null; end if;
  if g.white_id = me then raise exception 'You created this room'; end if;
  update public.games set black_id = me, status = 'active', last_move_at = clock_timestamp()
    where id = g.id returning * into g;
  return g;
end $$;

create or replace function public.cancel_game(p_game uuid) returns void
language sql security definer set search_path = public, pg_temp as $$
  delete from public.games where id = p_game and status = 'waiting' and white_id = auth.uid();
$$;

create or replace function public.touch_presence() returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.profiles set last_seen = now() where id = auth.uid() and last_seen < now() - interval '15 seconds';
$$;

-- ------------------------------------------------------------------ 6. challenges
create or replace function public.send_challenge(p_to uuid, p_minutes int, p_inc int) returns public.challenges
language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.challenges; me uuid := auth.uid();
begin
  if me is null then raise exception 'Not signed in'; end if;
  if p_to is null then raise exception 'Player not found'; end if;
  if p_to = me then raise exception 'You cannot challenge yourself'; end if;
  perform public._check_tc(p_minutes, p_inc);
  perform public._rate_hit(me, 'challenge', 10, interval '1 minute');
  perform public._expire_stale();
  if not exists (select 1 from public.profiles where id = p_to) then raise exception 'Player not found'; end if;
  if exists (select 1 from public.challenges where from_id = me and to_id = p_to and status = 'pending') then
    raise exception 'You already have a pending challenge to this player';
  end if;
  if (select count(*) from public.challenges where from_id = me and status = 'pending') >= 20 then
    raise exception 'Too many pending challenges';
  end if;
  insert into public.challenges (from_id, to_id, minutes, inc) values (me, p_to, p_minutes, p_inc) returning * into c;
  return c;
end $$;

create or replace function public.respond_challenge(p_id uuid, p_accept boolean) returns public.challenges
language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.challenges; g public.games; w uuid; b uuid; me uuid := auth.uid();
begin
  if me is null then raise exception 'Not signed in'; end if;
  select * into c from public.challenges
    where id = p_id and to_id = me and status = 'pending' and created_at > now() - interval '10 minutes' for update;
  if not found then raise exception 'Challenge expired or already answered'; end if;
  if not coalesce(p_accept, false) then
    update public.challenges set status = 'declined' where id = c.id returning * into c;
    return c;
  end if;
  if get_byte(uuid_send(gen_random_uuid()), 0) < 128 then w := c.from_id; b := c.to_id; else w := c.to_id; b := c.from_id; end if;
  insert into public.games (white_id, black_id, status, minutes, inc_ms, white_ms, black_ms, last_move_at)
    values (w, b, 'active', c.minutes, c.inc * 1000, c.minutes * 60000, c.minutes * 60000, clock_timestamp())
    returning * into g;
  update public.challenges set status = 'accepted', game_id = g.id where id = c.id returning * into c;
  insert into public.friendships (user_id, friend_id) values (c.from_id, c.to_id), (c.to_id, c.from_id) on conflict do nothing;
  return c;
end $$;

create or replace function public.cancel_challenge(p_id uuid) returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.challenges set status = 'cancelled' where id = p_id and from_id = auth.uid() and status = 'pending';
$$;

-- ------------------------------------------------------------------ 7. authoritative game engine
-- Finishes a game that the caller ALREADY HAS LOCKED (select ... for update). Idempotent: a finished game is
-- returned unchanged, so ratings can never be applied twice. Ratings only change for games with >= 2 plies.
create or replace function public._finish_locked(p_id uuid, p_result text, p_reason text) returns public.games
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; w public.profiles; b public.profiles; sw numeric; ew numeric; k constant int := 24;
begin
  update public.games set status = 'finished', result = p_result, reason = p_reason, draw_offer_by = null,
         white_ms = greatest(0, white_ms), black_ms = greatest(0, black_ms)
   where id = p_id and status = 'active' returning * into g;
  if not found then
    select * into g from public.games where id = p_id;
    return g;
  end if;
  if p_result in ('1-0','0-1','1/2-1/2') and g.white_id is not null and g.black_id is not null and cardinality(g.moves) >= 2 then
    -- lock both profiles in a fixed order (no deadlocks between concurrent games)
    perform 1 from public.profiles where id in (g.white_id, g.black_id) order by id for update;
    select * into w from public.profiles where id = g.white_id;
    select * into b from public.profiles where id = g.black_id;
    sw := case p_result when '1-0' then 1 when '0-1' then 0 else 0.5 end;
    ew := 1 / (1 + power(10::numeric, (b.rating - w.rating)::numeric / 400));
    update public.profiles set rating = greatest(100, round(w.rating + k * (sw - ew))::int), games_played = games_played + 1,
           wins = wins + (sw = 1)::int, losses = losses + (sw = 0)::int, draws = draws + (sw = 0.5)::int where id = w.id;
    update public.profiles set rating = greatest(100, round(b.rating + k * ((1 - sw) - (1 - ew)))::int), games_played = games_played + 1,
           wins = wins + (sw = 0)::int, losses = losses + (sw = 1)::int, draws = draws + (sw = 0.5)::int where id = b.id;
  end if;
  return g;
end $$;

-- Milliseconds the side to move has used since the last move, by the DATABASE clock (0 before white's first move).
create or replace function public._elapsed_ms(g public.games) returns int
language sql stable set search_path = public, pg_temp as $$
  select case when cardinality(g.moves) = 0 then 0
         else least(2000000000, greatest(0, floor(extract(epoch from (clock_timestamp() - g.last_move_at)) * 1000)))::int end;
$$;

-- One atomic move. Called ONLY by the edge function (service role) after chess.js validated the move against the
-- position it replayed from the stored move list. Everything the server trusts is re-checked here under a row lock.
create or replace function public.server_apply_move(
  p_game uuid, p_player uuid, p_uci text, p_expected_ply int, p_expected_fen text,
  p_new_fen text, p_san text, p_over_result text, p_over_reason text
) returns public.games
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; color text; spent int; left_ms int; ply int;
begin
  select * into g from public.games where id = p_game for update;
  if not found then raise exception 'Game not found'; end if;
  if p_player is distinct from g.white_id and p_player is distinct from g.black_id then raise exception 'Not your game'; end if;
  if g.status <> 'active' then raise exception 'Game is not active'; end if;
  color := case when p_player = g.white_id then 'w' else 'b' end;
  if g.turn <> color then raise exception 'Not your turn'; end if;
  -- stale / duplicate request: the position the move was validated against is no longer the current one
  if cardinality(g.moves) <> p_expected_ply or g.fen <> p_expected_fen then raise exception 'Stale request: the position changed'; end if;
  if p_uci !~ '^[a-h][1-8][a-h][1-8][qrbn]?$' then raise exception 'Bad move'; end if;
  if p_new_fen !~ '^[1-8pnbrqkPNBRQK/]{15,80} [wb] (-|[KQkq]{1,4}) (-|[a-h][36]) [0-9]{1,3} [0-9]{1,4}$' then raise exception 'Bad position'; end if;

  spent := public._elapsed_ms(g);
  left_ms := (case color when 'w' then g.white_ms else g.black_ms end) - spent;
  if cardinality(g.moves) > 0 and left_ms <= 0 then
    -- flag fell before the move arrived: the move is rejected and the game ends on time
    update public.games set white_ms = case when color = 'w' then 0 else white_ms end,
                            black_ms = case when color = 'b' then 0 else black_ms end where id = g.id;
    return public._finish_locked(g.id, case when color = 'w' then '0-1' else '1-0' end, 'Timeout');
  end if;

  ply := cardinality(g.moves) + 1;
  insert into public.game_moves (game_id, ply, uci, san, fen_after, player_id) values (g.id, ply, p_uci, p_san, p_new_fen, p_player);
  update public.games set
      fen = p_new_fen, turn = split_part(p_new_fen, ' ', 2), moves = moves || p_uci,
      white_ms = case when color = 'w' then (case when cardinality(g.moves) > 0 then left_ms + inc_ms else white_ms end) else white_ms end,
      black_ms = case when color = 'b' then left_ms + inc_ms else black_ms end,
      last_move_at = clock_timestamp(), draw_offer_by = null
    where id = g.id returning * into g;
  if p_over_result is not null then
    return public._finish_locked(g.id, p_over_result, coalesce(p_over_reason, 'Game over'));
  end if;
  return g;
end $$;

-- resign / offer_draw / decline_draw / accept_draw / timeout, each atomic and authorised under the row lock.
create or replace function public.server_game_action(p_game uuid, p_player uuid, p_action text) returns public.games
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; color text; spent int;
begin
  select * into g from public.games where id = p_game for update;
  if not found then raise exception 'Game not found'; end if;
  if p_player is distinct from g.white_id and p_player is distinct from g.black_id then raise exception 'Not your game'; end if;
  if g.status <> 'active' then raise exception 'Game is not active'; end if;
  color := case when p_player = g.white_id then 'w' else 'b' end;
  if p_action = 'resign' then
    return public._finish_locked(g.id, case when color = 'w' then '0-1' else '1-0' end, 'Resignation');
  elsif p_action = 'offer_draw' then
    update public.games set draw_offer_by = p_player where id = g.id returning * into g;
    return g;
  elsif p_action = 'decline_draw' then
    if g.draw_offer_by is null or g.draw_offer_by = p_player then raise exception 'No draw offer to decline'; end if;
    update public.games set draw_offer_by = null where id = g.id returning * into g;
    return g;
  elsif p_action = 'accept_draw' then
    if g.draw_offer_by is null or g.draw_offer_by = p_player then raise exception 'No draw offer to accept'; end if;
    return public._finish_locked(g.id, '1/2-1/2', 'Draw by agreement');
  elsif p_action = 'timeout' then
    if cardinality(g.moves) = 0 then raise exception 'No one has run out of time'; end if;
    spent := public._elapsed_ms(g);
    if g.turn = 'w' and g.white_ms - spent <= 0 then
      update public.games set white_ms = 0 where id = g.id;
      return public._finish_locked(g.id, '0-1', 'Timeout');
    elsif g.turn = 'b' and g.black_ms - spent <= 0 then
      update public.games set black_ms = 0 where id = g.id;
      return public._finish_locked(g.id, '1-0', 'Timeout');
    end if;
    raise exception 'No one has run out of time';
  end if;
  raise exception 'Unknown action';
end $$;

-- ------------------------------------------------------------------ 8. cloud progress: atomic, idempotent, multi-device safe
alter table public.user_progress add column if not exists version int not null default 0;
alter table public.user_progress add column if not exists settings_ts bigint not null default 0;
alter table public.user_progress add column if not exists baseline_v int not null default 0;

-- one row per finished rated game / solved puzzle: the primary key makes every event count exactly once
create table if not exists public.progress_games (
  user_id uuid not null references auth.users(id) on delete cascade,
  game_id text not null check (char_length(game_id) between 1 and 64),
  outcome smallint not null check (outcome in (-1, 0, 1)),
  rating_delta int not null check (rating_delta between -32 and 32),
  created_at timestamptz not null default now(),
  primary key (user_id, game_id)
);
create table if not exists public.progress_puzzles (
  user_id uuid not null references auth.users(id) on delete cascade,
  puzzle_id text not null check (char_length(puzzle_id) between 1 and 40),
  points int not null check (points between 0 and 100),
  created_at timestamptz not null default now(),
  primary key (user_id, puzzle_id)
);
alter table public.progress_games enable row level security;
alter table public.progress_puzzles enable row level security;
drop policy if exists "own progress_games" on public.progress_games;
create policy "own progress_games" on public.progress_games for select to authenticated using (user_id = auth.uid());
drop policy if exists "own progress_puzzles" on public.progress_puzzles;
create policy "own progress_puzzles" on public.progress_puzzles for select to authenticated using (user_id = auth.uid());
revoke all on public.progress_games, public.progress_puzzles from anon;
revoke insert, update, delete on public.progress_games, public.progress_puzzles from authenticated;

create or replace function public._jint(j jsonb, k text, d int) returns int
language sql immutable set search_path = public, pg_temp as $$
  select coalesce(case when jsonb_typeof(j -> k) = 'number' then (j ->> k)::numeric::int end, d);
$$;

create or replace function public._jtext_union(a jsonb, b jsonb, p_max int) returns jsonb
language sql immutable set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(x order by x), '[]'::jsonb) from (
    select distinct e as x from (
      select jsonb_array_elements_text(case when jsonb_typeof(a) = 'array' then a else '[]'::jsonb end) as e
      union all
      select jsonb_array_elements_text(case when jsonb_typeof(b) = 'array' then b else '[]'::jsonb end)
    ) s where char_length(e) between 1 and 40 limit p_max
  ) d;
$$;

-- Merges one device's pending work into the account and returns the authoritative result.
--   p_baseline  : this device's old local stats, used ONCE per account (baseline_v < 2) to carry over pre-sync progress
--   p_games     : [{id, o: -1|0|1, d: rating delta}]  new rated games (each id counts exactly once)
--   p_puzzles   : [{id, p: points}]                    newly solved puzzles (each id counts exactly once)
--   p_ach       : achievement ids (set union)
--   p_settings  : settings, accepted only when p_settings_ts is newer than the stored one
--   p_history   : game records, merged by id, newest 200 kept
create or replace function public.sync_progress(
  p_baseline jsonb, p_games jsonb, p_puzzles jsonb, p_ach jsonb, p_settings jsonb, p_settings_ts bigint, p_history jsonb
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  me uuid := auth.uid(); up public.user_progress; st jsonb; e jsonb; ins int;
  played int; wins int; losses int; draws int; rating int; pts int; solved jsonb; ach jsonb; hist jsonb; o int; d int; pp int;
begin
  if me is null then raise exception 'Not signed in'; end if;
  perform public._rate_hit(me, 'sync', 60, interval '1 minute');
  if p_games is not null and jsonb_typeof(p_games) = 'array' and jsonb_array_length(p_games) > 200 then raise exception 'Too many events'; end if;
  if p_puzzles is not null and jsonb_typeof(p_puzzles) = 'array' and jsonb_array_length(p_puzzles) > 200 then raise exception 'Too many events'; end if;
  if p_history is not null and (jsonb_typeof(p_history) <> 'array' or jsonb_array_length(p_history) > 300 or length(p_history::text) > 600000) then raise exception 'History too large'; end if;
  if p_settings is not null and (jsonb_typeof(p_settings) <> 'object' or length(p_settings::text) > 4000) then raise exception 'Bad settings'; end if;

  insert into public.user_progress (user_id) values (me) on conflict do nothing;
  select * into up from public.user_progress where user_id = me for update;   -- serialises concurrent devices

  st := coalesce(up.stats, '{}'::jsonb);
  played := public._jint(st, 'played', 0); wins := public._jint(st, 'wins', 0); losses := public._jint(st, 'losses', 0);
  draws := public._jint(st, 'draws', 0); rating := public._jint(st, 'rating', 1200); pts := public._jint(st, 'puzzlePoints', 0);
  solved := coalesce(case when jsonb_typeof(st -> 'solved') = 'array' then st -> 'solved' end, '[]'::jsonb);
  ach := coalesce(case when jsonb_typeof(st -> 'ach') = 'array' then st -> 'ach' end, '[]'::jsonb);

  -- one-time migration of pre-sync local progress (never repeated, so old local copies cannot overwrite newer data)
  if up.baseline_v < 2 and p_baseline is not null and jsonb_typeof(p_baseline) = 'object' then
    if public._jint(p_baseline, 'played', 0) > played then rating := public._jint(p_baseline, 'rating', rating); end if;
    played := greatest(played, least(public._jint(p_baseline, 'played', 0), 1000000));
    wins   := greatest(wins,   least(public._jint(p_baseline, 'wins', 0), 1000000));
    losses := greatest(losses, least(public._jint(p_baseline, 'losses', 0), 1000000));
    draws  := greatest(draws,  least(public._jint(p_baseline, 'draws', 0), 1000000));
    pts    := greatest(pts,    least(public._jint(p_baseline, 'puzzlePoints', 0), 100000));
    solved := public._jtext_union(solved, p_baseline -> 'solved', 500);
    ach    := public._jtext_union(ach, p_baseline -> 'ach', 100);
  end if;

  if p_games is not null and jsonb_typeof(p_games) = 'array' then
    for e in select * from jsonb_array_elements(p_games) loop
      continue when jsonb_typeof(e) is distinct from 'object' or jsonb_typeof(e -> 'id') is distinct from 'string';
      o := public._jint(e, 'o', 99); d := public._jint(e, 'd', 99);
      continue when o not in (-1, 0, 1) or d < -32 or d > 32;
      continue when char_length(e ->> 'id') not between 1 and 64;
      insert into public.progress_games (user_id, game_id, outcome, rating_delta) values (me, e ->> 'id', o, d) on conflict do nothing;
      get diagnostics ins = row_count;
      if ins = 1 then
        played := played + 1;
        if o = 1 then wins := wins + 1; elsif o = 0 then draws := draws + 1; else losses := losses + 1; end if;
        rating := greatest(100, rating + d);
      end if;
    end loop;
  end if;

  if p_puzzles is not null and jsonb_typeof(p_puzzles) = 'array' then
    for e in select * from jsonb_array_elements(p_puzzles) loop
      continue when jsonb_typeof(e) is distinct from 'object' or jsonb_typeof(e -> 'id') is distinct from 'string';
      pp := public._jint(e, 'p', -1);
      continue when pp < 0 or pp > 100 or char_length(e ->> 'id') not between 1 and 40;
      insert into public.progress_puzzles (user_id, puzzle_id, points) values (me, e ->> 'id', pp) on conflict do nothing;
      get diagnostics ins = row_count;
      if ins = 1 then
        pts := pts + pp;
        solved := public._jtext_union(solved, jsonb_build_array(e ->> 'id'), 500);
      end if;
    end loop;
  end if;
  ach := public._jtext_union(ach, p_ach, 100);

  hist := coalesce(up.history, '[]'::jsonb);
  if p_history is not null and jsonb_array_length(p_history) > 0 then
    select coalesce(jsonb_agg(x order by x ->> 'date' desc), '[]'::jsonb) into hist from (
      select distinct on (x ->> 'id') x from (
        select jsonb_array_elements(case when jsonb_typeof(hist) = 'array' then hist else '[]'::jsonb end) as x
        union all select jsonb_array_elements(p_history)
      ) a where jsonb_typeof(x) = 'object' and (x ->> 'id') is not null and char_length(x ->> 'id') <= 64
      order by x ->> 'id'
    ) b;
    select coalesce(jsonb_agg(x order by x ->> 'date' desc), '[]'::jsonb) into hist from (
      select x from jsonb_array_elements(hist) x order by x ->> 'date' desc limit 200) c;
  end if;

  st := jsonb_build_object('username', coalesce(st ->> 'username', 'Player'), 'rating', rating, 'played', played, 'wins', wins,
        'losses', losses, 'draws', draws, 'puzzlePoints', pts, 'solved', solved, 'ach', ach);

  update public.user_progress set
      stats = st, history = hist, version = version + 1, baseline_v = 2, updated_at = now(),
      settings = case when p_settings is not null and coalesce(p_settings_ts, 0) > settings_ts then p_settings else settings end,
      settings_ts = case when p_settings is not null and coalesce(p_settings_ts, 0) > settings_ts then p_settings_ts else settings_ts end
    where user_id = me returning * into up;

  return jsonb_build_object('stats', up.stats, 'settings', up.settings, 'settings_ts', up.settings_ts, 'history', up.history, 'version', up.version);
end $$;

-- ------------------------------------------------------------------ 9. profile trigger (fixed search_path)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
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
  if pic is null or pic !~* '^https://' or char_length(pic) > 500 then pic := null; end if;
  insert into public.profiles (id, username, avatar_url) values (new.id, final_name, pic);
  return new;
end $$;

-- ------------------------------------------------------------------ 10. function privileges
revoke all on function
  public._rate_hit(uuid, text, int, interval), public._rate_count(uuid, text, interval), public._rate_note(uuid, text),
  public._check_tc(int, int), public._room_code(), public._expire_stale(), public._finish_locked(uuid, text, text),
  public._elapsed_ms(public.games), public._jint(jsonb, text, int), public._jtext_union(jsonb, jsonb, int),
  public.server_apply_move(uuid, uuid, text, int, text, text, text, text, text),
  public.server_game_action(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.server_apply_move(uuid, uuid, text, int, text, text, text, text, text) to service_role;
grant execute on function public.server_game_action(uuid, uuid, text) to service_role;

revoke all on function public.touch_presence(), public.quick_match(int, int), public.create_room(int, int), public.join_room(text),
  public.cancel_game(uuid), public.send_challenge(uuid, int, int), public.respond_challenge(uuid, boolean),
  public.cancel_challenge(uuid), public.sync_progress(jsonb, jsonb, jsonb, jsonb, jsonb, bigint, jsonb) from public, anon;
grant execute on function public.touch_presence(), public.quick_match(int, int), public.create_room(int, int), public.join_room(text),
  public.cancel_game(uuid), public.send_challenge(uuid, int, int), public.respond_challenge(uuid, boolean),
  public.cancel_challenge(uuid), public.sync_progress(jsonb, jsonb, jsonb, jsonb, jsonb, bigint, jsonb) to authenticated;

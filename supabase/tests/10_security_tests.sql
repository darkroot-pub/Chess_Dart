-- DarkChess SQL security + game-engine tests. Every check raises on failure; the script stops at the first failure.
\set ON_ERROR_STOP on
\set QUIET on
create schema t;
alter default privileges for role nobody, authenticated, anon, service_role in schema t grant all on tables to public;
set search_path to t, public;
grant usage, create on schema t to public;
create table t.results (name text);
grant all on t.results to anon, authenticated, service_role;

create function t.pass(n text) returns void language sql as $$ insert into t.results values (n) $$;
create function t.assert(cond boolean, n text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'TEST FAILED: %', n; end if;
  insert into t.results values (n);
end $$;
-- runs sql and requires it to FAIL with a message matching pattern
create function t.expect_error(q text, pat text, n text) returns void language plpgsql as $$
declare m text;
begin
  begin execute q; exception when others then m := sqlerrm; end;
  if m is null then raise exception 'TEST FAILED (no error raised): %', n; end if;
  if m !~* pat then raise exception 'TEST FAILED (wrong error "%", wanted /%/): %', m, pat, n; end if;
  insert into t.results values (n);
end $$;
create function t.become(u uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u::text, false); execute 'set role authenticated'; end $$;
create function t.anon() returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '', false); execute 'set role anon'; end $$;
create function t.service() returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '', false); execute 'set role service_role'; end $$;
create function t.code_of(m int) returns text language sql security definer as $$
  select code from public.games where white_id = 'aaaaaaaa-0000-0000-0000-000000000001' and minutes = m and status = 'waiting' and is_private order by created_at desc limit 1 $$;
-- the helpers themselves must run as the superuser, so they are defined before any "set role"

insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@x', '{"username":"Alice"}'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@x', '{"username":"Bob"}'),
  ('cccccccc-0000-0000-0000-000000000003', 'c@x', '{"username":"Carol","picture":"http://evil.example/x.png"}'),
  ('dddddddd-0000-0000-0000-000000000004', 'd@x', '{"username":"Dave"}');
select t.assert((select count(*) from public.profiles) = 4, 'profile trigger creates a row per user');
select t.assert((select avatar_url from public.profiles where username = 'Carol') is null, 'non-https avatar from sign-up metadata is dropped');

-- ============================================================ RLS / privileges
select t.become('aaaaaaaa-0000-0000-0000-000000000001');
select t.expect_error($q$update public.profiles set rating = 3000 where id = 'aaaaaaaa-0000-0000-0000-000000000001'$q$, 'permission denied', 'user cannot edit own rating');
select t.expect_error($q$update public.profiles set games_played = 99 where id = 'aaaaaaaa-0000-0000-0000-000000000001'$q$, 'permission denied', 'user cannot edit own stats');
do $$ declare n int; begin
  update public.profiles set username = 'Hacked' where id = 'bbbbbbbb-0000-0000-0000-000000000002';
  get diagnostics n = row_count;
  perform t.assert(n = 0, 'user cannot rename another user');
end $$;
do $$ declare n int; begin
  update public.profiles set username = 'AliceNew' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  get diagnostics n = row_count;
  perform t.assert(n = 1, 'user can rename self');
end $$;
select t.expect_error($q$update public.profiles set avatar_url = 'http://x/y.png' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$q$, 'profiles_avatar_chk', 'http avatar rejected');
select t.expect_error($q$update public.profiles set avatar_url = 'javascript:alert(1)' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$q$, 'profiles_avatar_chk', 'javascript: avatar rejected');
update public.profiles set avatar_url = 'https://lh3.googleusercontent.com/a/pic' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select t.expect_error($q$insert into public.games (white_id, black_id, status) values ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002','active')$q$, 'permission denied', 'client cannot insert games');
select t.expect_error($q$update public.games set result = '1-0'$q$, 'permission denied', 'client cannot update games');
select t.expect_error($q$delete from public.games$q$, 'permission denied', 'client cannot delete games');
select t.expect_error($q$insert into public.game_moves (game_id, ply, uci, fen_after, player_id) values (gen_random_uuid(), 1, 'e2e4', 'x', 'aaaaaaaa-0000-0000-0000-000000000001')$q$, 'permission denied', 'client cannot forge moves');
select t.expect_error($q$select * from public.rate_events$q$, 'permission denied', 'rate_events hidden from clients');
select t.expect_error($q$select public.server_apply_move(gen_random_uuid(), gen_random_uuid(), 'e2e4', 0, 'x', 'x', 'e4', null, null)$q$, 'permission denied', 'authenticated cannot call server_apply_move');
select t.expect_error($q$select public.server_game_action(gen_random_uuid(), gen_random_uuid(), 'resign')$q$, 'permission denied', 'authenticated cannot call server_game_action');
select t.expect_error($q$select public._finish_locked(gen_random_uuid(), '1-0', 'x')$q$, 'permission denied', 'authenticated cannot call _finish_locked');
select t.expect_error($q$insert into public.progress_games values ('aaaaaaaa-0000-0000-0000-000000000001', 'x', 1, 10)$q$, 'permission denied', 'client cannot write progress ledger');
select t.expect_error($q$insert into public.friendships values ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001')$q$, 'friendships_self_chk|row-level security', 'cannot friend yourself');
select t.expect_error($q$insert into public.friendships values ('bbbbbbbb-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001')$q$, 'row-level security', 'cannot create friendships on behalf of others');
reset role;

select t.anon();
select t.expect_error($q$select * from public.profiles$q$, 'permission denied', 'anon role cannot read profiles');
select t.expect_error($q$select * from public.games$q$, 'permission denied', 'anon role cannot read games');
select t.expect_error($q$select * from public.leaderboard$q$, 'permission denied', 'anon role cannot read leaderboard');
select t.expect_error($q$select public.quick_match(5, 0)$q$, 'permission denied', 'anon role cannot call quick_match');
select t.expect_error($q$select public.sync_progress(null,null,null,null,null,0,null)$q$, 'permission denied', 'anon role cannot call sync_progress');
reset role;

-- ============================================================ RPC input validation
select t.become('aaaaaaaa-0000-0000-0000-000000000001');
select t.expect_error($q$select public.create_room(0, 0)$q$, 'Invalid time control', 'create_room rejects 0 minutes');
select t.expect_error($q$select public.create_room(-5, 0)$q$, 'Invalid time control', 'create_room rejects negative minutes');
select t.expect_error($q$select public.create_room(100000, 0)$q$, 'Invalid time control', 'create_room rejects huge minutes');
select t.expect_error($q$select public.create_room(5, -3)$q$, 'Invalid time control', 'create_room rejects negative increment');
select t.expect_error($q$select public.create_room(5, 61)$q$, 'Invalid time control', 'create_room rejects huge increment');
select t.expect_error($q$select public.create_room(null, 0)$q$, 'Invalid time control', 'create_room rejects null');
select t.expect_error($q$select public.quick_match(2000000000, 0)$q$, 'Invalid time control', 'quick_match rejects huge minutes');
select t.expect_error($q$select public.quick_match(5, -1)$q$, 'Invalid time control', 'quick_match rejects negative increment');
select t.expect_error($q$select public.send_challenge('bbbbbbbb-0000-0000-0000-000000000002', 0, 0)$q$, 'Invalid time control', 'send_challenge rejects bad time control');
select t.expect_error($q$select public.send_challenge('aaaaaaaa-0000-0000-0000-000000000001', 5, 0)$q$, 'cannot challenge yourself', 'cannot challenge yourself');
select t.expect_error($q$select public.send_challenge(gen_random_uuid(), 5, 0)$q$, 'Player not found', 'challenge to unknown player rejected');
select t.expect_error($q$select public.send_challenge(null, 5, 0)$q$, 'Player not found', 'challenge to null rejected');
reset role;

-- ============================================================ private rooms
select t.become('aaaaaaaa-0000-0000-0000-000000000001');
create table room as select * from public.create_room(5, 0);
select t.assert((select code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$' from room), 'room code is 8 chars from the 32-symbol alphabet');
select t.assert((select count(*) from public.games where code is not null) = 1, 'creator can see own waiting room');
select t.expect_error($q$select public.join_room((select code from room))$q$, 'You created this room', 'creator cannot join own room');
reset role;

select t.become('cccccccc-0000-0000-0000-000000000003');
select t.assert((select count(*) from public.games) = 0, 'outsider cannot read a private room (RLS)');
select t.assert((select count(*) from public.games where code is not null) = 0, 'outsider cannot discover room codes');
-- brute force: 10 wrong codes are tolerated, then the account is locked out (even for the right code)
do $$ declare i int; r public.games; begin
  for i in 1..10 loop
    r := public.join_room('ZZZZZZZ' || i);
    perform t.assert(r.id is null, 'wrong code ' || i || ' returns nothing');
  end loop;
end $$;
select t.expect_error($q$select public.join_room('AAAAAAAA')$q$, 'Too many wrong room codes', 'brute force locked after 10 wrong codes');
select t.expect_error($q$select public.join_room((select code from room))$q$, 'Too many wrong room codes', 'lockout also blocks the correct code');
reset role;

select t.become('bbbbbbbb-0000-0000-0000-000000000002');
select t.assert((select public.join_room('  ' || lower((select code from room)) || ' ')).id is not null, 'Bob joins with the code (case/space tolerant)');
select t.assert((select count(*) from public.games where black_id = auth.uid() and status = 'active') = 1, 'game is active for both players');
select t.assert(public.join_room((select code from room)) is null, 'a started room cannot be joined again');
reset role;
select t.assert((select count(*) from public.game_moves) = 0, 'no moves yet');

-- expiry of abandoned rooms
select t.become('dddddddd-0000-0000-0000-000000000004');
create table room2 as select * from public.create_room(3, 2);
reset role;
update public.games set created_at = now() - interval '31 minutes' where id = (select id from room2);
select t.become('aaaaaaaa-0000-0000-0000-000000000001');
select public.create_room(1, 0);
reset role;
select t.assert((select count(*) from public.games where id = (select id from room2)) = 0, 'abandoned private room expired');
select t.become('cccccccc-0000-0000-0000-000000000003');
select t.expect_error($q$select public.join_room('AAAAAAAA')$q$, 'Too many wrong', 'still locked out (limit window is 10 minutes)');
reset role;
delete from public.rate_events;  -- reset window for the rest of the tests

-- ============================================================ quick match
select t.become('aaaaaaaa-0000-0000-0000-000000000001');
create table qa as select * from public.quick_match(10, 0);
select t.assert((select status from qa) = 'waiting', 'first searcher waits');
select t.assert((select id from public.quick_match(10, 0)) = (select id from qa), 're-polling returns the same waiting game');
select t.assert((select count(*) from public.games where white_id = auth.uid() and status = 'waiting' and not is_private) = 1, 'no duplicate waiting games');
reset role;
select t.become('bbbbbbbb-0000-0000-0000-000000000002');
create table qb as select * from public.quick_match(10, 0);
select t.assert((select id from qb) = (select id from qa) and (select status from qb) = 'active', 'second searcher is matched');
select t.assert((select white_id from qb) = 'aaaaaaaa-0000-0000-0000-000000000001' and (select black_id from qb) = 'bbbbbbbb-0000-0000-0000-000000000002', 'colours assigned');
reset role;

-- ============================================================ challenges
select t.become('aaaaaaaa-0000-0000-0000-000000000001');
create table ch as select * from public.send_challenge('cccccccc-0000-0000-0000-000000000003', 5, 3);
select t.expect_error($q$select public.send_challenge('cccccccc-0000-0000-0000-000000000003', 5, 3)$q$, 'already have a pending challenge', 'duplicate challenge rejected');
reset role;
select t.become('dddddddd-0000-0000-0000-000000000004');
select t.expect_error($q$select public.respond_challenge((select id from ch), true)$q$, 'expired or already answered', 'third party cannot answer a challenge');
select t.assert((select count(*) from public.challenges) = 0, 'third party cannot see a challenge');
reset role;
update public.challenges set created_at = now() - interval '11 minutes' where id = (select id from ch);
select t.become('cccccccc-0000-0000-0000-000000000003');
select t.expect_error($q$select public.respond_challenge((select id from ch), true)$q$, 'expired or already answered', 'expired challenge cannot be accepted');
reset role;
select t.become('aaaaaaaa-0000-0000-0000-000000000001');
create table ch2 as select * from public.send_challenge('cccccccc-0000-0000-0000-000000000003', 5, 3);
reset role;
select t.become('cccccccc-0000-0000-0000-000000000003');
create table ch2r as select * from public.respond_challenge((select id from ch2), true);
select t.assert((select status from ch2r) = 'accepted' and (select game_id from ch2r) is not null, 'valid challenge accepted -> game');
select t.expect_error($q$select public.respond_challenge((select id from ch2), true)$q$, 'expired or already answered', 'challenge cannot be accepted twice');
select t.assert((select count(*) from public.games where id = (select game_id from ch2r) and status = 'active' and inc_ms = 3000) = 1, 'game created with the challenge time control');
reset role;

-- ============================================================ authoritative game engine
-- game G: Alice (white) vs Bob (black), 5+2
select t.become('aaaaaaaa-0000-0000-0000-000000000001');
create table g0 as select * from public.quick_match(5, 2);
reset role;
select t.become('bbbbbbbb-0000-0000-0000-000000000002');
select public.quick_match(5, 2);
reset role;
create table gid as select id from public.games where white_id = 'aaaaaaaa-0000-0000-0000-000000000001' and minutes = 5 and inc_ms = 2000;

select t.service();
select t.expect_error($q$select public.server_apply_move((select id from gid), 'bbbbbbbb-0000-0000-0000-000000000002', 'e7e5', 0, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq e6 0 1', 'e5', null, null)$q$, 'Not your turn', 'wrong-turn move rejected');
select t.expect_error($q$select public.server_apply_move((select id from gid), 'cccccccc-0000-0000-0000-000000000003', 'e2e4', 0, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', 'e4', null, null)$q$, 'Not your game', 'non-participant move rejected');
select t.expect_error($q$select public.server_apply_move((select id from gid), 'aaaaaaaa-0000-0000-0000-000000000001', 'e2e4', 5, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', 'e4', null, null)$q$, 'Stale request', 'stale ply rejected');
select t.expect_error($q$select public.server_apply_move((select id from gid), 'aaaaaaaa-0000-0000-0000-000000000001', 'e2e4', 0, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', 'e4', null, null)$q$, 'Stale request', 'client cannot claim a different current position');
select t.expect_error($q$select public.server_apply_move((select id from gid), 'aaaaaaaa-0000-0000-0000-000000000001', 'e2e4; drop table games', 0, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', 'e4', null, null)$q$, 'Bad move', 'malformed uci rejected');
select t.expect_error($q$select public.server_apply_move((select id from gid), 'aaaaaaaa-0000-0000-0000-000000000001', 'e2e4', 0, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'garbage', 'e4', null, null)$q$, 'Bad position', 'malformed fen rejected');
select t.assert((select count(*) from public.game_moves where game_id = (select id from gid)) = 0, 'rejected moves leave no trace');

create table m1 as select * from public.server_apply_move((select id from gid), 'aaaaaaaa-0000-0000-0000-000000000001', 'e2e4', 0, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', 'e4', null, null);
select t.assert((select turn from m1) = 'b' and cardinality((select moves from m1)) = 1, 'legal first move stored, turn switched');
select t.assert((select white_ms from m1) = 300000 and (select black_ms from m1) = 300000, 'clock does not move on the first move (no increment either)');
select t.expect_error($q$select public.server_apply_move((select id from gid), 'aaaaaaaa-0000-0000-0000-000000000001', 'e2e4', 0, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', 'e4', null, null)$q$, 'Not your turn|Stale request', 'duplicate request rejected');
select pg_sleep(1.2);
create table m2 as select * from public.server_apply_move((select id from gid), 'bbbbbbbb-0000-0000-0000-000000000002', 'e7e5', 1, 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2', 'e5', null, null);
select t.assert((select black_ms from m2) between 300000 - 2500 + 2000 and 300000 - 1100 + 2000, 'server clock: black lost ~1.2s and gained the 2s increment');
select t.assert((select white_ms from m2) = 300000, 'white clock untouched while black thinks');
select t.assert((select count(*) from public.game_moves where game_id = (select id from gid)) = 2, 'both moves recorded once');
reset role;

-- draw offers
select t.service();
select t.expect_error($q$select public.server_game_action((select id from gid), 'aaaaaaaa-0000-0000-0000-000000000001', 'accept_draw')$q$, 'No draw offer', 'cannot accept a draw nobody offered');
select public.server_game_action((select id from gid), 'aaaaaaaa-0000-0000-0000-000000000001', 'offer_draw');
select t.expect_error($q$select public.server_game_action((select id from gid), 'aaaaaaaa-0000-0000-0000-000000000001', 'accept_draw')$q$, 'No draw offer', 'cannot accept your own draw offer');
select t.expect_error($q$select public.server_game_action((select id from gid), 'cccccccc-0000-0000-0000-000000000003', 'accept_draw')$q$, 'Not your game', 'outsider cannot accept draw');
select public.server_game_action((select id from gid), 'bbbbbbbb-0000-0000-0000-000000000002', 'decline_draw');
select t.assert((select draw_offer_by from public.games where id = (select id from gid)) is null, 'decline clears the offer');
select public.server_game_action((select id from gid), 'bbbbbbbb-0000-0000-0000-000000000002', 'offer_draw');
create table dr as select * from public.server_game_action((select id from gid), 'aaaaaaaa-0000-0000-0000-000000000001', 'accept_draw');
select t.assert((select status from dr) = 'finished' and (select result from dr) = '1/2-1/2', 'draw by agreement ends the game');
select t.assert((select games_played from public.profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 1, 'rating applied once (2 plies played)');
select t.expect_error($q$select public.server_game_action((select id from gid), 'bbbbbbbb-0000-0000-0000-000000000002', 'resign')$q$, 'not active', 'finished game cannot be resigned');
select t.expect_error($q$select public.server_apply_move((select id from gid), 'aaaaaaaa-0000-0000-0000-000000000001', 'd2d4', 2, 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2', 'rnbqkbnr/pppp1ppp/8/4p3/3PP3/8/PPP2PPP/RNBQKBNR b KQkq d3 0 2', 'd4', null, null)$q$, 'not active', 'no moves after the game finished');
select t.assert((select games_played from public.profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 1 and (select games_played from public.profiles where id = 'bbbbbbbb-0000-0000-0000-000000000002') = 1, 'no duplicate rating update after finish');
reset role;

-- timeout: Alice (white) is to move and her flag has fallen
select t.become('aaaaaaaa-0000-0000-0000-000000000001'); select public.create_room(3, 0); reset role;
select t.become('bbbbbbbb-0000-0000-0000-000000000002'); create table tg as select * from public.join_room(t.code_of(3)); reset role;
select t.service();
select public.server_apply_move((select id from tg), 'aaaaaaaa-0000-0000-0000-000000000001', 'e2e4', 0, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', 'e4', null, null);
select public.server_apply_move((select id from tg), 'bbbbbbbb-0000-0000-0000-000000000002', 'e7e5', 1, 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2', 'e5', null, null);
select t.expect_error($q$select public.server_game_action((select id from tg), 'bbbbbbbb-0000-0000-0000-000000000002', 'timeout')$q$, 'No one has run out of time', 'timeout cannot be claimed while time remains');
reset role;
update public.games set last_move_at = now() - interval '4 minutes' where id = (select id from tg);   -- simulate 4 idle minutes on a 3 minute clock
select t.service();
select t.expect_error($q$select public.server_game_action((select id from tg), 'aaaaaaaa-0000-0000-0000-000000000001', 'offer_draw'); select 1/0$q$, 'division', 'sanity: offer works');  -- offers are still allowed; rolled back by the error
create table to1 as select * from public.server_apply_move((select id from tg), 'aaaaaaaa-0000-0000-0000-000000000001', 'g1f3', 2, 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2', 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2', 'Nf3', null, null);
select t.assert((select status from to1) = 'finished' and (select result from to1) = '0-1' and (select reason from to1) = 'Timeout', 'a move that arrives after the flag fell loses on time instead of being accepted');
select t.assert(cardinality((select moves from to1)) = 2, 'the late move was not stored');
select t.assert((select white_ms from to1) = 0, 'flagged clock is zero');
select t.expect_error($q$select public.server_game_action((select id from tg), 'bbbbbbbb-0000-0000-0000-000000000002', 'timeout')$q$, 'not active', 'timeout cannot be claimed twice (no duplicate rating)');
select t.assert((select games_played from public.profiles where id = 'bbbbbbbb-0000-0000-0000-000000000002') = 2 and (select wins from public.profiles where id = 'bbbbbbbb-0000-0000-0000-000000000002') = 1, 'timeout rating applied exactly once');
reset role;

-- opponent claims a timeout on an idle game
select t.become('aaaaaaaa-0000-0000-0000-000000000001'); select public.create_room(1, 0); reset role;
select t.become('bbbbbbbb-0000-0000-0000-000000000002'); create table tg2 as select * from public.join_room(t.code_of(1)); reset role;
select t.service();
select public.server_apply_move((select id from tg2), 'aaaaaaaa-0000-0000-0000-000000000001', 'e2e4', 0, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1', 'e4', null, null);
reset role;
update public.games set last_move_at = now() - interval '2 minutes' where id = (select id from tg2);
select t.service();
create table to2 as select * from public.server_game_action((select id from tg2), 'aaaaaaaa-0000-0000-0000-000000000001', 'timeout');
select t.assert((select result from to2) = '1-0' and (select reason from to2) = 'Timeout', 'opponent can claim timeout; black (to move) loses');
select t.assert((select rating from public.profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001') >= 100, 'rating stays above the floor');
reset role;

-- aborted games never move ratings (no rating farming by instant resignation)
select t.become('aaaaaaaa-0000-0000-0000-000000000001'); select public.create_room(2, 0); reset role;
select t.become('bbbbbbbb-0000-0000-0000-000000000002'); create table tg3 as select * from public.join_room(t.code_of(2)); reset role;
create table before_r as select id, rating, games_played from public.profiles;
select t.service();
select public.server_game_action((select id from tg3), 'bbbbbbbb-0000-0000-0000-000000000002', 'resign');
reset role;
select t.assert(not exists (select 1 from public.profiles p join before_r b using (id) where p.rating <> b.rating or p.games_played <> b.games_played), 'resignation before move 2 does not change ratings');

-- checkmate via the over-result path (fool''s mate, 4 plies) -> ratings move once
select t.become('aaaaaaaa-0000-0000-0000-000000000001'); select public.create_room(5, 0); reset role;
select t.become('bbbbbbbb-0000-0000-0000-000000000002'); create table tg4 as select * from public.join_room(t.code_of(5)); reset role;
select t.service();
select public.server_apply_move((select id from tg4), 'aaaaaaaa-0000-0000-0000-000000000001', 'f2f3', 0, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/8/5P2/PPPPP1PP/RNBQKBNR b KQkq - 0 1', 'f3', null, null);
select public.server_apply_move((select id from tg4), 'bbbbbbbb-0000-0000-0000-000000000002', 'e7e5', 1, 'rnbqkbnr/pppppppp/8/8/8/5P2/PPPPP1PP/RNBQKBNR b KQkq - 0 1', 'rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq e6 0 2', 'e5', null, null);
select public.server_apply_move((select id from tg4), 'aaaaaaaa-0000-0000-0000-000000000001', 'g2g4', 2, 'rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq e6 0 2', 'rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2', 'g4', null, null);
create table mate as select * from public.server_apply_move((select id from tg4), 'bbbbbbbb-0000-0000-0000-000000000002', 'd8h4', 3, 'rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2', 'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3', 'Qh4#', '0-1', 'Checkmate');
select t.assert((select status from mate) = 'finished' and (select result from mate) = '0-1' and (select reason from mate) = 'Checkmate', 'checkmate finishes the game atomically with the last move');
select t.assert((select count(*) from public.game_moves where game_id = (select id from tg4)) = 4, 'all 4 plies stored');
reset role;
select t.assert((select rating from public.profiles where id = 'bbbbbbbb-0000-0000-0000-000000000002') > (select rating from before_r where id = 'bbbbbbbb-0000-0000-0000-000000000002'), 'winner gained rating');
select t.assert((select rating from public.profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001') < (select rating from before_r where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'loser lost rating');
select t.service();
select t.expect_error($q$select public.server_apply_move((select id from tg4), 'aaaaaaaa-0000-0000-0000-000000000001', 'a2a3', 4, 'x', 'rnb1kbnr/pppp1ppp/8/4p3/6Pq/P4P2/1PPPP2P/RNBQKBNR b KQkq - 0 3', 'a3', null, null)$q$, 'not active', 'no move after checkmate');
reset role;

-- players can read their own game and moves, not others'
select t.become('cccccccc-0000-0000-0000-000000000003');
select t.assert((select count(*) from public.game_moves) = 0, 'outsider sees no moves');
reset role;
select t.become('bbbbbbbb-0000-0000-0000-000000000002');
select t.assert((select count(*) from public.game_moves where game_id = (select id from tg4)) = 4, 'participant reads own moves');
reset role;

-- ============================================================ cloud progress
select t.become('aaaaaaaa-0000-0000-0000-000000000001');
create table s1 as select public.sync_progress('{"played":5,"wins":3,"losses":1,"draws":1,"rating":1300,"puzzlePoints":20,"solved":["p1"],"ach":["first_game"]}'::jsonb,
  '[{"id":"g1","o":1,"d":12},{"id":"g2","o":-1,"d":-10}]'::jsonb, '[{"id":"p2","p":10}]'::jsonb, '["first_win"]'::jsonb, '{"sound":false}'::jsonb, 100, '[{"id":"g1","date":"2026-01-01"}]'::jsonb) as r;
select t.assert((select (r->'stats'->>'played')::int from s1) = 7, 'baseline (5) + 2 new games = 7');
select t.assert((select (r->'stats'->>'wins')::int from s1) = 4 and (select (r->'stats'->>'losses')::int from s1) = 2, 'wins/losses incremented from events');
select t.assert((select (r->'stats'->>'rating')::int from s1) = 1302, 'rating = baseline 1300 +12 -10');
select t.assert((select (r->'stats'->>'puzzlePoints')::int from s1) = 30, 'puzzle points = 20 + 10');
-- the same events again (retry / duplicate delivery) change nothing
create table s2 as select public.sync_progress(null, '[{"id":"g1","o":1,"d":12},{"id":"g2","o":-1,"d":-10}]'::jsonb, '[{"id":"p2","p":10}]'::jsonb, '[]'::jsonb, null, 0, '[{"id":"g1","date":"2026-01-01"}]'::jsonb) as r;
select t.assert((select r->'stats' from s2) = (select r->'stats' from s1), 'replayed events are idempotent (no double counting)');
select t.assert((select jsonb_array_length(r->'history') from s2) = 1, 'history merged by id (no duplicates)');
-- a second device with its own events: increments are SUMMED, not max-merged
create table s3 as select public.sync_progress('{"played":1,"wins":1}'::jsonb, '[{"id":"dev2-g1","o":0,"d":0},{"id":"dev2-g2","o":1,"d":9}]'::jsonb, '[{"id":"p3","p":5},{"id":"p2","p":10}]'::jsonb, '[]'::jsonb, '{"sound":true}'::jsonb, 50, '[{"id":"dev2-g1","date":"2026-02-01"}]'::jsonb) as r;
select t.assert((select (r->'stats'->>'played')::int from s3) = 9, 'second device adds 2 games on top of 7 (no lost increments)');
select t.assert((select (r->'stats'->>'puzzlePoints')::int from s3) = 35, 'duplicate puzzle ignored, new puzzle counted');
select t.assert((select jsonb_array_length(r->'stats'->'solved') from s3) = 3, 'solved set union (p1,p2,p3)');
select t.assert((select r->'settings'->>'sound' from s3) = 'false', 'older settings (ts 50) do not overwrite newer ones (ts 100)');
select t.assert((select jsonb_array_length(r->'history') from s3) = 2, 'history from both devices kept');
select t.assert((select (r->>'version')::int from s3) = 3, 'version increments on every sync');
select t.assert((select r->'history'->0->>'id' from s3) = 'dev2-g1', 'history newest first');
-- invalid events are ignored, oversize payloads rejected
create table s4 as select public.sync_progress(null, '[{"id":"cheat","o":1,"d":500},{"id":"x","o":7,"d":1},{"o":1,"d":1},"junk"]'::jsonb, '[{"id":"pz","p":9999}]'::jsonb, '[]'::jsonb, null, 0, null) as r;
select t.assert((select (r->'stats'->>'played')::int from s4) = 9, 'out-of-range rating deltas / outcomes are ignored');
select t.assert((select (r->'stats'->>'puzzlePoints')::int from s4) = 35, 'absurd puzzle points ignored');
select t.expect_error($q$select public.sync_progress(null, (select jsonb_agg(jsonb_build_object('id', i, 'o', 1, 'd', 1)) from generate_series(1, 500) i), '[]'::jsonb, '[]'::jsonb, null, 0, null)$q$, 'Too many events', 'event flood rejected');
reset role;
select t.become('bbbbbbbb-0000-0000-0000-000000000002');
select t.assert((select count(*) from public.user_progress) = 0 and (select count(*) from public.progress_games) = 0, 'other users cannot read my progress');
reset role;

-- ============================================================ SECURITY DEFINER audit
select t.assert(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')),
  'every SECURITY DEFINER function pins search_path');
select t.assert(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and p.proname !~ '^(handle_new_user)$'
    and has_function_privilege('anon', p.oid, 'execute')),
  'no SECURITY DEFINER function is executable by anon');
select t.assert(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('server_apply_move','server_game_action','_finish_locked') and has_function_privilege('authenticated', p.oid, 'execute')),
  'game engine functions are not callable by clients');

\echo
select count(*) || ' checks passed' as result from t.results;

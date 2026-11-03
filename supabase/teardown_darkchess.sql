-- DarkChess TEARDOWN: removes everything that schema.sql + patch_2/3/4 created, for a project you ran them in by mistake.
-- Run in the SQL Editor of the WRONG project only. It touches only objects with DarkChess names.
--
-- Safety: if any DarkChess table already holds rows, the script STOPS and changes nothing, because the rows might be
-- real data from that project. Read the message, and if you are sure the data is disposable, change
--     force_delete boolean := false;   ->   force_delete boolean := true;
-- and run it again.
do $$
declare
  force_delete boolean := false;
  t text; n bigint; total bigint := 0; msg text := '';
  f record;
begin
  foreach t in array array['games','game_moves','friendships','challenges','user_progress',
                           'progress_games','progress_puzzles','rate_events'] loop
    if to_regclass('public.' || t) is not null then
      execute format('select count(*) from public.%I', t) into n;
      if n > 0 then total := total + n; msg := msg || format(' %s=%s', t, n); end if;
    end if;
  end loop;
  if total > 0 and not force_delete then
    raise exception 'STOPPED, nothing was changed. These tables contain rows:%. If they are disposable, set force_delete to true at the top of this script and run it again.', msg;
  end if;

  -- trigger + view first (they depend on the tables/functions)
  execute 'drop trigger if exists on_auth_user_created on auth.users';
  execute 'drop view if exists public.leaderboard';

  -- every DarkChess function, whatever its argument list
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
    where s.nspname = 'public' and p.proname in (
      'handle_new_user','touch_presence','quick_match','create_room','join_room','cancel_game',
      'send_challenge','respond_challenge','cancel_challenge','_rate_hit','_rate_count','_rate_note',
      '_check_tc','_room_code','_expire_stale','_finish_locked','_elapsed_ms','server_apply_move',
      'server_game_action','_jint','_jtext_union','sync_progress')
  loop
    execute 'drop function if exists ' || f.sig || ' cascade';
  end loop;

  -- tables (policies, indexes, constraints and the realtime publication entry go with them)
  drop table if exists public.progress_games, public.progress_puzzles, public.rate_events,
                       public.game_moves, public.challenges, public.friendships, public.user_progress cascade;
  drop table if exists public.games cascade;

  -- profiles: dropped only if it is clearly the DarkChess one (has our columns). Otherwise it was already yours.
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='games_played')
     and exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='last_seen') then
    drop table public.profiles cascade;
    raise notice 'profiles table (DarkChess version) dropped';
  elsif to_regclass('public.profiles') is not null then
    raise notice 'public.profiles looks like it existed before DarkChess, so it was NOT dropped. Only the avatar_url column we added is removed.';
    alter table public.profiles drop column if exists avatar_url;
  end if;

  raise notice 'DarkChess objects removed.';
end $$;

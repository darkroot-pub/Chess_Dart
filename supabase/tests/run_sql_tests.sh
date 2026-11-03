#!/usr/bin/env bash
# Runs the migrations + SQL tests against a throw-away database on a local PostgreSQL (>= 14).
# Usage: PGHOST=/tmp PGPORT=54329 PGUSER=nobody ./run_sql_tests.sh
set -euo pipefail
cd "$(dirname "$0")"
DB="darkchess_test_$$"
psql -v ON_ERROR_STOP=1 -qc "create database $DB" postgres
trap 'psql -qc "drop database if exists $DB" postgres >/dev/null' EXIT
run() { psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$1" >/dev/null; }
run 00_supabase_stub.sql
run ../schema.sql
run ../patch_2_fix_room_and_progress.sql
run ../patch_3_social.sql
run ../patch_4_security.sql
run ../patch_4_security.sql   # migration must be re-runnable
psql -v ON_ERROR_STOP=1 -d "$DB" -f 10_security_tests.sql

# ------------------------------------------------------------------------------------------------
# Real concurrency tests: several psql sessions hit the same game at the same moment.
# ------------------------------------------------------------------------------------------------
q() { psql -v ON_ERROR_STOP=1 -qtA -d "$DB" "$@"; }
E=eeeeeeee-0000-0000-0000-000000000005; F=ffffffff-0000-0000-0000-000000000006
q -c "insert into auth.users (id, email, raw_user_meta_data) values ('$E','e@x','{\"username\":\"Erin\"}'),('$F','f@x','{\"username\":\"Frank\"}')"
START='rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
AFTER='rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1'

echo "== concurrency: 8 identical simultaneous moves -> exactly one wins"
G=$(q -c "insert into public.games (white_id, black_id, status, minutes, inc_ms, white_ms, black_ms) values ('$E','$F','active',5,0,300000,300000) returning id" | head -1)
pids=(); for i in 1 2 3 4 5 6 7 8; do
  ( q -c "set role service_role; select public.server_apply_move('$G','$E','e2e4',0,'$START','$AFTER','e4',null,null)" >/tmp/dc_conc_$i.out 2>&1 && echo ok > /tmp/dc_conc_$i.res || echo fail > /tmp/dc_conc_$i.res ) &
  pids+=($!)
done; wait "${pids[@]}"
OK=$(cat /tmp/dc_conc_*.res | grep -c '^ok$'); echo "successful requests: $OK"
[ "$OK" = "1" ] || { echo "FAILED: expected exactly 1 success"; exit 1; }
[ "$(q -c "select cardinality(moves) from public.games where id='$G'")" = "1" ] || { echo "FAILED: moves length"; exit 1; }
[ "$(q -c "select count(*) from public.game_moves where game_id='$G'")" = "1" ] || { echo "FAILED: game_moves rows"; exit 1; }
rm -f /tmp/dc_conc_*.res /tmp/dc_conc_*.out

echo "== concurrency: both players resign at the same instant -> finished once, ratings applied once"
G2=$(q -c "insert into public.games (white_id, black_id, status, minutes, inc_ms, white_ms, black_ms, moves) values ('$E','$F','active',5,0,300000,300000,'{e2e4,e7e5}') returning id" | head -1)
before=$(q -c "select sum(games_played) from public.profiles where id in ('$E','$F')")
pids=(); for who in $E $F $E $F $E $F; do
  ( q -c "set role service_role; select public.server_game_action('$G2','$who','resign')" >/dev/null 2>&1 || true ) & pids+=($!)
done; wait "${pids[@]}"
after=$(q -c "select sum(games_played) from public.profiles where id in ('$E','$F')")
[ "$((after - before))" = "2" ] || { echo "FAILED: games_played changed by $((after - before)), expected 2 (one finish, two players)"; exit 1; }
[ "$(q -c "select status from public.games where id='$G2'")" = "finished" ] || { echo "FAILED: not finished"; exit 1; }
echo "ratings applied once"

echo "== concurrency: simultaneous quick_match calls always pair up (10 rounds)"
for r in $(seq 1 10); do
  A=$(q -c "insert into auth.users (email) values ('qa$r@x') returning id" | head -1); B=$(q -c "insert into auth.users (email) values ('qb$r@x') returning id" | head -1)
  ( q -c "set role authenticated; select set_config('request.jwt.claim.sub','$A',false); select public.quick_match(7,1)" >/dev/null 2>&1 ) &
  p1=$!
  ( q -c "set role authenticated; select set_config('request.jwt.claim.sub','$B',false); select public.quick_match(7,1)" >/dev/null 2>&1 ) &
  p2=$!
  wait $p1 $p2
  n=$(q -c "select count(*) from public.games where status='active' and ((white_id='$A' and black_id='$B') or (white_id='$B' and black_id='$A'))")
  [ "$n" = "1" ] || { echo "FAILED round $r: players were not paired (active games between them: $n)"; exit 1; }
done
echo "all 10 rounds paired"
echo "ALL SQL + CONCURRENCY TESTS PASSED"

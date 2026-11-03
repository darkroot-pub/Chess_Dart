# DarkChess security audit and hardening report

Scope: Flutter app, Supabase schema/RPCs/RLS, the `game-action` edge function, cloud sync, Stockfish/review pipeline,
Android release signing and CI. Everything below was changed in this project; the **Test** column says what was really
executed. Nothing here claims the app is "fully secure".

## E. Test results (read this first)

| Area | Status | Detail |
|---|---|---|
| SQL migrations (schema + patches 2, 3, 4, patch 4 run twice) on PostgreSQL 16.15 | **PASSED, executed** | applied cleanly, re-runnable |
| SQL security / RLS / RPC / game-engine / sync tests (`supabase/tests/10_security_tests.sql`) | **PASSED, executed: 130 checks** | see `supabase/tests/LAST_RUN.txt` |
| Real concurrency tests (parallel psql sessions): 8 identical simultaneous moves, simultaneous resignations, simultaneous quick-match | **PASSED, executed** | exactly 1 move accepted; ratings applied once; 10/10 pairs matched |
| Workflow YAML syntax | **PASSED, executed** (parsed) | the workflow itself has NOT run on GitHub |
| Dart unit tests (`test/chess_game_test.dart`) | **NOT executed** | no Flutter/Dart SDK in the authoring environment; they run in CI (`flutter test`) |
| `flutter analyze` / compile of the changed Dart code | **NOT executed** | same reason; only bracket balance was checked. Expect to fix small compile errors on the first CI run |
| Edge function (`index.ts`, `logic.ts`) and `logic_test.ts` | **NOT executed** | Deno/npm unavailable (no network to registries). The database half it calls IS tested |
| Two real devices, Google sign-in, Realtime, reconnection, Play signing | **Requires production verification** | |
| Sync tests with two devices / offline | SQL side **executed** (idempotency, duplicate events, two-device sum, stale settings); Dart side **NOT executed** | |

## A. Fixed vulnerabilities

1. **Non-atomic moves / race conditions** (`supabase/functions/game-action/index.ts`). Two simultaneous requests could both pass the
   turn check; the move row was inserted before the conflict check; finishing a game had no compare-and-swap.
   Risk: duplicate or lost moves, corrupted history. Fix: all state changes go through `server_apply_move` /
   `server_game_action` (patch 4): one transaction, `SELECT ... FOR UPDATE` on the game row, membership, active status, turn,
   stale-position (`expected_ply` + `expected_fen`) checks, move insert + game update + finish in the same transaction.
   Test: executed (stale, duplicate, wrong-turn, non-member, finished game, 8-way parallel race).
2. **Client/edge-trusted clocks.** Clock math ran in the edge function with `Date.now()` and a non-locked read. Fix: clocks are computed in
   the database with `clock_timestamp()` under the row lock; clock does not run before white's first move; increment added after
   each move except white's first; a move arriving after the flag fell is rejected and the game ends on time; timeout claims are
   decided by the server. Test: executed (first move, increment, late move, claim, double claim).
3. **Draw by repetition never detected.** The function built `new Chess(g.fen)`, which has no history. Fix: the game is rebuilt by
   replaying the stored UCI list (`logic.ts`), so threefold/fifty-move see the full history. Test: `logic_test.ts` written, **not executed**.
4. **Racy rating updates.** Read-modify-write on `profiles` from the edge function. Fix: `_finish_locked` updates both profiles in
   one transaction, locked in id order, idempotent (finished game returns unchanged). Games with fewer than 2 plies never change
   ratings (no farming by instant resignation). Test: executed (once only, after draw/timeout/mate/resign, plus parallel resign).
5. **Weak, brute-forceable room codes** (5 hex chars = 20 bits, unlimited joins). Fix: 8 chars from a 32-symbol alphabet (40 bits)
   from the database CSPRNG, rooms expire after 30 minutes, 10 wrong codes per 10 minutes then lock-out; failed guesses return NULL
   (not an exception) so they are really counted; an outsider cannot read private rooms. Test: executed.
6. **No RPC input validation** (`quick_match`, `create_room`, `send_challenge`). Negative/huge time controls accepted. Fix: server-side
   limits (1-180 min, 0-60 s increment) + table CHECK constraints; self/unknown/null players rejected; duplicate pending challenges
   rejected; challenges expire after 10 minutes; per-user rate limits. Test: executed.
7. **Quick-match race.** Two simultaneous searchers could each create a waiting game and never meet; re-polling created duplicates.
   Fix: per-time-control advisory lock; re-poll returns the same waiting game. Test: executed (10 parallel rounds).
8. **Missing integrity constraints.** Added unique `(game_id, ply)`, foreign key on `game_moves.player_id`, CHECKs (turn, result,
   clocks, distinct players, code format, username length, rating bounds, https-only avatar URL), indexes. Added as NOT VALID then
   validated when existing data allows, so production rows can never block the migration. Test: executed.
9. **Privilege defence in depth.** `revoke insert/update/delete` on games, game_moves, challenges and progress ledgers from clients; `anon`
   has no table access; engine functions are `service_role` only; every SECURITY DEFINER function pins `search_path = public, pg_temp`;
   leaderboard is `security_invoker`. Test: executed (catalog checks + permission-denied checks).
10. **Cloud sync lost increments** (`lib/providers/app_state.dart`): stats were max-merged, so two devices lost games; whole-row overwrite
    let stale data win. Fix: `sync_progress` RPC: row lock, idempotent event ledger (`progress_games`, `progress_puzzles`, unique per id),
    settings last-writer-wins by timestamp, history merged by id, one-time baseline migration of old local data, bounds on every event.
    The app queues events (persisted) and adopts the server's totals. Test: SQL side executed; Dart side not executed.
11. **Engine/review pipeline** (`engine_service.dart`, `analysis_service.dart`): a timed-out search left a late `bestmove` that was taken as the
    answer to the next request (wrong position) -> `isready/readyok` drain before and after every job; timeouts now return *no result*
    instead of partial lines; analysis is retried once after an engine restart and otherwise fails with a retry button (no move is ever
    classified from missing data); crashed engine is detected and re-created; FENs are validated before reaching the engine (blocks UCI
    command injection through a newline); `lowerbound/upperbound` score lines ignored; illegal move in a record or >600 plies refuses to
    analyse instead of analysing a truncated game. Classification thresholds were NOT changed. Test: guards covered by Dart tests, **not executed**.
12. **Edge function hardening:** method/body/UUID/UCI validation, generic 500 text (no internal error strings returned), service-role key
    only read server-side.
13. **Flutter app:** avatar images only fetched over https; username sanitised (control/bidi characters, length); room-code field
    restricted to letters/digits; no tokens/PII in logs (debug-only logging); join failure message; premove/animation features do not touch the network.
14. **CI/release:** see section F and `.github/workflows/build-apk.yml`: no `continue-on-error` on analysis/tests; least-privilege
    `contents: read`; repository secret scan; production build fails when any secret is missing; `REQUIRE_RELEASE_SIGNING`; APK signature
    verification with `apksigner` and refusal of the debug certificate; separate explicit `allow_debug_signing` test-build switch.

## B. Remaining risks / manual actions

- **Apply patch 4 and redeploy the edge function** (Supabase dashboard). The new function requires the new SQL; deploy SQL first.
- **Signing key.** A release keystore and its password were generated *inside this chat session earlier* and delivered to you in a zip.
  Treat that key as exposed to this conversation. If you have not published to Google Play yet, simply generate your own key on your PC
  with `tools/make_keystore.sh`, replace the four GitHub secrets, and update the SHA-1 in the Google Cloud Android OAuth client.
  If an app signed with it IS already on Google Play: with Play App Signing, contact Play Console > Setup > App signing > "Request upload key reset"
  (Google replaces the *upload* key; users' installed apps keep updating). Without Play App Signing the key cannot be replaced for existing installs.
  Do not delete the old secrets until the new build is verified.
- **Supabase Auth settings** (cannot be set from code): email confirmation, password length/leak protection, rate limits, CAPTCHA, anonymous sign-ins (guests have the `authenticated` DB role by design; they can play and challenge but are not distinguishable by RLS).
- **Offline results are self-reported.** Games vs the on-device AI and puzzles are played offline, so the server cannot verify them; it only bounds each event
  (rating delta ±32, puzzle points ≤100, 200 events per call, rate limit). Online (human) games are fully server-authoritative. Keep the two ratings separate in your UI/marketing.
- **Secure token storage.** supabase_flutter stores the session in app-private SharedPreferences. I did NOT add `flutter_secure_storage`
  (an extra native dependency I cannot compile or test here, and it must not break your build). Android app-private storage is sandboxed; add
  it later if you need protection on rooted devices.
- **Old app versions** still write `user_progress` directly (kept for compatibility); remove those RLS policies once everyone updated.
- **Disconnects:** unplayed active games and stale lobbies expire; a running game whose flag fell stays open until a player claims the timeout (the app does it automatically). No automatic forfeiture timer without pg_cron.
- **Clock display** uses a local timestamp taken when each server update arrives (latency-sized error); the server clock is authoritative for all decisions.
- **Pin actions to SHAs:** workflow uses major tags (`@v4`, `@v5`, `@v2`) because SHAs could not be looked up offline. Resolve with
  `gh api repos/actions/checkout/commits/v4 --jq .sha` for each action and replace the tag.
- **Formatting** is auto-applied (`dart format`) rather than a failing gate, so that unformatted generated code cannot block every release.
  `flutter analyze` fails on errors and warnings; "info" hints are reported only. Tighten to `--fatal-infos` once the project is clean.
- **Realtime** payloads follow the `games` select policy; verify with two accounts in production.

## C. Files

New: `supabase/patch_4_security.sql`, `supabase/tests/{00_supabase_stub.sql,10_security_tests.sql,run_sql_tests.sh,LAST_RUN.txt}`,
`supabase/functions/game-action/{logic.ts,logic_test.ts}`, `test/chess_game_test.dart`, `SECURITY_AUDIT.md`.
Modified: `supabase/functions/game-action/index.ts`, `.github/workflows/build-apk.yml`, `.gitignore`, `tools/patch_android.py`, `tools/make_keystore.sh`,
`SETUP_SUPABASE.md`, `lib/providers/app_state.dart`, `lib/providers/game_controller.dart`, `lib/services/storage_service/storage_service.dart`,
`lib/services/multiplayer_service/supabase_service.dart`, `lib/services/stockfish_service/{engine_service,analysis_service}.dart`,
`lib/screens/multiplayer/{online_hub_screen,online_game_screen}.dart`, `lib/screens/review/review_screen.dart`, `lib/widgets/cards/common.dart`,
`lib/widgets/chessboard/chess_board.dart`, `lib/services/chess_service/chess_game.dart`, `lib/models/models.dart`, `lib/screens/settings/settings_screen.dart`, `lib/screens/game/game_screen.dart`.

## D. Migration

The complete migration is `supabase/patch_4_security.sql`. Apply: back up (Dashboard > Database > Backups), open SQL Editor,
paste the whole file, run once (re-running is safe), then redeploy the function and ship the app update. Constraints that old rows
violate stay `NOT VALID` and a NOTICE names them; fix those rows at leisure, then `ALTER TABLE ... VALIDATE CONSTRAINT`.

## F. Release readiness

Not release-ready until: (1) patch 4 applied and the function redeployed, (2) the first CI run is green (compile errors in the unexecuted Dart code are likely to
need one fix round), (3) two-device online testing (moves, clocks, reconnect, resign, draw, timeout) on the production project, (4) the signing key question above is resolved.
After that the multiplayer backend is considerably safer, but this is a hardened baseline, not a certification.

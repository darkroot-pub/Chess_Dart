# Supabase setup (first time) — about 10 minutes

Online play is optional. Without these steps the app still works fully offline (AI, pass & play, puzzles, learn, analysis).

## 1. Create the project
1. Go to https://supabase.com → **Sign in with GitHub** → **New project**.
2. Name: `darkchess`. Set a database password (save it). Pick the region closest to you. Create.
3. Wait ~2 minutes until the project is ready.

## 2. Create the tables and security rules
1. Left menu → **SQL Editor** → **New query**.
2. Paste the whole content of `supabase/schema.sql` → **Run**. It should say "Success".
   This creates: `profiles`, `games`, `game_moves`, `friendships`, a `leaderboard` view, Row Level Security
   policies (clients can only READ games; they cannot write moves directly), and the matchmaking functions.

## 3. Turn on sign-in
Authentication → **Providers**:
- **Email** is on by default. For quick testing, in Authentication → Sign In / Providers → Email turn **off "Confirm email"**
  (otherwise you must click the email link before signing in).
- Authentication → Sign In / Providers → turn **on "Allow anonymous sign-ins"** (used by "Continue as guest").

## 4. Deploy the move-validation function (this is what stops cheating)
Needs the Supabase CLI on your PC (Node installed): 
```
npm i -g supabase
supabase login
supabase link --project-ref YOUR_PROJECT_REF      # the ref is in Project Settings > General
supabase functions deploy game-action
```
The function already receives `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` automatically.
The service-role key is used ONLY inside this function on Supabase's servers and never goes into the app.

(No PC? In the dashboard open **Edge Functions → Deploy a new function → Via Editor**, name it `game-action`,
paste `supabase/functions/game-action/index.ts`, and deploy.)

### If you already ran an older schema.sql
Run `supabase/patch_2_fix_room_and_progress.sql` once in the SQL Editor. It fixes "Create private room" (error
`gen_random_bytes does not exist`) and adds the `user_progress` table used for cloud save.

### If moves / resign / draw show "Requested function was not found" (404)
The `game-action` Edge Function is not deployed. In Supabase: **Edge Functions → Deploy a new function → Via Editor**,
name it exactly `game-action`, paste all of `supabase/functions/game-action/index.ts`, click **Deploy**.
Keep "Verify JWT" ON. No secrets are needed; Supabase injects them.

### Friends, challenges and profile photos
Run `supabase/patch_3_social.sql` once in the SQL Editor. It adds profile photos (auto-filled from Google), the
`challenges` table and the `send_challenge` / `respond_challenge` / `cancel_challenge` functions.
(New installs: `schema.sql` already contains everything; the patch files are only for databases created earlier.)

## 5. Copy the two keys the app needs
Project Settings → **API**:
- **Project URL**  → `SUPABASE_URL`
- **anon public** key → `SUPABASE_ANON_KEY`  (safe to ship in the app; RLS protects the data)
NEVER use the `service_role` key in the app or in GitHub secrets for the app.

## 6. Give them to the build
GitHub repo → Settings → Secrets and variables → Actions → add `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
For local runs: `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`

## 7. Test
Install the APK on two phones (or phone + emulator), sign up two accounts, press **Quick Match** on both
(same time control). Or create a private room on one and join by code on the other.

Known limits: clocks use the phone clock for display only; the server decides timeouts. "Online players" shows
players active in the last 3 minutes; there is no direct challenge/invite yet (use private room codes).


## Google sign-in (native account picker, no browser)
1. Google Cloud Console → APIs & Services → Credentials → create two OAuth clients:
   - **Web application** → copy its Client ID and Secret. Authorized redirect URI: `https://<PROJECT-REF>.supabase.co/auth/v1/callback`.
   - **Android** → package name = your app id, plus the **SHA-1** of the keystore that signs the APK (release keystore *and* debug if you test with it).
2. Supabase → Authentication → Providers → **Google**: enable, paste the Web Client ID + Secret. (Optionally tick "Skip nonce checks".)
3. Add a GitHub secret `GOOGLE_WEB_CLIENT_ID` (the **Web** client ID) — it is passed with `--dart-define` at build time.
   Local run: `flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=... --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`


## Cloud save
When a player is signed in (email, Google or guest) their puzzles solved, puzzle points, stats, achievements, settings
and game history are saved to the `user_progress` table and restored on any device after login (merged with local data).

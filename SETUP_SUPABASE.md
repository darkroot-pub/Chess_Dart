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


## Google sign-in
1. Google Cloud Console → APIs & Services → Credentials → Create **OAuth client ID** → type **Web application**.
   Authorized redirect URI: `https://<YOUR-PROJECT-REF>.supabase.co/auth/v1/callback`.
2. Supabase → Authentication → Sign In / Providers → **Google**: enable, paste Client ID and Secret, save.
3. Supabase → Authentication → URL Configuration → **Redirect URLs**: add `io.darkchess.app://login-callback/`.
4. Rebuild (the CI runs `tools/patch_android.py`, which registers the `io.darkchess.app://login-callback` deep link).

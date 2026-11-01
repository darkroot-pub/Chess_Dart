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

-- ============================================================
-- SpeakGenie Supabase Schema
-- Run this whole file in: Supabase Dashboard -> SQL Editor -> New Query
-- ============================================================

-- 1. PROFILES (one row per signed-up user, keyed to Supabase Auth)
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Learner',
  avatar text default '🧒',
  xp integer default 0,
  coins integer default 0,
  streak integer default 0,
  fc_due integer default 10,
  fc_rev integer default 0,
  fc_mast integer default 0,
  bee_score integer default 0,
  pron_attempts integer default 0,
  fc_state jsonb default '{}'::jsonb, -- per-card SM-2 spaced-repetition schedule: {word: {interval, ease, reps, dueDay}}
  last_play_date date,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 2. DAILY QUIZ RESULTS (one row per day per user)
create table if not exists daily_quiz_results (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id) on delete cascade not null,
  quiz_date date not null,
  score integer not null,
  correct_count integer default 0,
  total_questions integer default 10,
  xp_earned integer default 0,
  created_at timestamptz default now(),
  unique(profile_id, quiz_date)
);

-- 3. COMIC RESULTS (one row per comic completion; a comic can be replayed)
create table if not exists comic_results (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id) on delete cascade not null,
  comic_title text not null,
  completed_date date not null,
  xp_earned integer default 0,
  created_at timestamptz default now()
);

-- 4. DAILY BONUS HISTORY (one row per claimed daily reward, tracks streak day)
create table if not exists daily_bonus_history (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id) on delete cascade not null,
  claim_date date not null,
  streak_day integer not null,
  xp_earned integer default 0,
  coins_earned integer default 0,
  -- which learn activity this bonus should deep-link to, e.g. 'quiz', 'wordhunt', 'spelling', 'comics'
  linked_activity text,
  linked_activity_label text,
  created_at timestamptz default now(),
  unique(profile_id, claim_date)
);

-- ============================================================
-- ROW LEVEL SECURITY: every user can only ever read/write their own rows
-- ============================================================
alter table profiles enable row level security;
alter table daily_quiz_results enable row level security;
alter table comic_results enable row level security;
alter table daily_bonus_history enable row level security;

create policy "profiles: read own" on profiles for select using (auth.uid() = id);
create policy "profiles: update own" on profiles for update using (auth.uid() = id);
create policy "profiles: insert own" on profiles for insert with check (auth.uid() = id);

create policy "quiz: read own" on daily_quiz_results for select using (auth.uid() = profile_id);
create policy "quiz: insert own" on daily_quiz_results for insert with check (auth.uid() = profile_id);
create policy "quiz: update own" on daily_quiz_results for update using (auth.uid() = profile_id);

create policy "comics: read own" on comic_results for select using (auth.uid() = profile_id);
create policy "comics: insert own" on comic_results for insert with check (auth.uid() = profile_id);

create policy "bonus: read own" on daily_bonus_history for select using (auth.uid() = profile_id);
create policy "bonus: insert own" on daily_bonus_history for insert with check (auth.uid() = profile_id);
create policy "bonus: update own" on daily_bonus_history for update using (auth.uid() = profile_id);

-- Auto-create a profile row the moment someone signs up via Supabase Auth
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name','Learner'));
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Helpful indexes for fast history lookups
create index if not exists idx_quiz_profile_date on daily_quiz_results(profile_id, quiz_date desc);
create index if not exists idx_comic_profile_date on comic_results(profile_id, completed_date desc);
create index if not exists idx_bonus_profile_date on daily_bonus_history(profile_id, claim_date desc);

-- ============================================================
-- MIGRATION: if you already ran this file once before and are just
-- adding the new columns below, run ONLY this block (safe to re-run,
-- it won't error if the columns already exist):
-- ============================================================
alter table profiles add column if not exists pron_attempts integer default 0;
alter table profiles add column if not exists fc_state jsonb default '{}'::jsonb;

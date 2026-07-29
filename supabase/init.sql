-- SYNC — Supabase schema
-- Run this in your Supabase SQL editor. Then enable Realtime on
-- `alarms`, `pairings`, and `profiles`.

create extension if not exists "uuid-ossp";

-- =========================================================================
-- Profiles
-- =========================================================================
create table if not exists profiles (
  id uuid references auth.users on delete cascade primary key,
  username text unique not null,
  avatar_url text,
  fcm_token text,
  timezone text default 'UTC',
  sleep_status text check (sleep_status in ('awake', 'asleep')) default 'awake',
  battery_percent int default 100,
  -- fcm_token was removed when we dropped Firebase; left out of v1
  -- schema to keep the profile row minimal. Add back if/when push
  -- is reintroduced via a different provider.
  created_at timestamptz default now()
);

-- =========================================================================
-- Pairings
-- =========================================================================
create table if not exists pairings (
  id uuid default uuid_generate_v4() primary key,
  user_a uuid references profiles(id) on delete cascade not null,
  -- Nullable so we can store an invite without a partner yet.
  user_b uuid references profiles(id) on delete cascade,
  status text check (status in ('pending', 'accepted', 'blocked')) default 'pending',
  invite_code text unique,
  accepted_at timestamptz,
  created_at timestamptz default now()
);

-- =========================================================================
-- Alarms
-- =========================================================================
create table if not exists alarms (
  id uuid default uuid_generate_v4() primary key,
  owner_id uuid references profiles(id) on delete cascade not null,
  created_by uuid references profiles(id) on delete cascade not null,
  label text not null default 'Alarm',
  message text default 'Wake up!',
  hour int not null check (hour between 0 and 23),
  minute int not null check (minute between 0 and 59),
  days_of_week int[] default '{}',
  is_active boolean default true,
  vibrate boolean default true,
  sound_name text default 'default',
  snooze_minutes int default 5,
  created_at timestamptz default now()
);

create index if not exists alarms_owner_id_idx on alarms (owner_id);
create index if not exists alarms_created_by_idx on alarms (created_by);

-- =========================================================================
-- Nudges (in-app realtime; replaces the old FCM push completely)
-- =========================================================================
create table if not exists nudges (
  id uuid default uuid_generate_v4() primary key,
  from_user uuid references profiles(id) on delete cascade not null,
  to_user   uuid references profiles(id) on delete cascade not null,
  created_at timestamptz default now(),
  read_at    timestamptz
);
create index if not exists nudges_to_user_created_idx on nudges (to_user, created_at desc);

-- =========================================================================
-- Alarm Logs
-- =========================================================================
create table if not exists alarm_logs (
  id uuid default uuid_generate_v4() primary key,
  alarm_id uuid references alarms(id) on delete cascade,
  action text check (action in ('fired', 'snoozed', 'dismissed')),
  reaction text,
  acted_by uuid references profiles(id),
  created_at timestamptz default now()
);

create index if not exists alarm_logs_alarm_idx on alarm_logs (alarm_id);
create index if not exists alarm_logs_created_at_idx on alarm_logs (created_at desc);

-- =========================================================================
-- Row Level Security
-- =========================================================================
alter table profiles    enable row level security;
alter table pairings    enable row level security;
alter table alarms      enable row level security;
alter table alarm_logs  enable row level security;
alter table nudges      enable row level security;
-- Nudges: sender and recipient can read; only the sender can insert
-- (and the target must be the other half of an accepted pairing);
-- only the recipient can flip read_at.
drop policy if exists nudges_select on nudges;
drop policy if exists nudges_insert on nudges;
drop policy if exists nudges_update on nudges;
create policy nudges_select on nudges for select using (
  from_user = auth.uid() or to_user = auth.uid()
);
create policy nudges_insert on nudges for insert with check (
  from_user = auth.uid()
  and exists (
    select 1 from pairings p
    where p.status = 'accepted'
      and ((p.user_a = auth.uid() and p.user_b = to_user)
        or (p.user_b = auth.uid() and p.user_a = to_user))
  )
);
create policy nudges_update on nudges for update using (
  to_user = auth.uid()
) with check (
  to_user = auth.uid()
);


-- Profiles: anyone authenticated can read, only owner can write.
drop policy if exists profiles_select on profiles;
drop policy if exists profiles_insert on profiles;
drop policy if exists profiles_update on profiles;
create policy profiles_select on profiles for select using (true);
create policy profiles_insert on profiles for insert with check (auth.uid() = id);
create policy profiles_update on profiles for update using (auth.uid() = id);

-- Pairings: any of the two participants can read/insert/update.
drop policy if exists pairings_select on pairings;
drop policy if exists pairings_insert on pairings;
drop policy if exists pairings_update on pairings;
drop policy if exists pairings_delete on pairings;
create policy pairings_select on pairings for select using (
  user_a = auth.uid() or user_b = auth.uid()
);
-- Only the inviter creates a pending invite row.
create policy pairings_insert on pairings for insert with check (
  user_a = auth.uid()
);
create policy pairings_update on pairings for update using (
  user_a = auth.uid() or user_b = auth.uid()
);
create policy pairings_delete on pairings for delete using (
  user_a = auth.uid() or user_b = auth.uid()
);

-- Alarms: visible to owner and creator.
drop policy if exists alarms_select on alarms;
drop policy if exists alarms_insert on alarms;
drop policy if exists alarms_update on alarms;
drop policy if exists alarms_delete on alarms;
create policy alarms_select on alarms for select using (
  owner_id = auth.uid() or created_by = auth.uid()
);
create policy alarms_insert on alarms for insert with check (
  created_by = auth.uid()
  and exists (
    select 1 from pairings p
    where ((p.user_a = auth.uid() and p.user_b = owner_id)
        or (p.user_b = auth.uid() and p.user_a = owner_id))
      and p.status = 'accepted'
  )
);
create policy alarms_update on alarms for update using (
  owner_id = auth.uid() or created_by = auth.uid()
);
create policy alarms_delete on alarms for delete using (
  owner_id = auth.uid() or created_by = auth.uid()
);

-- Alarm logs: visible to the alarm’s owner and creator.
drop policy if exists alarm_logs_select on alarm_logs;
drop policy if exists alarm_logs_insert on alarm_logs;
drop policy if exists alarm_logs_update on alarm_logs;
create policy alarm_logs_select on alarm_logs for select using (
  exists (
    select 1 from alarms
    where alarms.id = alarm_logs.alarm_id
      and (alarms.owner_id = auth.uid() or alarms.created_by = auth.uid())
  )
);
create policy alarm_logs_insert on alarm_logs for insert with check (
  exists (
    select 1 from alarms
    where alarms.id = alarm_logs.alarm_id
      and (alarms.owner_id = auth.uid() or alarms.created_by = auth.uid())
  )
);
create policy alarm_logs_update on alarm_logs for update using (
  exists (
    select 1 from alarms
    where alarms.id = alarm_logs.alarm_id
      and (alarms.owner_id = auth.uid() or alarms.created_by = auth.uid())
  )
);

-- =========================================================================
-- Helpers
-- =========================================================================
create or replace function public.user_has_active_pairing(uid uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from pairings
    where (user_a = uid or user_b = uid) and status = 'accepted'
  );
$$;

-- Cryptographically random 6-digit code (100000..999999).
create or replace function public.generate_invite_code()
returns text
language sql
volatile
as $$
  select lpad((floor(random() * 900000) + 100000)::text, 6, '0');
$$;

-- =========================================================================
-- Invite RPC — creates a pending pairing row with a unique invite_code.
-- Re-tapping "Generate" deletes the prior pending invite for the inviter
-- so the unique constraint doesn't blow up (issue 7).
-- =========================================================================
create or replace function public.create_pairing_invite(p_inviter uuid)
returns pairings
language plpgsql
security definer
as $$
declare
  v_pairing pairings;
  v_code text;
  v_attempts int := 0;
begin
  if public.user_has_active_pairing(p_inviter) then
    raise exception 'User already has an active pairing.';
  end if;

  -- Drop any earlier pending invite from this inviter.
  delete from pairings
    where user_a = p_inviter
      and status = 'pending'
      and user_b is null;

  loop
    v_code := public.generate_invite_code();
    v_attempts := v_attempts + 1;
    begin
      insert into pairings (user_a, user_b, status, invite_code)
        values (p_inviter, null, 'pending', v_code)
        returning * into v_pairing;
      exit;
    exception when unique_violation then
      if v_attempts >= 8 then raise exception 'Could not generate unique code.'; end if;
    end;
  end loop;

  return v_pairing;
end;
$$;

-- Accept an invite — sets user_b and status='accepted' atomically.
create or replace function public.claim_pairing_by_code(
  p_code text,
  p_user_id uuid
)
returns pairings
language plpgsql
security definer
as $$
declare
  v_pairing pairings;
begin
  if public.user_has_active_pairing(p_user_id) then
    raise exception 'User already paired.';
  end if;

  select * into v_pairing
  from pairings
  where status = 'pending'
    and invite_code = p_code
    and user_a <> p_user_id
  limit 1
  for update;

  if not found then
    raise exception 'Invalid pairing code.';
  end if;

  update pairings
    set user_b = p_user_id,
        status = 'accepted',
        accepted_at = now()
    where id = v_pairing.id
    returning * into v_pairing;

  return v_pairing;
end;
$$;

-- =========================================================================
-- Trigger: auto-create profile row when a user signs up.
-- =========================================================================
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (
    id,
    username,
    avatar_url,
    timezone
  )
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'user_name',
      new.raw_user_meta_data->>'preferred_username',
      'user_' || substr(new.id::text, 1, 6)
    ),
    new.raw_user_meta_data->>'avatar_url',
    coalesce(new.raw_user_meta_data->>'timezone', 'UTC')
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- =========================================================================
-- Realtime
-- =========================================================================
alter publication supabase_realtime add table public.profiles;
alter publication supabase_realtime add table public.pairings;
alter publication supabase_realtime add table public.alarms;
alter publication supabase_realtime add table public.alarm_logs;
alter publication supabase_realtime add table public.nudges;

-- VocaLatinum: erste Supabase-Datenbankgrundlage
-- Diese Migration ist vorbereitet, aber noch nicht auf ein Supabase-Projekt angewendet.
-- Client-Zugriff auf Freundschaften und Gruppen bleibt absichtlich gesperrt,
-- bis dafür geprüfte RPC-Funktionen und pgTAP-RLS-Tests vorliegen.

begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'Lernende Person'
    check (char_length(display_name) between 2 and 24),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.profile_sharing (
  user_id uuid primary key references auth.users (id) on delete cascade,
  share_level boolean not null default false,
  share_xp boolean not null default false,
  share_badges boolean not null default false,
  share_weekly_stats boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friend_requests_no_self check (sender_id <> recipient_id)
);

create unique index if not exists friend_requests_one_pending_direction
  on public.friend_requests (sender_id, recipient_id)
  where status = 'pending';
create index if not exists friend_requests_recipient_idx
  on public.friend_requests (recipient_id, created_at desc);

create table if not exists public.friendships (
  user_a uuid not null references auth.users (id) on delete cascade,
  user_b uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  constraint friendships_canonical_order check (user_a < user_b)
);

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 32),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  archived_at timestamptz
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member'
    check (role in ('leader', 'deputy_leader', 'member')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (group_id, user_id)
);
create unique index if not exists group_members_one_active_leader
  on public.group_members (group_id)
  where role = 'leader' and left_at is null;
create unique index if not exists group_members_one_active_deputy
  on public.group_members (group_id)
  where role = 'deputy_leader' and left_at is null;
create index if not exists group_members_user_idx
  on public.group_members (user_id, group_id)
  where left_at is null;

create table if not exists public.group_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  inviter_id uuid not null references auth.users (id) on delete cascade,
  invitee_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'cancelled', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  constraint group_invites_no_self check (inviter_id <> invitee_id)
);
create unique index if not exists group_invites_one_pending
  on public.group_invites (group_id, invitee_id)
  where status = 'pending';

create table if not exists public.group_settings (
  group_id uuid primary key references public.groups (id) on delete cascade,
  chat_retention_days integer
    check (chat_retention_days is null or chat_retention_days between 1 and 365),
  updated_at timestamptz not null default now()
);

-- RLS ist auf jeder Tabelle aktiv. Die Beziehungs- und Gruppentabellen
-- erhalten absichtlich noch keine Client-Grants oder Policies.
alter table public.profiles enable row level security;
alter table public.profile_sharing enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_invites enable row level security;
alter table public.group_settings enable row level security;

alter table public.profiles force row level security;
alter table public.profile_sharing force row level security;
alter table public.friend_requests force row level security;
alter table public.friendships force row level security;
alter table public.groups force row level security;
alter table public.group_members force row level security;
alter table public.group_invites force row level security;
alter table public.group_settings force row level security;

-- Explizite Minimalrechte statt impliziter Standardfreigaben.
revoke all on table
  public.profiles,
  public.profile_sharing,
  public.friend_requests,
  public.friendships,
  public.groups,
  public.group_members,
  public.group_invites,
  public.group_settings
from public, anon, authenticated;

grant select on table public.profiles, public.profile_sharing to authenticated;
grant update (display_name) on table public.profiles to authenticated;
grant update (
  share_level, share_xp, share_badges, share_weekly_stats
) on table public.profile_sharing to authenticated;

create policy "profile_owner_reads_own_profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "profile_owner_updates_own_profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "profile_owner_reads_own_sharing"
  on public.profile_sharing for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "profile_owner_updates_own_sharing"
  on public.profile_sharing for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

create trigger profile_sharing_set_updated_at
  before update on public.profile_sharing
  for each row execute function private.set_updated_at();

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.profile_sharing (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

revoke all on function private.set_updated_at() from public, anon, authenticated;
revoke all on function private.handle_new_auth_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created_vocalatinum on auth.users;
create trigger on_auth_user_created_vocalatinum
  after insert on auth.users
  for each row execute function private.handle_new_auth_user();

commit;

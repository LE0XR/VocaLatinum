-- VocaLatinum: gestufte Gruppenmoderation und dreitaegige Wiederaufnahme-Sperre
begin;

create table if not exists public.group_member_moderation_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  violation_category text not null check (char_length(btrim(violation_category)) between 2 and 80),
  action text not null check (action in ('reminder', 'warning', 'suspension')),
  created_at timestamptz not null default now()
);

create index if not exists group_member_moderation_events_history_idx
  on public.group_member_moderation_events (group_id, user_id, created_at);

create table if not exists public.group_member_suspensions (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  suspended_at timestamptz not null default now(),
  suspended_until timestamptz not null,
  reinstated_at timestamptz,
  reinstated_by uuid references auth.users (id) on delete set null,
  primary key (group_id, user_id),
  constraint group_member_suspension_period check (suspended_until > suspended_at)
);

alter table public.group_member_moderation_events enable row level security;
alter table public.group_member_moderation_events force row level security;
alter table public.group_member_suspensions enable row level security;
alter table public.group_member_suspensions force row level security;

revoke all on table public.group_member_moderation_events,
  public.group_member_suspensions from public, anon, authenticated;

-- Nur der vertrauenswuerdige Server darf einen bestaetigten Verstoss erfassen.
create or replace function public.record_group_moderation_violation(
  p_group_id uuid,
  p_user_id uuid,
  p_violation_category text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_action text;
begin
  if p_group_id is null or p_user_id is null
    or p_violation_category is null
    or char_length(btrim(p_violation_category)) < 2
    or char_length(btrim(p_violation_category)) > 80 then
    raise exception 'Valid group, member and violation category required' using errcode = 'P0001';
  end if;

  -- Sperrt die Mitgliedschaftszeile, damit gleichzeitige Meldungen
  -- fuer dieselbe Person nacheinander gezaehlt werden und keine Stufe ueberspringen.
  perform 1
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  where gm.group_id = p_group_id and gm.user_id = p_user_id
    and gm.left_at is null and gm.role = 'member'
    and g.archived_at is null
  for update of gm;

  if not found then
    raise exception 'Active ordinary group member required' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.group_member_suspensions s
    where s.group_id = p_group_id and s.user_id = p_user_id
      and s.reinstated_at is null and s.suspended_until > now()
  ) then
    raise exception 'Member is already suspended' using errcode = 'P0001';
  end if;

  select count(*)::integer + 1 into v_count
  from public.group_member_moderation_events e
  where e.group_id = p_group_id and e.user_id = p_user_id;

  v_action := case
    when v_count = 1 then 'reminder'
    when v_count = 2 then 'warning'
    else 'suspension'
  end;

  insert into public.group_member_moderation_events
    (group_id, user_id, violation_category, action)
  values (p_group_id, p_user_id, btrim(p_violation_category), v_action);

  if v_action = 'suspension' then
    insert into public.group_member_suspensions
      (group_id, user_id, suspended_at, suspended_until)
    values (p_group_id, p_user_id, now(), now() + interval '3 days')
    on conflict (group_id, user_id) do update
      set suspended_at = excluded.suspended_at,
          suspended_until = excluded.suspended_until,
          reinstated_at = null,
          reinstated_by = null;

    update public.group_members
    set left_at = now()
    where group_id = p_group_id and user_id = p_user_id and left_at is null;

    update public.group_invites
    set status = 'cancelled'
    where group_id = p_group_id and invitee_id = p_user_id and status = 'pending';
  end if;

  return v_action;
end;
$$;

revoke all on function public.record_group_moderation_violation(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.record_group_moderation_violation(uuid, uuid, text)
  to service_role;

-- Die Wiederaufnahme ist nach Ablauf der drei Tage nur durch die Gruppenleitung moeglich.
create or replace function public.reinstate_suspended_group_member(
  p_group_id uuid,
  p_member_friend_code text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_role text;
  v_member_id uuid;
  v_suspended_until timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if p_group_id is null or p_member_friend_code is null
    or p_member_friend_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception 'Invalid group or friend code' using errcode = 'P0001';
  end if;

  select gm.role into v_actor_role
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  where gm.group_id = p_group_id and gm.user_id = auth.uid()
    and gm.left_at is null and gm.role in ('leader', 'deputy_leader')
    and g.archived_at is null
  for update of gm;

  if v_actor_role is null then
    raise exception 'Group manager permission required' using errcode = 'P0001';
  end if;

  select p.user_id, s.suspended_until
    into v_member_id, v_suspended_until
  from public.profiles p
  join public.group_member_suspensions s
    on s.user_id = p.user_id and s.group_id = p_group_id
  where p.friend_code = p_member_friend_code
    and s.reinstated_at is null
  for update of s;

  if v_member_id is null then
    raise exception 'Active suspension not found' using errcode = 'P0001';
  end if;
  if v_suspended_until > now() then
    raise exception 'Three-day suspension has not expired' using errcode = 'P0001';
  end if;

  update public.group_members
  set left_at = null, joined_at = now(), role = 'member'
  where group_id = p_group_id and user_id = v_member_id and left_at is not null;

  if not found then
    raise exception 'Former group membership not found' using errcode = 'P0001';
  end if;

  update public.group_member_suspensions
  set reinstated_at = now(), reinstated_by = auth.uid()
  where group_id = p_group_id and user_id = v_member_id;

  return true;
end;
$$;

revoke all on function public.reinstate_suspended_group_member(uuid, text)
  from public, anon, authenticated;
grant execute on function public.reinstate_suspended_group_member(uuid, text)
  to authenticated;

-- Eine aktive Sperre blockiert auch die Annahme einer zuvor versandten Einladung.
create or replace function public.respond_to_group_invite(
  p_invite_id uuid,
  p_accept boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if p_invite_id is null or p_accept is null then
    raise exception 'Invitation and response are required' using errcode = 'P0001';
  end if;

  select i.group_id into v_group_id
  from public.group_invites i
  where i.id = p_invite_id
    and i.invitee_id = auth.uid()
    and i.status = 'pending'
    and (i.expires_at is null or i.expires_at > now())
  for update;

  if v_group_id is null then
    raise exception 'Invitation not found or expired' using errcode = 'P0001';
  end if;

  if p_accept and exists (
    select 1 from public.group_member_suspensions s
    where s.group_id = v_group_id and s.user_id = auth.uid()
      and s.reinstated_at is null
  ) then
    raise exception 'Group leader must reinstate this member' using errcode = 'P0001';
  end if;

  if p_accept then
    insert into public.group_members (group_id, user_id, role)
    values (v_group_id, auth.uid(), 'member')
    on conflict (group_id, user_id) do update
      set left_at = null, joined_at = now(), role = 'member'
      where public.group_members.left_at is not null;
    update public.group_invites set status = 'accepted' where id = p_invite_id;
  else
    update public.group_invites set status = 'rejected' where id = p_invite_id;
  end if;

  return true;
end;
$$;

revoke all on function public.respond_to_group_invite(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.respond_to_group_invite(uuid, boolean)
  to authenticated;

commit;

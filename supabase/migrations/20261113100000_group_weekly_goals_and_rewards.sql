-- VocaLatinum: woechentliche Gruppenziele und beitragsgebundene Belohnungen
-- XP-Ereignisse duerfen nur von einem vertrauenswuerdigen Serverdienst eingetragen werden.
begin;

create table public.group_weekly_goals (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  week_start date not null,
  week_end date not null,
  target_xp integer not null check (target_xp between 1 and 1000000),
  reward_type text not null check (reward_type in ('xp_boost_30m', 'badge_100xp', 'xp_bonus')),
  reward_amount integer,
  status text not null default 'active' check (status in ('active', 'awarded', 'missed')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  awarded_at timestamptz,
  constraint group_weekly_goals_valid_week check (week_end = week_start + 7),
  constraint group_weekly_goals_reward_amount check (
    (reward_type = 'xp_bonus' and reward_amount in (300, 400, 500, 600))
    or (reward_type = 'badge_100xp' and reward_amount = 100)
    or (reward_type = 'xp_boost_30m' and reward_amount is null)
  ),
  unique (group_id, week_start)
);

create table public.group_learning_events (
  event_id uuid primary key,
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  xp integer not null check (xp between 1 and 1000),
  created_at timestamptz not null default now()
);
create index group_learning_events_group_time_idx
  on public.group_learning_events(group_id, created_at);
create index group_learning_events_user_idx
  on public.group_learning_events(group_id, user_id, created_at);

create table public.group_goal_rewards (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null unique references public.group_weekly_goals(id) on delete cascade,
  reward_type text not null,
  reward_amount integer,
  awarded_at timestamptz not null default now()
);

create table public.user_group_reward_grants (
  id uuid primary key default gen_random_uuid(),
  reward_id uuid not null references public.group_goal_rewards(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reward_type text not null,
  reward_amount integer,
  created_at timestamptz not null default now(),
  unique (reward_id, user_id)
);

alter table public.group_weekly_goals enable row level security;
alter table public.group_learning_events enable row level security;
alter table public.group_goal_rewards enable row level security;
alter table public.user_group_reward_grants enable row level security;
alter table public.group_weekly_goals force row level security;
alter table public.group_learning_events force row level security;
alter table public.group_goal_rewards force row level security;
alter table public.user_group_reward_grants force row level security;

revoke all on table public.group_weekly_goals, public.group_learning_events,
  public.group_goal_rewards, public.user_group_reward_grants
from public, anon, authenticated;

create or replace function public.set_group_weekly_goal(
  p_group_id uuid,
  p_target_xp integer,
  p_reward_type text,
  p_reward_amount integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_goal_id uuid;
  v_week_start date := date_trunc('week', current_date)::date;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if p_group_id is null or p_target_xp is null or p_target_xp not between 1 and 1000000 then
    raise exception 'Weekly XP target must be between 1 and 1000000' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.group_id = p_group_id and gm.user_id = auth.uid()
      and gm.left_at is null and gm.role in ('leader', 'deputy_leader')
      and g.archived_at is null
  ) then
    raise exception 'Group manager permission required' using errcode = 'P0001';
  end if;
  if not (
    (p_reward_type = 'xp_boost_30m' and p_reward_amount is null)
    or (p_reward_type = 'badge_100xp' and p_reward_amount = 100)
    or (p_reward_type = 'xp_bonus' and p_reward_amount in (300, 400, 500, 600))
  ) then
    raise exception 'Invalid group reward selection' using errcode = 'P0001';
  end if;

  insert into public.group_weekly_goals
    (group_id, week_start, week_end, target_xp, reward_type, reward_amount, created_by)
  values
    (p_group_id, v_week_start, v_week_start + 7, p_target_xp,
     p_reward_type, p_reward_amount, auth.uid())
  on conflict (group_id, week_start) do update
    set target_xp = excluded.target_xp,
        reward_type = excluded.reward_type,
        reward_amount = excluded.reward_amount,
        created_by = excluded.created_by,
        status = 'active',
        awarded_at = null
  returning id into v_goal_id;
  return v_goal_id;
end;
$$;

create or replace function public.list_group_weekly_goal(p_group_id uuid)
returns table (
  goal_id uuid,
  week_start date,
  week_end date,
  target_xp integer,
  current_xp bigint,
  reward_type text,
  reward_amount integer,
  goal_status text,
  i_contributed boolean,
  my_reward_status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if p_group_id is null or not exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id = auth.uid() and gm.left_at is null
  ) then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;

  return query
  select g.id, g.week_start, g.week_end, g.target_xp,
    coalesce((select sum(e.xp)::bigint from public.group_learning_events e
      where e.group_id = g.group_id
        and (e.created_at at time zone 'UTC')::date >= g.week_start
        and (e.created_at at time zone 'UTC')::date < g.week_end), 0),
    g.reward_type, g.reward_amount, g.status,
    exists(select 1 from public.group_learning_events e
      where e.group_id = g.group_id and e.user_id = auth.uid()
        and (e.created_at at time zone 'UTC')::date >= g.week_start
        and (e.created_at at time zone 'UTC')::date < g.week_end),
    (select case when r.id is not null then 'earned' else null end
      from public.group_goal_rewards r
      join public.user_group_reward_grants ug on ug.reward_id = r.id
      where r.goal_id = g.id and ug.user_id = auth.uid())
  from public.group_weekly_goals g
  where g.group_id = p_group_id and g.week_start = date_trunc('week', current_date)::date;
end;
$$;

-- Ausschliesslich ein vertrauenswuerdiger Backend-Dienst darf bestaetigte Lern-XP melden.
create or replace function public.record_group_learning_event(
  p_event_id uuid,
  p_group_id uuid,
  p_user_id uuid,
  p_xp integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_event_id is null or p_group_id is null or p_user_id is null
    or p_xp is null or p_xp not between 1 and 1000 then
    raise exception 'Invalid learning event' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id = p_user_id and gm.left_at is null
  ) then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_weekly_goals g
    where g.group_id = p_group_id and g.status = 'active'
      and g.week_start = date_trunc('week', current_date)::date
  ) then
    raise exception 'No active weekly goal' using errcode = 'P0001';
  end if;
  insert into public.group_learning_events(event_id, group_id, user_id, xp)
  values (p_event_id, p_group_id, p_user_id, p_xp);
  return true;
exception when unique_violation then
  raise exception 'Learning event was already recorded' using errcode = 'P0001';
end;
$$;

-- Vergabe nur durch Backend-Dienst; jeder aktive Beitragende erhaelt genau eine Zuteilung.
create or replace function public.award_group_weekly_goal(p_group_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_goal public.group_weekly_goals%rowtype;
  v_reward_id uuid;
  v_count integer;
begin
  select * into v_goal
  from public.group_weekly_goals g
  where g.group_id = p_group_id
    and g.week_start = date_trunc('week', current_date)::date
    and g.status = 'active'
  for update;

  if not found then
    raise exception 'Active weekly goal not found' using errcode = 'P0001';
  end if;
  if (select coalesce(sum(e.xp), 0) from public.group_learning_events e
      where e.group_id = p_group_id
        and (e.created_at at time zone 'UTC')::date >= v_goal.week_start
        and (e.created_at at time zone 'UTC')::date < v_goal.week_end) < v_goal.target_xp then
    raise exception 'Weekly XP goal has not been reached' using errcode = 'P0001';
  end if;

  insert into public.group_goal_rewards(goal_id, reward_type, reward_amount)
  values (v_goal.id, v_goal.reward_type, v_goal.reward_amount)
  returning id into v_reward_id;

  insert into public.user_group_reward_grants(reward_id, user_id, reward_type, reward_amount)
  select v_reward_id, e.user_id, v_goal.reward_type, v_goal.reward_amount
  from public.group_learning_events e
  where e.group_id = p_group_id
    and (e.created_at at time zone 'UTC')::date >= v_goal.week_start
    and (e.created_at at time zone 'UTC')::date < v_goal.week_end
  group by e.user_id;

  get diagnostics v_count = row_count;
  update public.group_weekly_goals set status = 'awarded', awarded_at = now()
  where id = v_goal.id;
  return v_count;
exception when unique_violation then
  raise exception 'Weekly reward has already been awarded' using errcode = 'P0001';
end;
$$;

revoke all on function public.set_group_weekly_goal(uuid, integer, text, integer) from public, anon, authenticated;
revoke all on function public.list_group_weekly_goal(uuid) from public, anon, authenticated;
revoke all on function public.record_group_learning_event(uuid, uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.award_group_weekly_goal(uuid) from public, anon, authenticated;

grant execute on function public.set_group_weekly_goal(uuid, integer, text, integer) to authenticated;
grant execute on function public.list_group_weekly_goal(uuid) to authenticated;
grant execute on function public.record_group_learning_event(uuid, uuid, uuid, integer) to service_role;
grant execute on function public.award_group_weekly_goal(uuid) to service_role;

commit;

-- VocaLatinum: Gruppen-Umfragen und einstellbare Chat-Aufbewahrung
begin;

create table if not exists public.group_polls (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  creator_id uuid not null references auth.users (id) on delete cascade,
  question text not null check (char_length(btrim(question)) between 3 and 240),
  created_at timestamptz not null default now(),
  closes_at timestamptz,
  closed_at timestamptz
);

create table if not exists public.group_poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.group_polls (id) on delete cascade,
  option_text text not null check (char_length(btrim(option_text)) between 1 and 120),
  position smallint not null check (position between 1 and 6),
  unique (poll_id, position),
  unique (poll_id, id)
);

create table if not exists public.group_poll_votes (
  poll_id uuid not null,
  option_id uuid not null,
  voter_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (poll_id, voter_id),
  foreign key (poll_id, option_id)
    references public.group_poll_options (poll_id, id) on delete cascade
);

alter table public.group_polls enable row level security;
alter table public.group_polls force row level security;
alter table public.group_poll_options enable row level security;
alter table public.group_poll_options force row level security;
alter table public.group_poll_votes enable row level security;
alter table public.group_poll_votes force row level security;

revoke all on table public.group_polls, public.group_poll_options, public.group_poll_votes
from public, anon, authenticated;

create or replace function public.set_group_chat_retention(
  p_group_id uuid,
  p_days integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if p_days is not null and (p_days < 1 or p_days > 365) then
    raise exception 'Retention must be between 1 and 365 days, or null for no automatic expiry' using errcode = 'P0001';
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

  update public.group_settings
  set chat_retention_days = p_days, updated_at = now()
  where group_id = p_group_id;
  return found;
end;
$$;

create or replace function public.create_group_poll(
  p_group_id uuid,
  p_question text,
  p_options text[],
  p_closes_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_poll_id uuid;
  v_option text;
  v_position integer := 0;
  v_question text := btrim(coalesce(p_question, ''));
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if char_length(v_question) < 3 or char_length(v_question) > 240 then
    raise exception 'Question must contain 3 to 240 characters' using errcode = 'P0001';
  end if;
  if p_options is null or cardinality(p_options) < 2 or cardinality(p_options) > 6 then
    raise exception 'A poll needs 2 to 6 options' using errcode = 'P0001';
  end if;
  if p_closes_at is not null and p_closes_at <= now() then
    raise exception 'Poll closing time must be in the future' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.group_id = p_group_id and gm.user_id = auth.uid()
      and gm.left_at is null and g.archived_at is null
  ) then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from unnest(p_options) as opt
    where char_length(btrim(coalesce(opt, ''))) < 1
       or char_length(btrim(opt)) > 120
  ) or (select count(distinct lower(btrim(opt))) from unnest(p_options) as opt) <> cardinality(p_options) then
    raise exception 'Options must be unique and contain 1 to 120 characters' using errcode = 'P0001';
  end if;

  insert into public.group_polls (group_id, creator_id, question, closes_at)
  values (p_group_id, auth.uid(), v_question, p_closes_at)
  returning id into v_poll_id;

  foreach v_option in array p_options loop
    v_position := v_position + 1;
    insert into public.group_poll_options (poll_id, option_text, position)
    values (v_poll_id, btrim(v_option), v_position);
  end loop;
  return v_poll_id;
end;
$$;

create or replace function public.vote_group_poll(
  p_poll_id uuid,
  p_option_id uuid
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

  select p.group_id into v_group_id
  from public.group_polls p
  where p.id = p_poll_id
    and p.closed_at is null
    and (p.closes_at is null or p.closes_at > now())
    and exists (
      select 1 from public.group_poll_options o
      where o.poll_id = p.id and o.id = p_option_id
    );

  if v_group_id is null then
    raise exception 'Poll or option not found, or poll is closed' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_members gm
    where gm.group_id = v_group_id and gm.user_id = auth.uid() and gm.left_at is null
  ) then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;

  insert into public.group_poll_votes (poll_id, option_id, voter_id)
  values (p_poll_id, p_option_id, auth.uid())
  on conflict (poll_id, voter_id)
  do update set option_id = excluded.option_id, created_at = now();
  return true;
end;
$$;

create or replace function public.list_group_polls(p_group_id uuid)
returns table (
  poll_id uuid,
  question text,
  option_id uuid,
  option_text text,
  vote_count integer,
  my_vote boolean,
  closes_at timestamptz,
  closed_at timestamptz
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
  if not exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id = auth.uid() and gm.left_at is null
  ) then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;

  return query
    select p.id, p.question, o.id, o.option_text,
      (select count(*)::integer from public.group_poll_votes v where v.poll_id = p.id and v.option_id = o.id),
      exists (select 1 from public.group_poll_votes v where v.poll_id = p.id and v.voter_id = auth.uid() and v.option_id = o.id),
      p.closes_at, p.closed_at
    from public.group_polls p
    join public.group_poll_options o on o.poll_id = p.id
    where p.group_id = p_group_id
    order by p.created_at desc, o.position;
end;
$$;

create or replace function public.close_group_poll(p_poll_id uuid)
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
  select p.group_id into v_group_id
  from public.group_polls p
  where p.id = p_poll_id and p.closed_at is null
  for update;
  if v_group_id is null then
    raise exception 'Open poll not found' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_members gm
    where gm.group_id = v_group_id and gm.user_id = auth.uid()
      and gm.left_at is null and gm.role in ('leader', 'deputy_leader')
  ) then
    raise exception 'Group manager permission required' using errcode = 'P0001';
  end if;
  update public.group_polls set closed_at = now() where id = p_poll_id;
  return true;
end;
$$;

-- Nur der Datenbank-Administrator/Service-Job darf diese Bereinigung ausführen.
-- Die Funktion wird absichtlich nicht an authenticated oder anon vergeben.
create or replace function public.purge_expired_group_messages()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from public.group_messages m
  using public.group_settings s
  where s.group_id = m.group_id
    and s.chat_retention_days is not null
    and m.created_at < now() - make_interval(days => s.chat_retention_days);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.set_group_chat_retention(uuid, integer) from public, anon, authenticated;
revoke all on function public.create_group_poll(uuid, text, text[], timestamptz) from public, anon, authenticated;
revoke all on function public.vote_group_poll(uuid, uuid) from public, anon, authenticated;
revoke all on function public.list_group_polls(uuid) from public, anon, authenticated;
revoke all on function public.close_group_poll(uuid) from public, anon, authenticated;
revoke all on function public.purge_expired_group_messages() from public, anon, authenticated;

grant execute on function public.set_group_chat_retention(uuid, integer) to authenticated;
grant execute on function public.create_group_poll(uuid, text, text[], timestamptz) to authenticated;
grant execute on function public.vote_group_poll(uuid, uuid) to authenticated;
grant execute on function public.list_group_polls(uuid) to authenticated;
grant execute on function public.close_group_poll(uuid) to authenticated;

commit;

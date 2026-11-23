-- VocaLatinum: Zwei-Tage-Frist für fehlende Gruppen-Stellvertretung
-- Gruppen werden nach Ablauf archiviert, niemals physisch gelöscht.

begin;

alter table public.groups
  add column if not exists deputy_missing_since timestamptz,
  add column if not exists deputy_deadline_at timestamptz,
  add column if not exists archive_reason text;

alter table public.groups
  add constraint groups_archive_reason_valid
  check (archive_reason is null or archive_reason in ('deputy_missing_timeout'));

create or replace function private.track_missing_group_deputy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.role = 'deputy_leader'
    and old.left_at is null
    and new.left_at is not null
    and not exists (
      select 1 from public.group_members gm
      where gm.group_id = new.group_id
        and gm.role = 'deputy_leader'
        and gm.left_at is null
        and gm.user_id <> new.user_id
    ) then
    update public.groups
    set deputy_missing_since = now(),
        deputy_deadline_at = now() + interval '2 days'
    where id = new.group_id
      and archived_at is null
      and deputy_missing_since is null;
  end if;
  return new;
end;
$$;

drop trigger if exists group_deputy_departure_tracking on public.group_members;
create trigger group_deputy_departure_tracking
  after update of left_at on public.group_members
  for each row
  when (old.left_at is null and new.left_at is not null)
  execute function private.track_missing_group_deputy();

create or replace function public.change_group_deputy(
  p_group_id uuid,
  p_new_deputy_friend_code text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old_deputy_id uuid;
  v_new_deputy_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if p_group_id is null or p_new_deputy_friend_code is null
    or p_new_deputy_friend_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception 'Invalid group or friend code' using errcode = 'P0001';
  end if;

  perform 1
  from public.groups g
  join public.group_members gm on gm.group_id = g.id
  where g.id = p_group_id
    and g.archived_at is null
    and gm.user_id = auth.uid()
    and gm.role = 'leader'
    and gm.left_at is null
  for update of g, gm;

  if not found then
    raise exception 'Group leader permission required' using errcode = 'P0001';
  end if;

  select p.user_id into v_new_deputy_id
  from public.profiles p
  where p.friend_code = p_new_deputy_friend_code;

  if v_new_deputy_id is null or v_new_deputy_id = auth.uid() then
    raise exception 'New deputy must be an active group member' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = v_new_deputy_id
      and gm.left_at is null
      and gm.role in ('member', 'deputy_leader')
  ) then
    raise exception 'New deputy must be an active group member' using errcode = 'P0001';
  end if;

  select gm.user_id into v_old_deputy_id
  from public.group_members gm
  where gm.group_id = p_group_id
    and gm.role = 'deputy_leader'
    and gm.left_at is null
  for update;

  if v_old_deputy_id is distinct from v_new_deputy_id then
    update public.group_members
    set role = 'member'
    where group_id = p_group_id
      and user_id = v_old_deputy_id
      and left_at is null;

    update public.group_members
    set role = 'deputy_leader'
    where group_id = p_group_id
      and user_id = v_new_deputy_id
      and left_at is null;
  end if;

  update public.groups
  set deputy_missing_since = null,
      deputy_deadline_at = null
  where id = p_group_id
    and archived_at is null;

  return true;
end;
$$;

create or replace function public.get_group_deputy_status(p_group_id uuid)
returns table (
  deputy_required boolean,
  missing_since timestamptz,
  deadline_at timestamptz,
  is_archived boolean
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
    join public.groups g on g.id = gm.group_id
    where gm.group_id = p_group_id
      and gm.user_id = auth.uid()
      and gm.left_at is null
  ) then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;

  return query
    select g.deputy_deadline_at is not null,
      g.deputy_missing_since, g.deputy_deadline_at,
      g.archived_at is not null
    from public.groups g
    where g.id = p_group_id;
end;
$$;

create or replace function public.archive_groups_missing_deputy(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_archived_count integer;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;

  update public.groups g
  set archived_at = p_now,
      archive_reason = 'deputy_missing_timeout'
  where g.archived_at is null
    and g.deputy_deadline_at is not null
    and g.deputy_deadline_at <= p_now
    and not exists (
      select 1 from public.group_members gm
      where gm.group_id = g.id
        and gm.role = 'deputy_leader'
        and gm.left_at is null
    );

  get diagnostics v_archived_count = row_count;
  return v_archived_count;
end;
$$;

revoke all on function private.track_missing_group_deputy() from public, anon, authenticated;
revoke all on function public.change_group_deputy(uuid, text) from public, anon, authenticated;
revoke all on function public.get_group_deputy_status(uuid) from public, anon, authenticated;
revoke all on function public.archive_groups_missing_deputy(timestamptz) from public, anon, authenticated;

grant execute on function public.change_group_deputy(uuid, text) to authenticated;
grant execute on function public.get_group_deputy_status(uuid) to authenticated;
grant execute on function public.archive_groups_missing_deputy(timestamptz) to service_role;

commit;

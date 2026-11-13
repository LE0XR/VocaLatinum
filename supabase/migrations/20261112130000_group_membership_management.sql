-- VocaLatinum: sichere Gruppenmitglieder-Verwaltung
begin;

create or replace function public.list_group_members(p_group_id uuid)
returns table (
  display_name text,
  member_role text,
  joined_at timestamptz
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
    join public.groups g on g.id = gm.group_id
    where gm.group_id = p_group_id
      and gm.user_id = auth.uid()
      and gm.left_at is null
      and g.archived_at is null
  ) then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;

  return query
    select p.display_name, gm.role, gm.joined_at
    from public.group_members gm
    join public.profiles p on p.user_id = gm.user_id
    where gm.group_id = p_group_id
      and gm.left_at is null
    order by case gm.role
      when 'leader' then 1
      when 'deputy_leader' then 2
      else 3
    end, gm.joined_at;
end;
$$;

create or replace function public.leave_group(p_group_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;

  select gm.role into v_role
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  where gm.group_id = p_group_id
    and gm.user_id = auth.uid()
    and gm.left_at is null
    and g.archived_at is null
  for update of gm;

  if v_role is null then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;
  if v_role = 'leader' then
    raise exception 'Leader must transfer leadership before leaving' using errcode = 'P0001';
  end if;

  update public.group_members
  set left_at = now()
  where group_id = p_group_id
    and user_id = auth.uid()
    and left_at is null;

  return true;
end;
$$;

create or replace function public.remove_group_member(
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
  v_member_role text;
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
  where gm.group_id = p_group_id
    and gm.user_id = auth.uid()
    and gm.left_at is null
    and g.archived_at is null
  for update of gm;

  if v_actor_role not in ('leader', 'deputy_leader') or v_actor_role is null then
    raise exception 'Group manager permission required' using errcode = 'P0001';
  end if;

  select p.user_id, gm.role into v_member_id, v_member_role
  from public.profiles p
  join public.group_members gm on gm.user_id = p.user_id
  where p.friend_code = p_member_friend_code
    and gm.group_id = p_group_id
    and gm.left_at is null
  for update of gm;

  if v_member_id is null then
    raise exception 'Active group member not found' using errcode = 'P0001';
  end if;
  if v_member_role <> 'member' then
    raise exception 'Managers cannot remove group leaders' using errcode = 'P0001';
  end if;

  update public.group_members
  set left_at = now()
  where group_id = p_group_id
    and user_id = v_member_id
    and left_at is null;

  return true;
end;
$$;

revoke all on function public.list_group_members(uuid) from public, anon, authenticated;
revoke all on function public.leave_group(uuid) from public, anon, authenticated;
revoke all on function public.remove_group_member(uuid, text) from public, anon, authenticated;

grant execute on function public.list_group_members(uuid) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;
grant execute on function public.remove_group_member(uuid, text) to authenticated;

commit;

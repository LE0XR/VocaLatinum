-- VocaLatinum: Gruppenleitung übertragen und Stellvertretung wechseln
begin;

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

  if not exists (
    select 1 from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.group_id = p_group_id
      and gm.user_id = auth.uid()
      and gm.role = 'leader'
      and gm.left_at is null
      and g.archived_at is null
    for update of gm, g
  ) then
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

  if v_old_deputy_id = v_new_deputy_id then
    return true;
  end if;

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

  return true;
end;
$$;

create or replace function public.transfer_group_leadership(p_group_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deputy_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if p_group_id is null then
    raise exception 'Group is required' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.group_id = p_group_id
      and gm.user_id = auth.uid()
      and gm.role = 'leader'
      and gm.left_at is null
      and g.archived_at is null
    for update of gm, g
  ) then
    raise exception 'Group leader permission required' using errcode = 'P0001';
  end if;

  select gm.user_id into v_deputy_id
  from public.group_members gm
  where gm.group_id = p_group_id
    and gm.role = 'deputy_leader'
    and gm.left_at is null
  for update;

  if v_deputy_id is null then
    raise exception 'Active deputy required for leadership transfer' using errcode = 'P0001';
  end if;

  update public.group_members
  set role = 'member'
  where group_id = p_group_id
    and user_id = v_deputy_id
    and left_at is null;

  update public.group_members
  set role = 'deputy_leader'
  where group_id = p_group_id
    and user_id = auth.uid()
    and left_at is null;

  update public.group_members
  set role = 'leader'
  where group_id = p_group_id
    and user_id = v_deputy_id
    and left_at is null;

  return true;
end;
$$;

revoke all on function public.change_group_deputy(uuid, text) from public, anon, authenticated;
revoke all on function public.transfer_group_leadership(uuid) from public, anon, authenticated;

grant execute on function public.change_group_deputy(uuid, text) to authenticated;
grant execute on function public.transfer_group_leadership(uuid) to authenticated;

commit;

-- VocaLatinum: sichere Gruppen-Grundfunktionen
-- Alle Gruppen- und Einladungsdaten bleiben über RPCs geschützt.

begin;

create or replace function public.create_group(
  p_name text,
  p_deputy_friend_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deputy_id uuid;
  v_group_id uuid;
  v_name text := btrim(coalesce(p_name, ''));
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 32 then
    raise exception 'Group name must contain 2 to 32 characters' using errcode = 'P0001';
  end if;
  if p_deputy_friend_code is null or p_deputy_friend_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception 'Valid deputy friend code required' using errcode = 'P0001';
  end if;

  select p.user_id into v_deputy_id
  from public.profiles p
  where p.friend_code = p_deputy_friend_code;

  if v_deputy_id is null or v_deputy_id = auth.uid() then
    raise exception 'Deputy must be a different confirmed friend' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.friendships f
    where f.user_a = least(auth.uid(), v_deputy_id)
      and f.user_b = greatest(auth.uid(), v_deputy_id)
  ) then
    raise exception 'Deputy must be a confirmed friend' using errcode = 'P0001';
  end if;

  insert into public.groups (name, created_by)
  values (v_name, auth.uid())
  returning id into v_group_id;

  insert into public.group_members (group_id, user_id, role)
  values
    (v_group_id, auth.uid(), 'leader'),
    (v_group_id, v_deputy_id, 'deputy_leader');

  insert into public.group_settings (group_id)
  values (v_group_id);

  return v_group_id;
end;
$$;

create or replace function public.list_my_groups()
returns table (
  group_id uuid,
  group_name text,
  my_role text,
  member_count integer,
  created_at timestamptz
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

  return query
    select g.id, g.name, gm.role,
      (select count(*)::integer from public.group_members m
       where m.group_id = g.id and m.left_at is null),
      g.created_at
    from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.user_id = auth.uid()
      and gm.left_at is null
      and g.archived_at is null
    order by g.created_at desc;
end;
$$;

create or replace function public.invite_friend_to_group(
  p_group_id uuid,
  p_friend_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitee_id uuid;
  v_invite_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if p_group_id is null or p_friend_code is null
    or p_friend_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception 'Invalid group or friend code' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id = auth.uid()
      and gm.left_at is null and gm.role in ('leader', 'deputy_leader')
  ) then
    raise exception 'Group manager permission required' using errcode = 'P0001';
  end if;

  select p.user_id into v_invitee_id
  from public.profiles p where p.friend_code = p_friend_code;

  if v_invitee_id is null or v_invitee_id = auth.uid() then
    raise exception 'Invitee must be a different confirmed friend' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.friendships f
    where f.user_a = least(auth.uid(), v_invitee_id)
      and f.user_b = greatest(auth.uid(), v_invitee_id)
  ) then
    raise exception 'Invitee must be a confirmed friend' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id = v_invitee_id
      and gm.left_at is null
  ) then
    raise exception 'User is already a group member' using errcode = 'P0001';
  end if;

  insert into public.group_invites (group_id, inviter_id, invitee_id, expires_at)
  values (p_group_id, auth.uid(), v_invitee_id, now() + interval '7 days')
  returning id into v_invite_id;

  return v_invite_id;
exception
  when unique_violation then
    raise exception 'A pending invitation already exists' using errcode = 'P0001';
end;
$$;

create or replace function public.list_group_invites()
returns table (
  invite_id uuid,
  group_id uuid,
  group_name text,
  inviter_name text,
  created_at timestamptz,
  expires_at timestamptz
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

  return query
    select i.id, i.group_id, g.name, p.display_name, i.created_at, i.expires_at
    from public.group_invites i
    join public.groups g on g.id = i.group_id
    join public.profiles p on p.user_id = i.inviter_id
    where i.invitee_id = auth.uid()
      and i.status = 'pending'
      and (i.expires_at is null or i.expires_at > now())
    order by i.created_at desc;
end;
$$;

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

  if p_accept then
    insert into public.group_members (group_id, user_id, role)
    values (v_group_id, auth.uid(), 'member');
    update public.group_invites set status = 'accepted' where id = p_invite_id;
  else
    update public.group_invites set status = 'rejected' where id = p_invite_id;
  end if;

  return true;
end;
$$;

revoke all on function public.create_group(text, text) from public, anon, authenticated;
revoke all on function public.list_my_groups() from public, anon, authenticated;
revoke all on function public.invite_friend_to_group(uuid, text) from public, anon, authenticated;
revoke all on function public.list_group_invites() from public, anon, authenticated;
revoke all on function public.respond_to_group_invite(uuid, boolean) from public, anon, authenticated;

grant execute on function public.create_group(text, text) to authenticated;
grant execute on function public.list_my_groups() to authenticated;
grant execute on function public.invite_friend_to_group(uuid, text) to authenticated;
grant execute on function public.list_group_invites() to authenticated;
grant execute on function public.respond_to_group_invite(uuid, boolean) to authenticated;

commit;

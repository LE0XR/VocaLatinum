-- VocaLatinum: sichere Textchat- und Moderationsgrundlage
begin;

create table if not exists public.group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  sender_id uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references auth.users (id) on delete set null,
  constraint group_messages_deleted_consistency
    check ((deleted_at is null and deleted_by is null)
        or (deleted_at is not null and deleted_by is not null))
);

create index if not exists group_messages_timeline_idx
  on public.group_messages (group_id, created_at desc)
  where deleted_at is null;

create table if not exists public.group_message_reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.group_messages (id) on delete cascade,
  group_id uuid not null references public.groups (id) on delete cascade,
  reporter_id uuid not null references auth.users (id) on delete cascade,
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  created_at timestamptz not null default now(),
  status text not null default 'open'
    check (status in ('open', 'reviewed', 'dismissed', 'actioned')),
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz
);

create unique index if not exists group_message_reports_one_per_user
  on public.group_message_reports (message_id, reporter_id);

create table if not exists public.group_chat_blocks (
  group_id uuid not null references public.groups (id) on delete cascade,
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (group_id, blocker_id, blocked_id),
  constraint group_chat_blocks_no_self check (blocker_id <> blocked_id)
);

alter table public.group_messages enable row level security;
alter table public.group_messages force row level security;
alter table public.group_message_reports enable row level security;
alter table public.group_message_reports force row level security;
alter table public.group_chat_blocks enable row level security;
alter table public.group_chat_blocks force row level security;

revoke all on table public.group_messages, public.group_message_reports, public.group_chat_blocks
from public, anon, authenticated;

create or replace function public.send_group_message(
  p_group_id uuid,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message_id uuid;
  v_body text := btrim(coalesce(p_body, ''));
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if p_group_id is null or char_length(v_body) < 1 or char_length(v_body) > 2000 then
    raise exception 'Message must contain 1 to 2000 characters' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.group_id = p_group_id and gm.user_id = auth.uid()
      and gm.left_at is null and g.archived_at is null
  ) then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;

  insert into public.group_messages (group_id, sender_id, body)
  values (p_group_id, auth.uid(), v_body)
  returning id into v_message_id;
  return v_message_id;
end;
$$;

create or replace function public.list_group_messages(
  p_group_id uuid,
  p_limit integer default 50
)
returns table (
  message_id uuid,
  sender_name text,
  message_body text,
  created_at timestamptz,
  is_mine boolean
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
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'Limit must be between 1 and 100' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.group_id = p_group_id and gm.user_id = auth.uid()
      and gm.left_at is null and g.archived_at is null
  ) then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;

  return query
    select m.id, p.display_name, m.body, m.created_at, m.sender_id = auth.uid()
    from public.group_messages m
    join public.profiles p on p.user_id = m.sender_id
    where m.group_id = p_group_id
      and m.deleted_at is null
      and not exists (
        select 1 from public.group_chat_blocks b
        where b.group_id = p_group_id
          and ((b.blocker_id = auth.uid() and b.blocked_id = m.sender_id)
            or (b.blocked_id = auth.uid() and b.blocker_id = m.sender_id))
      )
    order by m.created_at desc
    limit p_limit;
end;
$$;

create or replace function public.delete_group_message(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_id uuid;
  v_sender_id uuid;
  v_actor_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;

  select m.group_id, m.sender_id into v_group_id, v_sender_id
  from public.group_messages m
  where m.id = p_message_id and m.deleted_at is null
  for update;

  if v_group_id is null then
    raise exception 'Message not found' using errcode = 'P0001';
  end if;

  select gm.role into v_actor_role
  from public.group_members gm
  where gm.group_id = v_group_id and gm.user_id = auth.uid()
    and gm.left_at is null;

  if v_actor_role is null then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;
  if v_sender_id <> auth.uid() and v_actor_role not in ('leader', 'deputy_leader') then
    raise exception 'Own message or group manager permission required' using errcode = 'P0001';
  end if;

  update public.group_messages
  set body = '[Nachricht gelöscht]', deleted_at = now(), deleted_by = auth.uid()
  where id = p_message_id;
  return true;
end;
$$;

create or replace function public.report_group_message(
  p_message_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_id uuid;
  v_sender_id uuid;
  v_report_id uuid;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if char_length(v_reason) < 3 or char_length(v_reason) > 500 then
    raise exception 'Report reason must contain 3 to 500 characters' using errcode = 'P0001';
  end if;

  select m.group_id, m.sender_id into v_group_id, v_sender_id
  from public.group_messages m
  where m.id = p_message_id and m.deleted_at is null;

  if v_group_id is null then
    raise exception 'Message not found' using errcode = 'P0001';
  end if;
  if v_sender_id = auth.uid() then
    raise exception 'Cannot report your own message' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_members gm
    where gm.group_id = v_group_id and gm.user_id = auth.uid() and gm.left_at is null
  ) then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;

  insert into public.group_message_reports (message_id, group_id, reporter_id, reason)
  values (p_message_id, v_group_id, auth.uid(), v_reason)
  returning id into v_report_id;
  return v_report_id;
exception
  when unique_violation then
    raise exception 'Message already reported by this user' using errcode = 'P0001';
end;
$$;

create or replace function public.block_group_member(
  p_group_id uuid,
  p_member_friend_code text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_blocked_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;
  if p_group_id is null or p_member_friend_code is null
    or p_member_friend_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception 'Invalid group or friend code' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id = auth.uid() and gm.left_at is null
  ) then
    raise exception 'Active group membership required' using errcode = 'P0001';
  end if;

  select p.user_id into v_blocked_id
  from public.profiles p
  join public.group_members gm on gm.user_id = p.user_id
  where p.friend_code = p_member_friend_code
    and gm.group_id = p_group_id and gm.left_at is null;

  if v_blocked_id is null or v_blocked_id = auth.uid() then
    raise exception 'Another active group member is required' using errcode = 'P0001';
  end if;

  insert into public.group_chat_blocks (group_id, blocker_id, blocked_id)
  values (p_group_id, auth.uid(), v_blocked_id)
  on conflict do nothing;
  return true;
end;
$$;

create or replace function public.unblock_group_member(
  p_group_id uuid,
  p_member_friend_code text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_blocked_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;

  select p.user_id into v_blocked_id
  from public.profiles p
  where p.friend_code = p_member_friend_code;

  if v_blocked_id is null then
    raise exception 'Member not found' using errcode = 'P0001';
  end if;

  delete from public.group_chat_blocks
  where group_id = p_group_id and blocker_id = auth.uid() and blocked_id = v_blocked_id;
  return true;
end;
$$;

revoke all on function public.send_group_message(uuid, text) from public, anon, authenticated;
revoke all on function public.list_group_messages(uuid, integer) from public, anon, authenticated;
revoke all on function public.delete_group_message(uuid) from public, anon, authenticated;
revoke all on function public.report_group_message(uuid, text) from public, anon, authenticated;
revoke all on function public.block_group_member(uuid, text) from public, anon, authenticated;
revoke all on function public.unblock_group_member(uuid, text) from public, anon, authenticated;

grant execute on function public.send_group_message(uuid, text) to authenticated;
grant execute on function public.list_group_messages(uuid, integer) to authenticated;
grant execute on function public.delete_group_message(uuid) to authenticated;
grant execute on function public.report_group_message(uuid, text) to authenticated;
grant execute on function public.block_group_member(uuid, text) to authenticated;
grant execute on function public.unblock_group_member(uuid, text) to authenticated;

commit;

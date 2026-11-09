-- VocaLatinum: Begrenzung ausgehender Freundschaftsanfragen
-- Schützt Nutzer vor automatisierten oder massenhaften Anfragen.

begin;

create table if not exists private.friend_request_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  request_count integer not null check (request_count >= 0)
);

revoke all on table private.friend_request_rate_limits from public, anon, authenticated;

create or replace function private.consume_friend_request_limit()
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;

  insert into private.friend_request_rate_limits (
    user_id, window_started_at, request_count
  )
  values (v_user_id, clock_timestamp(), 1)
  on conflict (user_id) do update
    set window_started_at = case
          when private.friend_request_rate_limits.window_started_at
               <= clock_timestamp() - interval '1 hour'
            then clock_timestamp()
          else private.friend_request_rate_limits.window_started_at
        end,
        request_count = case
          when private.friend_request_rate_limits.window_started_at
               <= clock_timestamp() - interval '1 hour'
            then 1
          else private.friend_request_rate_limits.request_count + 1
        end
  returning request_count into v_count;

  return v_count <= 10;
end;
$$;

revoke all on function private.consume_friend_request_limit() from public, anon, authenticated;

create or replace function public.send_friend_request(p_recipient_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sender_id uuid := auth.uid();
  v_request_id uuid;
begin
  if v_sender_id is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;

  if p_recipient_id is null or p_recipient_id = v_sender_id then
    raise exception 'Invalid recipient' using errcode = 'P0001';
  end if;

  if not exists (select 1 from auth.users u where u.id = p_recipient_id) then
    raise exception 'Recipient not found' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.friendships f
    where f.user_a = least(v_sender_id, p_recipient_id)
      and f.user_b = greatest(v_sender_id, p_recipient_id)
  ) then
    raise exception 'Already friends' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.friend_requests fr
    where fr.status = 'pending'
      and least(fr.sender_id, fr.recipient_id) = least(v_sender_id, p_recipient_id)
      and greatest(fr.sender_id, fr.recipient_id) = greatest(v_sender_id, p_recipient_id)
  ) then
    raise exception 'A pending request already exists between these accounts' using errcode = 'P0001';
  end if;

  if not private.consume_friend_request_limit() then
    raise exception 'Friend request rate limit exceeded; try again later' using errcode = 'P0001';
  end if;

  insert into public.friend_requests (sender_id, recipient_id)
  values (v_sender_id, p_recipient_id)
  returning id into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.send_friend_request(uuid) from public, anon, authenticated;
grant execute on function public.send_friend_request(uuid) to authenticated;

commit;

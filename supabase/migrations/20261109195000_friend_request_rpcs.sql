-- VocaLatinum: sichere serverseitige Freundschaftsanfragen
-- Direkte Tabellenrechte bleiben gesperrt; Clients verwenden nur diese RPC-Funktionen.

begin;

-- Verhindert parallele/offene Anfragen in beide Richtungen zwischen denselben Konten.
create unique index if not exists friend_requests_one_pending_per_pair
  on public.friend_requests (
    least(sender_id, recipient_id),
    greatest(sender_id, recipient_id)
  )
  where status = 'pending';

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

  insert into public.friend_requests (sender_id, recipient_id)
  values (v_sender_id, p_recipient_id)
  returning id into v_request_id;

  return v_request_id;
end;
$$;

create or replace function public.list_friend_requests()
returns table (
  request_id uuid,
  direction text,
  other_display_name text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    fr.id,
    case when fr.sender_id = auth.uid() then 'outgoing' else 'incoming' end,
    p.display_name,
    fr.created_at
  from public.friend_requests fr
  join public.profiles p
    on p.user_id = case
      when fr.sender_id = auth.uid() then fr.recipient_id
      else fr.sender_id
    end
  where fr.status = 'pending'
    and (fr.sender_id = auth.uid() or fr.recipient_id = auth.uid())
  order by fr.created_at desc;
$$;

create or replace function public.accept_friend_request(p_request_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sender_id uuid;
  v_recipient_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;

  select fr.sender_id, fr.recipient_id
    into v_sender_id, v_recipient_id
  from public.friend_requests fr
  where fr.id = p_request_id
    and fr.status = 'pending'
  for update;

  if not found then
    raise exception 'Friend request not found or not available to this account' using errcode = 'P0001';
  end if;

  if v_recipient_id <> auth.uid() then
    raise exception 'Only the recipient can accept this request' using errcode = 'P0001';
  end if;

  insert into public.friendships (user_a, user_b)
  values (least(v_sender_id, v_recipient_id), greatest(v_sender_id, v_recipient_id))
  on conflict do nothing;

  update public.friend_requests
  set status = 'accepted', updated_at = now()
  where id = p_request_id and status = 'pending';

  return true;
end;
$$;

create or replace function public.reject_friend_request(p_request_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;

  update public.friend_requests
  set status = 'rejected', updated_at = now()
  where id = p_request_id
    and recipient_id = auth.uid()
    and status = 'pending';

  if not found then
    raise exception 'Friend request not found or not available to this account' using errcode = 'P0001';
  end if;

  return true;
end;
$$;

revoke all on function public.send_friend_request(uuid) from public, anon, authenticated;
revoke all on function public.list_friend_requests() from public, anon, authenticated;
revoke all on function public.accept_friend_request(uuid) from public, anon, authenticated;
revoke all on function public.reject_friend_request(uuid) from public, anon, authenticated;

grant execute on function public.send_friend_request(uuid) to authenticated;
grant execute on function public.list_friend_requests() to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.reject_friend_request(uuid) to authenticated;

commit;

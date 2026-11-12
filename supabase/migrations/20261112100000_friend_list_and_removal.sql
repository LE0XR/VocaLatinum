-- VocaLatinum: sichere Freundesliste und Freundschaft beenden
-- Freundschaften bleiben ausschließlich über geprüfte RPC-Funktionen erreichbar.

begin;

create or replace function public.list_friends()
returns table (
  display_name text,
  friend_code text,
  friends_since timestamptz
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
    select p.display_name, p.friend_code, f.created_at
    from public.friendships f
    join public.profiles p
      on p.user_id = case
        when f.user_a = auth.uid() then f.user_b
        else f.user_a
      end
    where f.user_a = least(auth.uid(), p.user_id)
      and f.user_b = greatest(auth.uid(), p.user_id)
    order by lower(p.display_name), p.friend_code;
end;
$$;

create or replace function public.remove_friend(p_friend_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;

  if p_friend_user_id is null or p_friend_user_id = auth.uid() then
    raise exception 'Invalid friend' using errcode = 'P0001';
  end if;

  delete from public.friendships f
  where f.user_a = least(auth.uid(), p_friend_user_id)
    and f.user_b = greatest(auth.uid(), p_friend_user_id);

  if not found then
    raise exception 'Friendship not found or not available to this account' using errcode = 'P0001';
  end if;

  return true;
end;
$$;

revoke all on function public.list_friends() from public, anon, authenticated;
revoke all on function public.remove_friend(uuid) from public, anon, authenticated;

grant execute on function public.list_friends() to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;

commit;

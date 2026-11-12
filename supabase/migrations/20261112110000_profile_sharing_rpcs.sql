-- VocaLatinum: sichere Profilfreigaben für bestätigte Freunde
-- Nutzer können nur ihre eigenen Freigaben ändern. Freunde sehen ausschließlich
-- die Freigabeeinstellungen, niemals interne Auth-IDs oder fremde Tabellenzeilen.

begin;

create or replace function public.update_my_profile_sharing(
  p_share_level boolean,
  p_share_xp boolean,
  p_share_badges boolean,
  p_share_weekly_stats boolean
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

  if p_share_level is null
    or p_share_xp is null
    or p_share_badges is null
    or p_share_weekly_stats is null then
    raise exception 'Sharing choices must be explicit' using errcode = 'P0001';
  end if;

  update public.profile_sharing
  set share_level = p_share_level,
      share_xp = p_share_xp,
      share_badges = p_share_badges,
      share_weekly_stats = p_share_weekly_stats
  where user_id = auth.uid();

  if not found then
    raise exception 'Profile sharing settings not found' using errcode = 'P0001';
  end if;

  return true;
end;
$$;

create or replace function public.list_friend_sharing()
returns table (
  display_name text,
  friend_code text,
  share_level boolean,
  share_xp boolean,
  share_badges boolean,
  share_weekly_stats boolean
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
    select p.display_name, p.friend_code,
           s.share_level, s.share_xp, s.share_badges, s.share_weekly_stats
    from public.friendships f
    join public.profiles p
      on p.user_id = case
        when f.user_a = auth.uid() then f.user_b
        else f.user_a
      end
    join public.profile_sharing s on s.user_id = p.user_id
    where f.user_a = least(auth.uid(), p.user_id)
      and f.user_b = greatest(auth.uid(), p.user_id)
    order by lower(p.display_name), p.friend_code;
end;
$$;

revoke all on function public.update_my_profile_sharing(boolean, boolean, boolean, boolean)
  from public, anon, authenticated;
revoke all on function public.list_friend_sharing() from public, anon, authenticated;

grant execute on function public.update_my_profile_sharing(boolean, boolean, boolean, boolean)
  to authenticated;
grant execute on function public.list_friend_sharing() to authenticated;

commit;

-- VocaLatinum: serverseitige Begrenzung der Profilsuche
-- Verhindert unbegrenztes automatisiertes Durchsuchen von Profilen.

begin;

create table if not exists private.profile_search_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null,
  request_count integer not null check (request_count >= 0)
);

revoke all on table private.profile_search_rate_limits from public, anon, authenticated;

create or replace function private.consume_profile_search_limit()
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

  insert into private.profile_search_rate_limits (
    user_id, window_started_at, request_count
  )
  values (v_user_id, clock_timestamp(), 1)
  on conflict (user_id) do update
    set window_started_at = case
          when private.profile_search_rate_limits.window_started_at
               <= clock_timestamp() - interval '10 minutes'
            then clock_timestamp()
          else private.profile_search_rate_limits.window_started_at
        end,
        request_count = case
          when private.profile_search_rate_limits.window_started_at
               <= clock_timestamp() - interval '10 minutes'
            then 1
          else private.profile_search_rate_limits.request_count + 1
        end
  returning request_count into v_count;

  return v_count <= 20;
end;
$$;

revoke all on function private.consume_profile_search_limit() from public, anon, authenticated;

create or replace function public.search_profiles(p_query text)
returns table (
  display_name text,
  friend_code text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_query text := upper(trim(coalesce(p_query, '')));
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;

  if char_length(trim(coalesce(p_query, ''))) < 3 then
    raise exception 'Search query must contain at least 3 characters' using errcode = 'P0001';
  end if;

  if not private.consume_profile_search_limit() then
    raise exception 'Search rate limit exceeded; try again later' using errcode = 'P0001';
  end if;

  return query
    select p.display_name, p.friend_code
    from public.profiles p
    where p.user_id <> auth.uid()
      and (
        upper(p.friend_code) = v_query
        or left(lower(p.display_name), char_length(trim(p_query))) =
           lower(trim(p_query))
      )
    order by
      case when upper(p.friend_code) = v_query then 0 else 1 end,
      lower(p.display_name),
      p.friend_code
    limit 20;
end;
$$;

revoke all on function public.search_profiles(text) from public, anon, authenticated;
grant execute on function public.search_profiles(text) to authenticated;

commit;

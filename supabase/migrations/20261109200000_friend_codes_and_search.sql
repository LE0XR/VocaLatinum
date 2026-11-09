-- VocaLatinum: eindeutige Freundescodes und sichere Profilsuche
-- Freundescodes sind öffentliche Suchkennungen, keine Auth-IDs oder Geheimnisse.

begin;

create or replace function private.generate_friend_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  v_attempt integer := 0;
  v_index integer;
begin
  loop
    v_attempt := v_attempt + 1;
    v_code := '';
    for v_index in 1..6 loop
      v_code := v_code || substr(
        v_alphabet,
        1 + floor(random() * char_length(v_alphabet))::integer,
        1
      );
    end loop;

    exit when not exists (
      select 1 from public.profiles p where p.friend_code = v_code
    );

    if v_attempt >= 100 then
      raise exception 'Could not allocate a unique friend code';
    end if;
  end loop;

  return v_code;
end;
$$;

alter table public.profiles
  add column if not exists friend_code text;

-- Bestehende Profile erhalten ebenfalls einen Code.
do $$
declare
  v_user record;
begin
  for v_user in
    select p.user_id
    from public.profiles p
    where p.friend_code is null
  loop
    update public.profiles
    set friend_code = private.generate_friend_code()
    where user_id = v_user.user_id;
  end loop;
end;
$$;

alter table public.profiles
  alter column friend_code set not null;

create unique index if not exists profiles_friend_code_unique
  on public.profiles (friend_code);

create or replace function private.assign_friend_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.friend_code is null or new.friend_code = '' then
    new.friend_code := private.generate_friend_code();
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_assign_friend_code on public.profiles;
create trigger profiles_assign_friend_code
  before insert on public.profiles
  for each row execute function private.assign_friend_code();

revoke all on function private.generate_friend_code() from public, anon, authenticated;
revoke all on function private.assign_friend_code() from public, anon, authenticated;

create or replace function public.search_profiles(p_query text)
returns table (
  display_name text,
  friend_code text
)
language plpgsql
stable
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

create or replace function public.send_friend_request_by_code(p_friend_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = 'P0001';
  end if;

  select p.user_id into v_recipient_id
  from public.profiles p
  where p.friend_code = upper(trim(coalesce(p_friend_code, '')))
    and p.user_id <> auth.uid();

  if v_recipient_id is null then
    raise exception 'Friend code not found' using errcode = 'P0001';
  end if;

  return public.send_friend_request(v_recipient_id);
end;
$$;

revoke all on function public.search_profiles(text) from public, anon, authenticated;
revoke all on function public.send_friend_request_by_code(text) from public, anon, authenticated;
grant execute on function public.search_profiles(text) to authenticated;
grant execute on function public.send_friend_request_by_code(text) to authenticated;

commit;

-- VocaLatinum: automatische Archivierung nach Ablauf der Zwei-Tage-Frist
-- Supabase Cron prueft alle 15 Minuten, ob Gruppen ohne Stellvertretung ablaufen.
begin;

create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

create or replace function private.archive_groups_missing_deputy_cron()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_archived_count integer;
begin
  update public.groups g
  set archived_at = now(),
      archive_reason = 'deputy_missing_timeout'
  where g.archived_at is null
    and g.deputy_deadline_at is not null
    and g.deputy_deadline_at <= now()
    and not exists (
      select 1 from public.group_members gm
      where gm.group_id = g.id
        and gm.role = 'deputy_leader'
        and gm.left_at is null
    );

  get diagnostics v_archived_count = row_count;
  return v_archived_count;
end;
$$;

revoke all on function private.archive_groups_missing_deputy_cron()
  from public, anon, authenticated;
grant execute on function private.archive_groups_missing_deputy_cron()
  to postgres;

create or replace function public.archive_groups_missing_deputy(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;

  return private.archive_groups_missing_deputy_cron();
end;
$$;

revoke all on function public.archive_groups_missing_deputy(timestamptz)
  from public, anon, authenticated;
grant execute on function public.archive_groups_missing_deputy(timestamptz)
  to service_role;

select cron.schedule(
  'vocalatinum-archive-groups-missing-deputy',
  '*/15 * * * *',
  'select private.archive_groups_missing_deputy_cron();'
);

commit;

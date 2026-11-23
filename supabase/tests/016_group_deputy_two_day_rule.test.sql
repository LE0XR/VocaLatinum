begin;

select plan(10);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('e1000000-0000-4000-8000-000000000001', 'deputy-rule-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('e2000000-0000-4000-8000-000000000002', 'deputy-rule-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('e3000000-0000-4000-8000-000000000003', 'deputy-rule-three@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

insert into public.friendships (user_a, user_b)
values
  ('e1000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000002'),
  ('e1000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000003');

select set_config('test.deputy_two_code',
  (select friend_code from public.profiles where user_id='e2000000-0000-4000-8000-000000000002'), true);
select set_config('test.deputy_three_code',
  (select friend_code from public.profiles where user_id='e3000000-0000-4000-8000-000000000003'), true);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select set_config('test.deputy_group_replace',
  public.create_group('Stellvertretung wechseln', current_setting('test.deputy_two_code'))::text, true);
select set_config('test.deputy_invite',
  public.invite_friend_to_group(
    current_setting('test.deputy_group_replace')::uuid,
    current_setting('test.deputy_three_code')
  )::text, true);
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e3000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select ok(public.respond_to_group_invite(current_setting('test.deputy_invite')::uuid, true),
  'Additional member can join the group');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e2000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select ok(public.leave_group(current_setting('test.deputy_group_replace')::uuid),
  'Deputy can leave the group');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select ok((select deputy_required from public.get_group_deputy_status(
  current_setting('test.deputy_group_replace')::uuid)),
  'Leaving deputy starts the replacement requirement');
select ok(public.change_group_deputy(
  current_setting('test.deputy_group_replace')::uuid,
  current_setting('test.deputy_three_code')
), 'Leader can appoint a replacement deputy during the grace period');
select ok(not (select deputy_required from public.get_group_deputy_status(
  current_setting('test.deputy_group_replace')::uuid)),
  'Appointing a replacement clears the deadline');
select set_config('test.deputy_group_archive',
  public.create_group('Archiv nach Frist', current_setting('test.deputy_three_code'))::text, true);
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e3000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select ok(public.leave_group(current_setting('test.deputy_group_archive')::uuid),
  'Deputy can leave the second group');
reset role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select is(public.archive_groups_missing_deputy(now() + interval '1 day'), 0,
  'Group is not archived before the two-day deadline');
select is(public.archive_groups_missing_deputy(now() + interval '3 days'), 1,
  'Group is archived after the two-day deadline');
reset role;

select ok((select archived_at is not null
  and archive_reason = 'deputy_missing_timeout'
  from public.groups where id = current_setting('test.deputy_group_archive')::uuid),
  'Expired group is marked as archived with a reason');
select is((select count(*)::integer from public.group_members
  where group_id = current_setting('test.deputy_group_archive')::uuid), 2,
  'Archiving preserves group membership history');

select * from finish();
rollback;

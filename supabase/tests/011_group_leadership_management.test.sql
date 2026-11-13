begin;

select plan(10);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('d1000000-0000-4000-8000-000000000001', 'leadership-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('d2000000-0000-4000-8000-000000000002', 'leadership-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('d3000000-0000-4000-8000-000000000003', 'leadership-three@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

insert into public.friendships (user_a, user_b)
values
  ('d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000002'),
  ('d1000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000003');

select set_config('test.leadership_two_code',
  (select friend_code from public.profiles where user_id='d2000000-0000-4000-8000-000000000002'), true);
select set_config('test.leadership_three_code',
  (select friend_code from public.profiles where user_id='d3000000-0000-4000-8000-000000000003'), true);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"d1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('test.leadership_group_id',
  public.create_group('Leitungswechsel', current_setting('test.leadership_two_code'))::text, true);

select set_config('test.leadership_invite_id',
  public.invite_friend_to_group(
    current_setting('test.leadership_group_id')::uuid,
    current_setting('test.leadership_three_code')
  )::text, true);
select ok(current_setting('test.leadership_invite_id') <> '',
  'Leader can invite a confirmed friend');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"d3000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select ok(public.respond_to_group_invite(current_setting('test.leadership_invite_id')::uuid, true),
  'Invited friend can join');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"d1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select ok(public.change_group_deputy(
  current_setting('test.leadership_group_id')::uuid,
  current_setting('test.leadership_three_code')
), 'Leader can appoint an active member as new deputy');
select is((select count(*)::integer from public.list_group_members(
  current_setting('test.leadership_group_id')::uuid) where member_role = 'deputy_leader'), 1,
  'There is exactly one active deputy');
select ok(public.transfer_group_leadership(current_setting('test.leadership_group_id')::uuid),
  'Leader can transfer leadership to the deputy');
select is((select my_role from public.list_my_groups()), 'deputy_leader',
  'Former leader becomes deputy after transfer');
select ok(public.leave_group(current_setting('test.leadership_group_id')::uuid),
  'Former leader can leave after transferring leadership');
select is((select count(*)::integer from public.list_my_groups()), 0,
  'Former leader no longer sees the group after leaving');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"d3000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select is((select my_role from public.list_my_groups()), 'leader',
  'New leader sees the leader role');
select is((select count(*)::integer from public.list_group_members(
  current_setting('test.leadership_group_id')::uuid) where member_role = 'leader'), 1,
  'Group retains exactly one active leader');
reset role;

select * from finish();
rollback;

begin;

select plan(9);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('c1000000-0000-4000-8000-000000000001', 'members-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('c2000000-0000-4000-8000-000000000002', 'members-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('c3000000-0000-4000-8000-000000000003', 'members-three@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

insert into public.friendships (user_a, user_b)
values
  ('c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000002'),
  ('c1000000-0000-4000-8000-000000000001','c3000000-0000-4000-8000-000000000003');

select set_config('test.members_two_code',
  (select friend_code from public.profiles where user_id='c2000000-0000-4000-8000-000000000002'), true);
select set_config('test.members_three_code',
  (select friend_code from public.profiles where user_id='c3000000-0000-4000-8000-000000000003'), true);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('test.members_group_id',
  public.create_group('Mitglieder Test', current_setting('test.members_two_code'))::text, true);

select is((select count(*)::integer from public.list_group_members(current_setting('test.members_group_id')::uuid)), 2,
  'Group member can see the active member list');
select is((select member_role from public.list_group_members(current_setting('test.members_group_id')::uuid)
  where member_role = 'deputy_leader'), 'deputy_leader',
  'Member list shows the deputy role');

select throws_ok(
  format('select public.leave_group(%L::uuid)', current_setting('test.members_group_id')),
  'P0001', 'Leader must transfer leadership before leaving',
  'Leader cannot leave before transferring leadership'
);

select set_config('test.members_invite_id',
  public.invite_friend_to_group(
    current_setting('test.members_group_id')::uuid,
    current_setting('test.members_three_code')
  )::text, true);
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c3000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select ok(public.respond_to_group_invite(current_setting('test.members_invite_id')::uuid, true),
  'Invitee can join the group');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c2000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select is((select count(*)::integer from public.list_group_members(current_setting('test.members_group_id')::uuid)), 3,
  'Deputy can see all three active members');
select ok(public.remove_group_member(
  current_setting('test.members_group_id')::uuid,
  current_setting('test.members_three_code')
), 'Deputy can remove a regular member');
select is((select count(*)::integer from public.list_group_members(current_setting('test.members_group_id')::uuid)), 2,
  'Removed member no longer appears in the member list');
select ok(public.leave_group(current_setting('test.members_group_id')::uuid),
  'Deputy can leave the group');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is((select count(*)::integer from public.list_group_members(current_setting('test.members_group_id')::uuid)), 1,
  'Former deputy is no longer in the active member list');
reset role;

select * from finish();
rollback;

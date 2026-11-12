begin;

select plan(10);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('b1000000-0000-4000-8000-000000000001', 'group-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('b2000000-0000-4000-8000-000000000002', 'group-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('b3000000-0000-4000-8000-000000000003', 'group-three@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

insert into public.friendships (user_a, user_b)
values
  ('b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000002'),
  ('b1000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000003');

select set_config('test.group_two_code',
  (select friend_code from public.profiles where user_id='b2000000-0000-4000-8000-000000000002'), true);
select set_config('test.group_three_code',
  (select friend_code from public.profiles where user_id='b3000000-0000-4000-8000-000000000003'), true);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"b1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select ok(
  public.create_group('Latein Lernteam', current_setting('test.group_two_code')) is not null,
  'A user can create a group with a confirmed friend as deputy'
);
select is((select count(*)::integer from public.list_my_groups()), 1,
  'Leader sees the newly created group');
select is((select my_role from public.list_my_groups()), 'leader',
  'Creator receives leader role');
select is((select member_count from public.list_my_groups()), 2,
  'Group starts with leader and deputy');

select throws_ok(
  $q$select public.create_group('Ohne Freund', 'ZZZZZZ')$q$,
  'P0001',
  'Deputy must be a different confirmed friend',
  'A non-friend cannot be appointed as deputy'
);

select ok(
  public.invite_friend_to_group(
    (select group_id from public.list_my_groups()),
    current_setting('test.group_three_code')
  ) is not null,
  'Leader can invite a confirmed friend by friend code'
);
select throws_ok(
  $q$select public.invite_friend_to_group(
    (select group_id from public.list_my_groups()), 'ZZZZZZ'
  )$q$,
  'P0001',
  'Invitee must be a different confirmed friend',
  'A non-friend cannot be invited'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"b3000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select is((select count(*)::integer from public.list_group_invites()), 1,
  'Invitee sees their pending group invitation');
select ok(
  public.respond_to_group_invite(
    (select invite_id from public.list_group_invites()), true
  ),
  'Invitee can accept their own invitation'
);
select is((select count(*)::integer from public.list_my_groups()), 1,
  'Accepted invitee becomes a group member');
reset role;

select * from finish();
rollback;

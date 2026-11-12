begin;

select plan(9);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('a1000000-0000-4000-8000-000000000001', 'sharing-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('a2000000-0000-4000-8000-000000000002', 'sharing-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('a3000000-0000-4000-8000-000000000003', 'sharing-three@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

update public.profiles set display_name = 'Freund A'
where user_id = 'a1000000-0000-4000-8000-000000000001';
update public.profiles set display_name = 'Freund B'
where user_id = 'a2000000-0000-4000-8000-000000000002';

insert into public.friendships (user_a, user_b)
values (
  'a1000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000002'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select share_level from public.profile_sharing
   where user_id = auth.uid()),
  false,
  'Profile sharing starts private by default'
);
select ok(
  public.update_my_profile_sharing(true, false, true, false),
  'A user can update their own sharing choices'
);
select ok(
  (select share_level and not share_xp and share_badges and not share_weekly_stats
   from public.profile_sharing where user_id = auth.uid()),
  'Only the selected sharing choices are enabled'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a2000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

select is(
  (select count(*)::integer from public.list_friend_sharing()),
  1,
  'A confirmed friend can see the sharing settings of their friend'
);
select is(
  (select display_name from public.list_friend_sharing()),
  'Freund A',
  'Friend sharing results contain the display name'
);
select ok(
  (select share_level and not share_xp and share_badges and not share_weekly_stats
   from public.list_friend_sharing()),
  'Friends see exactly the selected sharing preferences'
);
select ok(
  not has_table_privilege('authenticated', 'public.friendships', 'select'),
  'Direct friendship table access remains blocked'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a3000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select is(
  (select count(*)::integer from public.list_friend_sharing()),
  0,
  'A non-friend cannot see another profile sharing settings'
);
reset role;

select ok(
  not has_function_privilege(
    'anon',
    'public.update_my_profile_sharing(boolean,boolean,boolean,boolean)',
    'execute'
  ),
  'Anonymous users cannot change sharing settings'
);

select * from finish();
rollback;

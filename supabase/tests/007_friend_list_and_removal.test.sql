begin;

select plan(9);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('91000000-0000-4000-8000-000000000001', 'friends-list-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('92000000-0000-4000-8000-000000000002', 'friends-list-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('93000000-0000-4000-8000-000000000003', 'friends-list-three@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

update public.profiles set display_name = 'Gleichnamiges Lernkonto'
where user_id in (
  '91000000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000002'
);

insert into public.friendships (user_a, user_b)
values (
  '91000000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000002'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select count(*)::integer from public.list_friends()),
  1,
  'A user sees exactly their confirmed friend'
);
select is(
  (select display_name from public.list_friends()),
  'Gleichnamiges Lernkonto',
  'Friend list returns the display name'
);
select ok(
  (select friend_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$'
   from public.list_friends()),
  'Friend code distinguishes accounts with identical display names'
);
select ok(
  (select friends_since is not null from public.list_friends()),
  'Friend list includes the confirmation timestamp'
);
select ok(
  not has_table_privilege('authenticated', 'public.friendships', 'select'),
  'Clients cannot read the friendships table directly'
);
select throws_ok(
  $query$select public.remove_friend('93000000-0000-4000-8000-000000000003'::uuid)$query$,
  'P0001',
  'Friendship not found or not available to this account',
  'A user cannot remove an account that is not their friend'
);
select ok(
  public.remove_friend('92000000-0000-4000-8000-000000000002'),
  'A user can end their own friendship'
);
select is(
  (select count(*)::integer from public.list_friends()),
  0,
  'Removed friend disappears from the caller friend list'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select is(
  (select count(*)::integer from public.list_friends()),
  0,
  'Friendship removal also removes the relationship for the other account'
);
reset role;

select * from finish();
rollback;

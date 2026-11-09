begin;

select plan(8);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('30000000-0000-4000-8000-000000000003', 'friend-code-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('40000000-0000-4000-8000-000000000004', 'friend-code-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

update public.profiles set display_name = 'Lernkonto Alpha'
where user_id = '30000000-0000-4000-8000-000000000003';
update public.profiles set display_name = 'Lernkonto Beta'
where user_id = '40000000-0000-4000-8000-000000000004';

select ok(
  (select friend_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$'
   from public.profiles
   where user_id = '30000000-0000-4000-8000-000000000003'),
  'A six-character friend code is generated automatically'
);
select isnt(
  (select friend_code from public.profiles
   where user_id = '30000000-0000-4000-8000-000000000003'),
  (select friend_code from public.profiles
   where user_id = '40000000-0000-4000-8000-000000000004'),
  'Friend codes are unique'
);

select set_config(
  'test.friend_code_two',
  (select friend_code from public.profiles
   where user_id = '40000000-0000-4000-8000-000000000004'),
  true
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select is(
  (select count(*)::integer from public.search_profiles('Lernkonto')),
  1,
  'Name search returns other accounts but not the current account'
);
select is(
  (select display_name from public.search_profiles('Lernkonto')),
  'Lernkonto Beta',
  'Name search returns the matching display name'
);
select ok(
  (select friend_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$'
   from public.search_profiles('Lernkonto')),
  'Search result provides a public friend code, not an internal account ID'
);
select throws_ok(
  $query$select * from public.search_profiles('Le')$query$,
  'P0001',
  'Search query must contain at least 3 characters',
  'Very short search terms are rejected'
);
select is(
  public.send_friend_request_by_code(current_setting('test.friend_code_two')) is not null,
  true,
  'Friend request can be sent using the friend code'
);
select is(
  (select direction from public.list_friend_requests()),
  'outgoing',
  'Sender sees the outgoing request'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"40000000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);
select is(
  (select direction from public.list_friend_requests()),
  'incoming',
  'The recipient receives the request sent by friend code'
);
reset role;

select * from finish();
rollback;

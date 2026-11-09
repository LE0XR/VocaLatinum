begin;

select plan(14);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('10000000-0000-4000-8000-000000000001', 'friend-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('20000000-0000-4000-8000-000000000002', 'friend-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

update public.profiles set display_name = 'Lernkonto Eins'
where user_id = '10000000-0000-4000-8000-000000000001';
update public.profiles set display_name = 'Lernkonto Zwei'
where user_id = '20000000-0000-4000-8000-000000000002';

-- Konto 1 sendet eine Anfrage. Die Anfrage-ID bleibt nur in der Testsession.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'test.friend_request_id',
  public.send_friend_request('20000000-0000-4000-8000-000000000002')::text,
  true
);
select is(
  (select count(*)::integer from public.list_friend_requests()),
  1,
  'Sender sees exactly one outgoing request'
);
select is(
  (select direction from public.list_friend_requests()),
  'outgoing',
  'Sender sees request as outgoing'
);
select is(
  (select other_display_name from public.list_friend_requests()),
  'Lernkonto Zwei',
  'Request list exposes only the other display name, not profile details'
);

-- Absender darf die eigene Anfrage nicht annehmen.
select throws_ok(
  format('select public.accept_friend_request(%L::uuid)', current_setting('test.friend_request_id')),
  'P0001',
  'Only the recipient can accept this request',
  'Sender cannot accept their own outgoing request'
);

reset role;
select is(
  (select count(*)::integer from public.friend_requests where status = 'pending'),
  1,
  'Exactly one pending request is stored'
);

-- Konto 2 sieht die Anfrage als eingehend und darf sie annehmen.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select is(
  (select direction from public.list_friend_requests()),
  'incoming',
  'Recipient sees request as incoming'
);
select is(
  (select other_display_name from public.list_friend_requests()),
  'Lernkonto Eins',
  'Recipient sees sender display name'
);
select ok(
  public.accept_friend_request(current_setting('test.friend_request_id')::uuid),
  'Recipient can accept the request'
);
reset role;

select is(
  (select count(*)::integer from public.friendships),
  1,
  'Acceptance creates exactly one friendship'
);
select is(
  (select status from public.friend_requests
   where id = current_setting('test.friend_request_id')::uuid),
  'accepted',
  'Accepted request status is stored'
);
select ok(
  not has_table_privilege('authenticated', 'public.friend_requests', 'select'),
  'Clients cannot read friend request table directly'
);
select ok(
  has_function_privilege('authenticated', 'public.send_friend_request(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.accept_friend_request(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.reject_friend_request(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.list_friend_requests()', 'execute'),
  'Authenticated clients can execute only the approved friend request RPC entry points'
);

-- Neue Anfrage für den Ablehnungspfad: Test entfernt die zuvor bestätigte Beziehung.
delete from public.friendships;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'test.friend_request_id',
  public.send_friend_request('20000000-0000-4000-8000-000000000002')::text,
  true
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select ok(
  public.reject_friend_request(current_setting('test.friend_request_id')::uuid),
  'Recipient can reject the request'
);
select is(
  (select count(*)::integer from public.list_friend_requests()),
  0,
  'Rejected request is no longer listed as pending'
);
reset role;

select * from finish();
rollback;

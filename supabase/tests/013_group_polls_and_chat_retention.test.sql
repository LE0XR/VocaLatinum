begin;

select plan(8);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('f1000000-0000-4000-8000-000000000001', 'poll-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('f2000000-0000-4000-8000-000000000002', 'poll-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

insert into public.friendships (user_a, user_b)
values ('f1000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000002');

select set_config('test.poll_two_code',
  (select friend_code from public.profiles where user_id='f2000000-0000-4000-8000-000000000002'), true);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('test.poll_group_id',
  public.create_group('Umfrage Test', current_setting('test.poll_two_code'))::text, true);
select ok(public.set_group_chat_retention(current_setting('test.poll_group_id')::uuid, 30),
  'Leader can set chat retention');
select throws_ok(
  format('select public.set_group_chat_retention(%L::uuid, 500)',
    current_setting('test.poll_group_id')),
  'P0001', 'Retention must be between 1 and 365 days, or null for no automatic expiry',
  'Retention outside the allowed range is rejected'
);
select set_config('test.poll_id',
  public.create_group_poll(current_setting('test.poll_group_id')::uuid,
    'Wann lernen wir?', array['Heute', 'Morgen', 'Am Wochenende'])::text, true);
select is((select count(*)::integer from public.list_group_polls(
  current_setting('test.poll_group_id')::uuid)), 3,
  'Poll options are visible to group members');
select set_config('test.poll_option_id',
  (select option_id::text from public.list_group_polls(current_setting('test.poll_group_id')::uuid)
   where option_text = 'Morgen' limit 1), true);
select ok(public.vote_group_poll(current_setting('test.poll_id')::uuid,
  current_setting('test.poll_option_id')::uuid), 'Member can vote in a group poll');
select ok(public.vote_group_poll(current_setting('test.poll_id')::uuid,
  current_setting('test.poll_option_id')::uuid), 'A member can update their vote');
select ok(public.close_group_poll(current_setting('test.poll_id')::uuid),
  'Group leader can close a poll');
select throws_ok(
  format('select public.vote_group_poll(%L::uuid, %L::uuid)',
    current_setting('test.poll_id'), current_setting('test.poll_option_id')),
  'P0001', 'Poll or option not found, or poll is closed',
  'Closed poll no longer accepts votes'
);
reset role;

select * from finish();
rollback;

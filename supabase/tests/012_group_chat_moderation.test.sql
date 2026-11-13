begin;

select plan(8);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('e1000000-0000-4000-8000-000000000001', 'chat-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('e2000000-0000-4000-8000-000000000002', 'chat-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

insert into public.friendships (user_a, user_b)
values ('e1000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000002');

select set_config('test.chat_two_code',
  (select friend_code from public.profiles where user_id='e2000000-0000-4000-8000-000000000002'), true);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('test.chat_group_id',
  public.create_group('Chat Test', current_setting('test.chat_two_code'))::text, true);
select set_config('test.chat_message_id',
  public.send_group_message(current_setting('test.chat_group_id')::uuid, 'Hallo Gruppe')::text, true);
select is((select count(*)::integer from public.list_group_messages(current_setting('test.chat_group_id')::uuid)), 1,
  'Sender can read their group message');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e2000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select is((select count(*)::integer from public.list_group_messages(current_setting('test.chat_group_id')::uuid)), 1,
  'Deputy can read group messages');
select ok(public.report_group_message(current_setting('test.chat_message_id')::uuid, 'Bitte prüfen') is not null,
  'Member can report another member message');
select ok(public.block_group_member(
  current_setting('test.chat_group_id')::uuid,
  (select friend_code from public.profiles where user_id='e1000000-0000-4000-8000-000000000001')
), 'Member can block another group member in their own chat view');
select is((select count(*)::integer from public.list_group_messages(current_setting('test.chat_group_id')::uuid)), 0,
  'Blocked member messages are hidden from the blocker');
select ok(public.unblock_group_member(
  current_setting('test.chat_group_id')::uuid,
  (select friend_code from public.profiles where user_id='e1000000-0000-4000-8000-000000000001')
), 'Member can unblock a group member');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select ok(public.delete_group_message(current_setting('test.chat_message_id')::uuid),
  'Author can delete their own message');
select is((select count(*)::integer from public.list_group_messages(current_setting('test.chat_group_id')::uuid)), 0,
  'Deleted messages are not returned');
reset role;

select * from finish();
rollback;

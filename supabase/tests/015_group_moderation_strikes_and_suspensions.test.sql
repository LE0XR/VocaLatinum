begin;

select plan(10);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('a1000000-0000-4000-8000-000000000001', 'moderation-leader@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('a2000000-0000-4000-8000-000000000002', 'moderation-deputy@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('a3000000-0000-4000-8000-000000000003', 'moderation-member@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

insert into public.friendships (user_a, user_b) values
  ('a1000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000002'),
  ('a1000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000003');

select set_config('test.mod_deputy_code',
  (select friend_code from public.profiles where user_id='a2000000-0000-4000-8000-000000000002'), true);
select set_config('test.mod_member_code',
  (select friend_code from public.profiles where user_id='a3000000-0000-4000-8000-000000000003'), true);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('test.mod_group_id',
  public.create_group('Moderationstest', current_setting('test.mod_deputy_code'))::text, true);
select set_config('test.mod_invite_id',
  public.invite_friend_to_group(current_setting('test.mod_group_id')::uuid,
    current_setting('test.mod_member_code'))::text, true);
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a3000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select ok(public.respond_to_group_invite(current_setting('test.mod_invite_id')::uuid, true),
  'Invited member can join before any moderation action');
reset role;

set local role service_role;
select is(public.record_group_moderation_violation(
  current_setting('test.mod_group_id')::uuid,
  'a3000000-0000-4000-8000-000000000003',
  'Beleidigung'), 'reminder', 'First violation creates a reminder');
select is(public.record_group_moderation_violation(
  current_setting('test.mod_group_id')::uuid,
  'a3000000-0000-4000-8000-000000000003',
  'Beleidigung'), 'warning', 'Second violation creates a warning');
select is(public.record_group_moderation_violation(
  current_setting('test.mod_group_id')::uuid,
  'a3000000-0000-4000-8000-000000000003',
  'Belästigung'), 'suspension', 'Third violation creates a suspension');
select is((select count(*)::integer from public.group_member_moderation_events
  where group_id=current_setting('test.mod_group_id')::uuid
    and user_id='a3000000-0000-4000-8000-000000000003'), 3,
  'Violations are counted across dates in the group history');
select ok((select left_at is not null from public.group_members
  where group_id=current_setting('test.mod_group_id')::uuid
    and user_id='a3000000-0000-4000-8000-000000000003'),
  'Third violation removes the member from active membership');
select ok((select suspended_until > now() + interval '2 days'
  and suspended_until <= now() + interval '3 days'
  from public.group_member_suspensions
  where group_id=current_setting('test.mod_group_id')::uuid
    and user_id='a3000000-0000-4000-8000-000000000003'),
  'Suspension lasts three days');
select throws_ok(
  $$select public.record_group_moderation_violation(
    current_setting('test.mod_group_id')::uuid,
    'a3000000-0000-4000-8000-000000000003',
    'Spam')$$,
  'P0001', 'Active ordinary group member required',
  'A suspended former member cannot accumulate new group strikes'
);
reset role;

update public.group_member_suspensions
set suspended_at = now() - interval '3 days',
    suspended_until = now() - interval '1 minute'
where group_id=current_setting('test.mod_group_id')::uuid
  and user_id='a3000000-0000-4000-8000-000000000003';

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select ok(public.reinstate_suspended_group_member(
  current_setting('test.mod_group_id')::uuid,
  current_setting('test.mod_member_code')),
  'Group leader can reinstate the member after the three-day period');
select ok((select left_at is null from public.group_members
  where group_id=current_setting('test.mod_group_id')::uuid
    and user_id='a3000000-0000-4000-8000-000000000003'),
  'Reinstated member is active again');
reset role;

select * from finish();
rollback;

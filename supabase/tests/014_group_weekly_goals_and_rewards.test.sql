begin;
select plan(12);

insert into auth.users (
  id, email, aud, role, email_confirmed_at, raw_app_meta_data, raw_user_meta_data
) values
  ('a1000000-0000-4000-8000-000000000001', 'goal-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('a2000000-0000-4000-8000-000000000002', 'goal-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('a3000000-0000-4000-8000-000000000003', 'goal-three@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

insert into public.friendships(user_a,user_b) values
 ('a1000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000002');

select set_config('test.goal_two_code',
 (select friend_code from public.profiles where user_id='a2000000-0000-4000-8000-000000000002'), true);

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('test.goal_group_id',
 public.create_group('Wochenziel', current_setting('test.goal_two_code'))::text, true);

select ok(public.set_group_weekly_goal(
 current_setting('test.goal_group_id')::uuid, 500, 'xp_bonus', 400) is not null,
 'Leader can configure a weekly goal and an allowed XP reward');

select is((select count(*)::integer from public.list_group_weekly_goal(
 current_setting('test.goal_group_id')::uuid)), 1,
 'Active group members can view the weekly goal');

select throws_ok(
 format('select public.set_group_weekly_goal(%L::uuid, 500, %L, 250)',
 current_setting('test.goal_group_id'), 'xp_bonus'),
 'P0001', 'Invalid group reward selection',
 'Unsupported reward amounts are rejected');

select throws_ok(
 format('select public.record_group_learning_event(%L::uuid,%L::uuid,%L::uuid,100)',
 'a9000000-0000-4000-8000-000000000009',
 current_setting('test.goal_group_id'),
 'a1000000-0000-4000-8000-000000000001'),
 '42501', null,
 'Authenticated clients cannot submit their own XP events');

select throws_ok(
 format('select public.award_group_weekly_goal(%L::uuid)',
 current_setting('test.goal_group_id')),
 '42501', null,
 'Authenticated clients cannot grant rewards');

select ok(exists(select 1 from public.list_group_weekly_goal(
 current_setting('test.goal_group_id')::uuid)),
 'Goal status can be queried without exposing private account IDs');

select throws_ok(
 format('select public.set_group_weekly_goal(%L::uuid, 0, %L, 400)',
 current_setting('test.goal_group_id'), 'xp_bonus'),
 'P0001', 'Weekly XP target must be between 1 and 1000000',
 'Invalid XP targets are rejected');

reset role;

-- Nur ein aktiver Gruppenbeitraeger sammelt 500 XP; der Stellvertreter bleibt ohne Beitrag.
set local role service_role;
select ok(public.record_group_learning_event(
 'a9000000-0000-4000-8000-000000000009',
 current_setting('test.goal_group_id')::uuid,
 'a1000000-0000-4000-8000-000000000001',
 500), 'Trusted backend can record a verified learning event');

select throws_ok(
 format('select public.record_group_learning_event(%L::uuid,%L::uuid,%L::uuid,500)',
 'a9000000-0000-4000-8000-000000000009',
 current_setting('test.goal_group_id'),
 'a1000000-0000-4000-8000-000000000001'),
 'P0001', 'Learning event was already recorded',
 'Duplicate learning events cannot add XP twice');

select is(public.award_group_weekly_goal(
 current_setting('test.goal_group_id')::uuid), 1,
 'Only the member who contributed receives a reward');

select is((select count(*)::integer from public.user_group_reward_grants), 1,
 'Exactly one reward grant is created for the contributor');

select ok(not exists(
 select 1 from public.user_group_reward_grants
 where user_id = 'a2000000-0000-4000-8000-000000000002'),
 'A group member without a contribution receives no reward');

reset role;
select * from finish();
rollback;

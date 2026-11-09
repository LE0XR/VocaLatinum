begin;

select plan(2);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
)
select
  ('70000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'request-limit-' || n::text || '@example.invalid',
  'authenticated', 'authenticated', now(),
  '{"provider":"email","providers":["email"]}', '{}'
from generate_series(1, 11) as n;

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values (
  '80000000-0000-4000-8000-000000000008',
  'request-sender@example.invalid',
  'authenticated', 'authenticated', now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"80000000-0000-4000-8000-000000000008","role":"authenticated"}',
  true
);

do $$
declare
  v_attempt integer;
  v_recipient_id uuid;
begin
  for v_attempt in 1..10 loop
    v_recipient_id := (
      '70000000-0000-4000-8000-' || lpad(v_attempt::text, 12, '0')
    )::uuid;
    perform public.send_friend_request(v_recipient_id);
  end loop;
end;
$$;

select throws_ok(
  $query$select public.send_friend_request('70000000-0000-4000-8000-000000000011'::uuid)$query$,
  'P0001',
  'Friend request rate limit exceeded; try again later',
  'The 11th outgoing friend request within one hour is rejected'
);

reset role;

select is(
  (select request_count from private.friend_request_rate_limits
   where user_id = '80000000-0000-4000-8000-000000000008'),
  10,
  'Rejected attempt does not increase the committed server-side counter'
);

select * from finish();
rollback;

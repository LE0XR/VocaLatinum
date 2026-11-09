begin;

select plan(2);

insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('50000000-0000-4000-8000-000000000005', 'search-limit@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('60000000-0000-4000-8000-000000000006', 'search-target@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

update public.profiles set display_name = 'Search Limit Target'
where user_id = '60000000-0000-4000-8000-000000000006';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"50000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

do $$
declare
  v_attempt integer;
begin
  for v_attempt in 1..20 loop
    perform * from public.search_profiles('Search');
  end loop;
end;
$$;

select throws_ok(
  $query$select * from public.search_profiles('Search')$query$,
  'P0001',
  'Search rate limit exceeded; try again later',
  'The 21st profile search in a ten-minute window is rejected'
);

reset role;

select ok(
  not private.consume_profile_search_limit(),
  'Rate-limit state is maintained server-side for the authenticated account'
);

select * from finish();
rollback;

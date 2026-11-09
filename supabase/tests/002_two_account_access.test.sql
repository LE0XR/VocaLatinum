begin;

select plan(8);

-- Zwei künstliche Testkonten ohne echte E-Mail-Adressen oder persönliche Daten.
insert into auth.users (
  id, email, aud, role, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('10000000-0000-4000-8000-000000000001', 'rls-user-one@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('20000000-0000-4000-8000-000000000002', 'rls-user-two@example.invalid',
   'authenticated', 'authenticated', now(), '{"provider":"email","providers":["email"]}', '{}');

update public.profiles
set display_name = 'Lernkonto Eins'
where user_id = '10000000-0000-4000-8000-000000000001';

update public.profiles
set display_name = 'Lernkonto Zwei'
where user_id = '20000000-0000-4000-8000-000000000002';

-- Konto 1 sieht ausschließlich das eigene Profil.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select count(*)::integer from public.profiles),
  1,
  'Account one sees exactly one profile row'
);
select is(
  (select display_name from public.profiles limit 1),
  'Lernkonto Eins',
  'Account one sees its own display name'
);
select is(
  (select count(*)::integer from public.profile_sharing),
  1,
  'Account one sees exactly its own privacy settings'
);

-- Konto 1 kann das eigene Profil ändern, aber Konto 2 nicht.
update public.profiles
set display_name = 'Eins aktualisiert'
where user_id = '10000000-0000-4000-8000-000000000001';

select is(
  (select display_name from public.profiles
   where user_id = '10000000-0000-4000-8000-000000000001'),
  'Eins aktualisiert',
  'Account one can update its own display name'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

select is(
  (select count(*)::integer from public.profiles),
  1,
  'Account two sees exactly one profile row'
);
select is(
  (select display_name from public.profiles limit 1),
  'Lernkonto Zwei',
  'Account two sees its own display name, not account one'
);
select is(
  (select count(*)::integer from public.profile_sharing),
  1,
  'Account two sees exactly its own privacy settings'
);

reset role;
select is(
  (select display_name from public.profiles
   where user_id = '20000000-0000-4000-8000-000000000002'),
  'Lernkonto Zwei',
  'Account one did not change account two display name'
);

select * from finish();
rollback;

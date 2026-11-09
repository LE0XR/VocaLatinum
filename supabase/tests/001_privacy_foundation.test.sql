begin;

select plan(18);

select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'profiles'),
  'RLS is enabled on profiles'
);
select ok(
  (select c.relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'profiles'),
  'RLS is forced on profiles'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'profile_sharing'),
  'RLS is enabled on profile_sharing'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'friend_requests'),
  'RLS is enabled on friend_requests'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'friendships'),
  'RLS is enabled on friendships'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'groups'),
  'RLS is enabled on groups'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'group_members'),
  'RLS is enabled on group_members'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'group_invites'),
  'RLS is enabled on group_invites'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'group_settings'),
  'RLS is enabled on group_settings'
);

select ok(has_table_privilege('authenticated', 'public.profiles', 'select'),
  'Authenticated users can read the profiles table subject to RLS');
select ok(has_column_privilege('authenticated', 'public.profiles', 'display_name', 'update'),
  'Authenticated users can update the display name subject to RLS');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'user_id', 'update'),
  'Authenticated users cannot change profile ownership');
select ok(has_table_privilege('authenticated', 'public.profile_sharing', 'select'),
  'Authenticated users can read their sharing settings subject to RLS');
select ok(not has_table_privilege('anon', 'public.profiles', 'select'),
  'Anonymous users cannot read profiles');
select ok(not has_table_privilege('anon', 'public.profile_sharing', 'select'),
  'Anonymous users cannot read privacy settings');

select ok(not has_table_privilege('authenticated', 'public.friend_requests', 'select'),
  'Friend request rows are not exposed directly to clients yet');
select ok(not has_table_privilege('authenticated', 'public.group_members', 'select'),
  'Group membership UUIDs are not exposed directly to clients yet');
select ok(to_regclass('public.group_messages') is null,
  'The group chat table is intentionally not created in this initial migration');

select * from finish();
rollback;

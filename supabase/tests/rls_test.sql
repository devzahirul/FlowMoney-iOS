-- pgTAP tests for Row Level Security and schema rules. Run with `supabase test db` (CI does this on every push).
begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

-- Two users.
insert into auth.users (id, email, raw_user_meta_data)
values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'alice@example.com', '{"display_name":"Alice"}'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'bob@example.com', '{}');

select is(
  (select display_name from flowmoney.profiles where id = 'aaaaaaaa-0000-4000-8000-000000000001'),
  'Alice',
  'sign-up creates a profile with the metadata name'
);

-- Act as Alice.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}', true);

insert into flowmoney.accounts (id, name, kind) values ('a1111111-0000-4000-8000-000000000001', 'Checking', 'checking');
insert into flowmoney.transactions (id, account_id, kind, amount, category_id, occurred_at)
values ('a2222222-0000-4000-8000-000000000001', 'a1111111-0000-4000-8000-000000000001', 'expense', 520, 'food', now());

select is((select user_id from flowmoney.accounts limit 1), 'aaaaaaaa-0000-4000-8000-000000000001'::uuid, 'user_id defaults to auth.uid()');
select is((select count(*)::int from flowmoney.transactions), 1, 'owner sees own transaction');

select throws_ok(
  $$ insert into flowmoney.transactions (id, account_id, kind, amount, category_id, occurred_at)
     values (gen_random_uuid(), 'a1111111-0000-4000-8000-000000000001', 'expense', 0, 'food', now()) $$,
  '23514', null, 'amount must be positive'
);

select throws_ok(
  $$ insert into flowmoney.accounts (id, user_id, name, kind)
     values (gen_random_uuid(), 'bbbbbbbb-0000-4000-8000-000000000002', 'Sneaky', 'cash') $$,
  '42501', null, 'cannot insert a row owned by someone else'
);

-- Updating updated_at from the client is ignored: the server stamps it.
update flowmoney.transactions set updated_at = '2000-01-01', merchant = 'Starbucks' where id = 'a2222222-0000-4000-8000-000000000001';
select ok((select updated_at > now() - interval '1 minute' from flowmoney.transactions), 'server owns updated_at');

select throws_ok(
  $$ delete from flowmoney.transactions $$,
  '42501', null, 'clients cannot hard-delete (soft delete only)'
);

insert into flowmoney.budgets (id, category_id, limit_amount) values (gen_random_uuid(), 'food', 50000);
select throws_ok(
  $$ insert into flowmoney.budgets (id, category_id, limit_amount) values (gen_random_uuid(), 'food', 60000) $$,
  '23505', null, 'one live budget per category'
);

-- Act as Bob.
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-4000-8000-000000000002","role":"authenticated"}', true);

select is((select count(*)::int from flowmoney.transactions), 0, 'other users see nothing');
select is((select count(*)::int from flowmoney.accounts), 0, 'other users see no accounts');

update flowmoney.transactions set merchant = 'hacked';
reset role;
select is((select merchant from flowmoney.transactions), 'Starbucks', 'other users cannot update');
set local role authenticated;

select throws_ok(
  $$ insert into flowmoney.transactions (id, account_id, kind, amount, category_id, occurred_at)
     values (gen_random_uuid(), 'a1111111-0000-4000-8000-000000000001', 'expense', 100, 'food', now()) $$,
  '23503', null, 'cannot attach a transaction to another user''s account'
);

-- Anonymous clients get nothing.
set local role anon;
select throws_ok($$ select * from flowmoney.transactions $$, '42501', null, 'anon has no table access');

-- Account deletion cascades.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}', true);
select flowmoney.delete_my_account();
reset role;
select is((select count(*)::int from flowmoney.transactions), 0, 'delete_my_account removes all data');

select * from finish();
rollback;

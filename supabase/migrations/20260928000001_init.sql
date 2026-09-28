-- FlowMoney schema.
--
-- Everything lives in its own Postgres schema `flowmoney`, so FlowMoney can share a Supabase project with other
-- apps (it runs alongside NovaShop) without any name collisions. Add `flowmoney` to
-- Project Settings → API → Exposed schemas so PostgREST serves it.
--
-- Design rules (see docs/adr/0002-offline-first-sync.md):
--   * Primary keys are client-generated UUIDs → rows can be created offline and upserted idempotently.
--   * `updated_at` is stamped by the server (trigger) → the pull cursor is never fooled by device clocks.
--   * Deletes are soft (`deleted_at`) → deletions reach other devices through the same "changed since" pull.
--   * Money is `bigint` minor units (cents) → exact, no floating point.
--   * Every table is protected by Row Level Security; `user_id` defaults to `auth.uid()` and can't be changed.

create schema if not exists flowmoney;
grant usage on schema flowmoney to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------
-- Shared trigger: server-owned timestamps and immutable ownership.
-- ---------------------------------------------------------------------------------------------------------
create or replace function flowmoney.stamp_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  if tg_op = 'UPDATE' then
    new.created_at := old.created_at;
    if to_jsonb(new) ? 'user_id' then
      new.user_id := old.user_id;
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------------------------------------
create table flowmoney.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null default '' check (char_length(display_name) <= 80),
  currency_code text not null default 'USD' check (currency_code ~ '^[A-Z]{3}$'),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

-- ---------------------------------------------------------------------------------------------------------
-- accounts
-- ---------------------------------------------------------------------------------------------------------
create table flowmoney.accounts (
  id              uuid primary key,
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name            text not null check (char_length(name) between 1 and 60),
  kind            text not null check (kind in ('checking', 'savings', 'cash', 'investment', 'property', 'credit_card', 'loan')),
  institution     text not null default '' check (char_length(institution) <= 60),
  last_four       text check (last_four ~ '^[0-9]{4}$'),
  opening_balance bigint not null default 0,
  sort_order      integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  -- Lets child tables use a composite FK so a row can only reference the *same user's* account.
  unique (id, user_id)
);

-- ---------------------------------------------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------------------------------------------
create table flowmoney.transactions (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  account_id        uuid not null,
  kind              text not null check (kind in ('expense', 'income')),
  amount            bigint not null check (amount > 0 and amount <= 100000000000),
  category_id       text not null check (char_length(category_id) between 1 and 40),
  merchant          text not null default '' check (char_length(merchant) <= 120),
  note              text not null default '' check (char_length(note) <= 500),
  occurred_at       timestamptz not null,
  -- No FK: a posted occurrence outlives the rule that created it.
  recurring_rule_id uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  foreign key (account_id, user_id) references flowmoney.accounts (id, user_id) on delete cascade
);

-- ---------------------------------------------------------------------------------------------------------
-- budgets (monthly limit per category)
-- ---------------------------------------------------------------------------------------------------------
create table flowmoney.budgets (
  id           uuid primary key,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  category_id  text not null check (char_length(category_id) between 1 and 40),
  limit_amount bigint not null check (limit_amount > 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

-- One *live* budget per category; deleted ones don't count.
create unique index budgets_one_live_per_category on flowmoney.budgets (user_id, category_id) where deleted_at is null;

-- ---------------------------------------------------------------------------------------------------------
-- goals + contributions
-- ---------------------------------------------------------------------------------------------------------
create table flowmoney.goals (
  id                   uuid primary key,
  user_id              uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name                 text not null check (char_length(name) between 1 and 60),
  symbol               text not null default 'other' check (char_length(symbol) <= 20),
  target               bigint not null check (target > 0),
  target_date          timestamptz,
  monthly_contribution bigint not null default 0 check (monthly_contribution >= 0),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  unique (id, user_id)
);

-- Rows, not a `saved` counter: two devices adding money at once must both count.
create table flowmoney.goal_contributions (
  id             uuid primary key,
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  goal_id        uuid not null,
  amount         bigint not null check (amount <> 0),
  contributed_at timestamptz not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  foreign key (goal_id, user_id) references flowmoney.goals (id, user_id) on delete cascade
);

-- ---------------------------------------------------------------------------------------------------------
-- recurring rules (bills, subscriptions, paychecks)
-- ---------------------------------------------------------------------------------------------------------
create table flowmoney.recurring_rules (
  id              uuid primary key,
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  account_id      uuid not null,
  name            text not null check (char_length(name) between 1 and 60),
  kind            text not null check (kind in ('expense', 'income')),
  amount          bigint not null check (amount > 0),
  category_id     text not null check (char_length(category_id) between 1 and 40),
  frequency       text not null check (frequency in ('weekly', 'monthly', 'quarterly', 'yearly')),
  start_date      timestamptz not null,
  is_subscription boolean not null default false,
  auto_post       boolean not null default true,
  is_paused       boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  foreign key (account_id, user_id) references flowmoney.accounts (id, user_id) on delete cascade
);

-- ---------------------------------------------------------------------------------------------------------
-- Triggers, indexes, Row Level Security — identical for every synced table.
-- ---------------------------------------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['profiles', 'accounts', 'transactions', 'budgets', 'goals', 'goal_contributions', 'recurring_rules']
  loop
    execute format('create trigger stamp_row before insert or update on flowmoney.%I for each row execute function flowmoney.stamp_row()', t);
    execute format('alter table flowmoney.%I enable row level security', t);
    -- Supabase's default privileges grant ALL (incl. DELETE/TRUNCATE) to API roles: start from nothing.
    execute format('revoke all on flowmoney.%I from anon, authenticated', t);
    execute format('grant select, insert, update on flowmoney.%I to authenticated', t);
  end loop;

  -- Sync pulls filter on (owner, updated_at): one index per table keeps them index-only range scans.
  foreach t in array array['accounts', 'transactions', 'budgets', 'goals', 'goal_contributions', 'recurring_rules']
  loop
    execute format('create index %I on flowmoney.%I (user_id, updated_at)', t || '_sync_idx', t);
    -- `(select auth.uid())` is evaluated once per statement instead of once per row.
    execute format('create policy "owner can read" on flowmoney.%I for select to authenticated using (user_id = (select auth.uid()))', t);
    execute format('create policy "owner can insert" on flowmoney.%I for insert to authenticated with check (user_id = (select auth.uid()))', t);
    execute format('create policy "owner can update" on flowmoney.%I for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
  end loop;
end;
$$;

create index profiles_sync_idx on flowmoney.profiles (id, updated_at);
create index transactions_by_date on flowmoney.transactions (user_id, occurred_at desc) where deleted_at is null;

create policy "owner can read" on flowmoney.profiles for select to authenticated using (id = (select auth.uid()));
create policy "owner can insert" on flowmoney.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy "owner can update" on flowmoney.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- No DELETE grants or policies at all: clients soft-delete. Hard deletes only happen through
-- `delete_my_account()` (cascade) or the tombstone purge job.

-- ---------------------------------------------------------------------------------------------------------
-- New users get a profile row automatically (name comes from sign-up metadata).
-- ---------------------------------------------------------------------------------------------------------
create or replace function flowmoney.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The auth user table is shared with other apps in this project (NovaShop): never let a FlowMoney
  -- problem block their sign-ups. The app also creates the profile row itself if it's missing.
  begin
    insert into flowmoney.profiles (id, display_name)
    values (new.id, left(coalesce(new.raw_user_meta_data ->> 'display_name', ''), 80))
    on conflict (id) do nothing;
  exception when others then
    raise warning 'flowmoney.handle_new_user skipped: %', sqlerrm;
  end;
  return new;
end;
$$;

-- Existing users of the shared project (e.g. NovaShop accounts) get a FlowMoney profile too. Read-only on auth.users.
insert into flowmoney.profiles (id, display_name)
select id, left(coalesce(raw_user_meta_data ->> 'display_name', ''), 80) from auth.users
on conflict (id) do nothing;

create trigger on_auth_user_created_flowmoney
  after insert on auth.users
  for each row execute function flowmoney.handle_new_user();

-- ---------------------------------------------------------------------------------------------------------
-- Account deletion (App Store guideline 5.1.1(v)): removes every FlowMoney row for the caller.
-- The login itself (auth.users) is shared with other apps in this project, so it is NOT deleted here —
-- deleting it would cascade into their data. A standalone FlowMoney project could delete the auth user instead.
-- ---------------------------------------------------------------------------------------------------------
create or replace function flowmoney.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from flowmoney.goal_contributions where user_id = uid;
  delete from flowmoney.transactions where user_id = uid;
  delete from flowmoney.recurring_rules where user_id = uid;
  delete from flowmoney.budgets where user_id = uid;
  delete from flowmoney.goals where user_id = uid;
  delete from flowmoney.accounts where user_id = uid;
  delete from flowmoney.profiles where id = uid;
end;
$$;

revoke all on function flowmoney.delete_my_account() from public, anon;
grant execute on function flowmoney.delete_my_account() to authenticated;

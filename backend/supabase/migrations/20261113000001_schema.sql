-- akwe — core schema
-- Conventions:
--   * amounts are numeric(14,2) in the account's own currency
--   * transaction.amount is SIGNED from the user's point of view: negative = money out, positive = money in
--     (Plaid uses the opposite sign; the sync function flips it)
--   * every user-owned row carries user_id and is protected by RLS (see 0002)

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.pay_frequency as enum ('weekly', 'biweekly', 'semimonthly', 'monthly');
create type public.item_status as enum ('ok', 'login_required', 'pending_expiration', 'error', 'revoked');
create type public.card_kind as enum ('debit', 'credit', 'deferred');
create type public.payment_method as enum ('debit_card', 'credit_card', 'deferred_card', 'direct_debit', 'transfer', 'atm', 'check', 'other');
create type public.tx_kind as enum ('spend', 'income', 'transfer', 'card_payment', 'card_settlement', 'refund');
create type public.category_source as enum ('plaid', 'rule', 'user', 'default');
create type public.budget_period as enum ('pay_period', 'month');
create type public.goal_funding as enum ('account', 'earmark', 'manual');
create type public.appearance as enum ('system', 'light', 'dark');

-- ---------------------------------------------------------------------------
-- Profiles & settings
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  display_currency text not null default 'USD' check (display_currency ~ '^[A-Z]{3}$'),
  appearance public.appearance not null default 'system',
  country_codes text[] not null default array['US', 'CA', 'FR'],
  onboarded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.pay_schedules (
  user_id uuid primary key references auth.users (id) on delete cascade,
  frequency public.pay_frequency not null default 'monthly',
  anchor_date date not null default date_trunc('month', now())::date, -- any known payday
  semimonthly_days int[] not null default array[1, 15],
  income_source text,           -- e.g. "ACME CORP PAYROLL"
  typical_amount numeric(14, 2),
  detected boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.notification_prefs (
  user_id uuid primary key references auth.users (id) on delete cascade,
  goal_reached boolean not null default true,
  goal_milestones boolean not null default true,
  budget_warning boolean not null default true,
  budget_exceeded boolean not null default true,
  bills_due boolean not null default true,
  payday_summary boolean not null default true,
  reauth boolean not null default true
);

create table public.device_tokens (
  token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  environment text not null default 'production' check (environment in ('sandbox', 'production')),
  locale text,
  updated_at timestamptz not null default now()
);
create index on public.device_tokens (user_id);

-- ---------------------------------------------------------------------------
-- Banks
-- ---------------------------------------------------------------------------
create table public.bank_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plaid_item_id text not null unique,
  institution_id text,
  institution_name text not null,
  country text,
  status public.item_status not null default 'ok',
  error_code text,
  last_synced_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.bank_items (user_id);

-- secrets: RLS enabled with NO policies + grants revoked → only the service role (edge functions) can read them
create table public.plaid_secrets (
  item_id uuid primary key references public.bank_items (id) on delete cascade,
  access_token text not null,
  sync_cursor text
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  item_id uuid not null references public.bank_items (id) on delete cascade,
  plaid_account_id text not null unique,
  name text not null,
  official_name text,
  nickname text,
  mask text,
  type text not null,            -- depository | credit | loan | investment | other
  subtype text,                  -- checking | savings | credit card | ...
  currency text not null default 'USD',
  current_balance numeric(14, 2),
  available_balance numeric(14, 2),
  credit_limit numeric(14, 2),
  card_kind public.card_kind,    -- inferred (credit for credit cards, debit for checking) or set by the user (deferred)
  include_in_totals boolean not null default true,
  color text,
  sort int not null default 0,
  updated_at timestamptz not null default now()
);
create index on public.accounts (user_id);

-- ---------------------------------------------------------------------------
-- Pockets & categories
-- ---------------------------------------------------------------------------
create table public.pockets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  key text,                      -- stable key for defaults ("food"), null for user-made
  name text not null,
  icon text not null default 'circle',
  color text not null default '#8B8B96',
  is_income boolean not null default false,
  sort int not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, key)
);
create index on public.pockets (user_id);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  pocket_id uuid not null references public.pockets (id) on delete restrict,
  key text,
  name text not null,
  icon text not null default 'circle',
  pfc_match text[] not null default '{}',   -- Plaid personal_finance_category prefixes this category absorbs
  sort int not null default 0,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  unique (user_id, key)
);
create index on public.categories (user_id);
create index on public.categories (pocket_id);

-- ---------------------------------------------------------------------------
-- Transactions
-- ---------------------------------------------------------------------------
create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  plaid_transaction_id text unique,
  pending boolean not null default false,
  pending_transaction_id text,
  amount numeric(14, 2) not null,           -- signed, user's POV
  currency text not null,
  date date not null,
  authorized_date date,
  raw_name text not null,                   -- bank label as received
  merchant_name text,                       -- cleaned / renamed
  logo_url text,
  pfc_primary text,
  pfc_detailed text,
  payment_channel text,                     -- online | in store | other
  payment_method public.payment_method not null default 'other',
  kind public.tx_kind not null default 'spend',
  category_id uuid references public.categories (id) on delete set null,
  category_source public.category_source not null default 'default',
  needs_review boolean not null default false,
  transfer_pair_id uuid references public.transactions (id) on delete set null,
  excluded boolean not null default false,  -- user: don't count in stats
  note text,
  tags text[] not null default '{}',
  split_parent_id uuid references public.transactions (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.transactions (user_id, date desc);
create index on public.transactions (account_id, date desc);
create index on public.transactions (user_id, needs_review) where needs_review;

-- user rules: "always put <merchant> in <category>"
create table public.rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  merchant_key text not null,               -- normalized merchant (see _shared/normalize.ts)
  account_id uuid references public.accounts (id) on delete cascade,
  category_id uuid not null references public.categories (id) on delete cascade,
  rename_to text,
  created_at timestamptz not null default now(),
  unique (user_id, merchant_key, account_id)
);

-- recurring streams (Plaid /transactions/recurring/get)
create table public.recurring_streams (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  plaid_stream_id text not null unique,
  direction text not null check (direction in ('inflow', 'outflow')),
  description text not null,
  merchant_name text,
  frequency text not null,
  average_amount numeric(14, 2) not null,
  last_amount numeric(14, 2) not null,
  previous_amount numeric(14, 2),
  currency text not null,
  last_date date,
  predicted_next_date date,
  is_active boolean not null default true,
  category_id uuid references public.categories (id) on delete set null,
  updated_at timestamptz not null default now()
);
create index on public.recurring_streams (user_id);

-- ---------------------------------------------------------------------------
-- Budgets
-- ---------------------------------------------------------------------------
create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  pocket_id uuid references public.pockets (id) on delete cascade,
  category_id uuid references public.categories (id) on delete cascade,
  amount numeric(14, 2) not null check (amount > 0),
  currency text not null,
  period public.budget_period not null default 'pay_period',
  created_at timestamptz not null default now(),
  check ((pocket_id is null) <> (category_id is null))
);
create unique index on public.budgets (user_id, coalesce(pocket_id, category_id));

-- ---------------------------------------------------------------------------
-- Goals (personal and shared)
-- ---------------------------------------------------------------------------
create table public.goals (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  icon text not null default 'target',
  color text not null default '#7C9CFF',
  target_amount numeric(14, 2) not null check (target_amount > 0),
  currency text not null,
  target_date date,
  reached_at timestamptz,
  last_milestone int not null default 0,     -- 0, 25, 50, 75, 100
  archived_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.goals (owner_id);

-- one row per participant (the owner too). Each participant funds their own share.
create table public.goal_members (
  goal_id uuid not null references public.goals (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'partner')),
  display_name text,
  funding public.goal_funding not null default 'manual',
  account_id uuid references public.accounts (id) on delete set null,
  earmark_amount numeric(14, 2),
  current_amount numeric(14, 2) not null default 0,  -- maintained by the server, in goal currency
  share_amount_visible boolean not null default true,
  share_activity boolean not null default true,
  joined_at timestamptz not null default now(),
  primary key (goal_id, user_id)
);
create index on public.goal_members (user_id);

create table public.goal_events (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references public.goals (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('contribution', 'withdrawal', 'milestone', 'reached', 'joined', 'cheer')),
  amount numeric(14, 2),
  note text,
  created_at timestamptz not null default now()
);
create index on public.goal_events (goal_id, created_at desc);

create table public.goal_invites (
  code text primary key default translate(encode(extensions.gen_random_bytes(9), 'base64'), '+/', '-_'),
  goal_id uuid not null references public.goals (id) on delete cascade,
  created_by uuid not null references auth.users (id) on delete cascade,
  share_amount_visible boolean not null default true,
  share_activity boolean not null default true,
  expires_at timestamptz not null default now() + interval '7 days',
  accepted_by uuid references auth.users (id) on delete set null,
  accepted_at timestamptz
);

-- ---------------------------------------------------------------------------
-- FX & notifications bookkeeping
-- ---------------------------------------------------------------------------
create table public.fx_rates (
  date date not null,
  quote text not null,          -- rate = units of `quote` per 1 EUR
  rate numeric(18, 8) not null,
  primary key (date, quote)
);

create table public.notification_log (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  ref text not null,            -- budget id / goal id / stream id
  period_key text not null,     -- e.g. 2026-11-07 (period start) or milestone value
  sent_at timestamptz not null default now(),
  unique (user_id, kind, ref, period_key)
);

-- ---------------------------------------------------------------------------
-- updated_at helper
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();
create trigger accounts_touch before update on public.accounts for each row execute function public.touch_updated_at();
create trigger transactions_touch before update on public.transactions for each row execute function public.touch_updated_at();
create trigger pay_schedules_touch before update on public.pay_schedules for each row execute function public.touch_updated_at();

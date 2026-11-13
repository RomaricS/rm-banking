-- akwe — row level security
-- Every table is locked down; the app (role "authenticated") only sees its own rows.
-- Edge functions use the service role and bypass RLS.

alter table public.profiles enable row level security;
alter table public.pay_schedules enable row level security;
alter table public.notification_prefs enable row level security;
alter table public.device_tokens enable row level security;
alter table public.bank_items enable row level security;
alter table public.accounts enable row level security;
alter table public.pockets enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.rules enable row level security;
alter table public.recurring_streams enable row level security;
alter table public.budgets enable row level security;
alter table public.goals enable row level security;
alter table public.goal_members enable row level security;
alter table public.goal_events enable row level security;
alter table public.goal_invites enable row level security;
alter table public.fx_rates enable row level security;
alter table public.notification_log enable row level security;
alter table public.plaid_secrets enable row level security;
revoke all on public.plaid_secrets from anon, authenticated;

-- Simple "own rows" tables -------------------------------------------------
create policy "own profile" on public.profiles
  for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy "own pay schedule" on public.pay_schedules
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own notification prefs" on public.notification_prefs
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own device tokens" on public.device_tokens
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own pockets" on public.pockets
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own categories" on public.categories
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own rules" on public.rules
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own budgets" on public.budgets
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Bank data: read + limited updates; inserts/deletes come from edge functions -----
create policy "read own items" on public.bank_items
  for select to authenticated using (user_id = auth.uid());

create policy "read own accounts" on public.accounts
  for select to authenticated using (user_id = auth.uid());
create policy "update own accounts" on public.accounts
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "read own transactions" on public.transactions
  for select to authenticated using (user_id = auth.uid());
create policy "update own transactions" on public.transactions
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
-- splits are created by the user
create policy "insert own split transactions" on public.transactions
  for insert to authenticated with check (user_id = auth.uid() and split_parent_id is not null);
create policy "delete own split transactions" on public.transactions
  for delete to authenticated using (user_id = auth.uid() and split_parent_id is not null);

create policy "read own recurring" on public.recurring_streams
  for select to authenticated using (user_id = auth.uid());
create policy "update own recurring" on public.recurring_streams
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Users may not change server-maintained columns on transactions/accounts.
revoke update on public.transactions from authenticated;
grant update (category_id, category_source, needs_review, excluded, note, tags, merchant_name, kind) on public.transactions to authenticated;
revoke update on public.accounts from authenticated;
grant update (nickname, include_in_totals, color, sort, card_kind) on public.accounts to authenticated;

-- FX: readable by everyone signed in
create policy "read fx" on public.fx_rates for select to authenticated using (true);

-- Notification log: read own (useful for an in-app inbox later)
create policy "read own notification log" on public.notification_log
  for select to authenticated using (user_id = auth.uid());

-- Goals ---------------------------------------------------------------------
-- helper avoids recursive policies between goals and goal_members
create or replace function public.is_goal_member(gid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.goal_members where goal_id = gid and user_id = auth.uid());
$$;

create policy "members read goals" on public.goals
  for select to authenticated using (owner_id = auth.uid() or public.is_goal_member(id));
create policy "owner writes goals" on public.goals
  for insert to authenticated with check (owner_id = auth.uid());
create policy "owner updates goals" on public.goals
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "owner deletes goals" on public.goals
  for delete to authenticated using (owner_id = auth.uid());

create policy "members read members" on public.goal_members
  for select to authenticated using (public.is_goal_member(goal_id));
create policy "owner adds self" on public.goal_members
  for insert to authenticated with check (
    user_id = auth.uid() and exists (select 1 from public.goals g where g.id = goal_id and g.owner_id = auth.uid())
  );
create policy "member updates own row" on public.goal_members
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "member leaves" on public.goal_members
  for delete to authenticated using (user_id = auth.uid());
-- current_amount is server-maintained
revoke update on public.goal_members from authenticated;
grant update (funding, account_id, earmark_amount, share_amount_visible, share_activity, display_name) on public.goal_members to authenticated;

create policy "members read events" on public.goal_events
  for select to authenticated using (public.is_goal_member(goal_id));
create policy "members add own events" on public.goal_events
  for insert to authenticated with check (
    user_id = auth.uid() and public.is_goal_member(goal_id) and kind in ('contribution', 'withdrawal', 'cheer')
  );

create policy "owner manages invites" on public.goal_invites
  for all to authenticated using (created_by = auth.uid()) with check (created_by = auth.uid());

-- Privacy-aware view of shared progress: hides a partner's amount when they chose so.
create or replace view public.goal_member_progress with (security_invoker = true) as
select
  m.goal_id,
  m.user_id,
  m.role,
  m.display_name,
  m.funding,
  case when m.user_id = auth.uid() or m.share_amount_visible then m.current_amount end as current_amount,
  case when g.target_amount > 0 then round(m.current_amount / g.target_amount * 100, 1) end as share_pct,
  m.share_activity,
  m.joined_at
from public.goal_members m
join public.goals g on g.id = m.goal_id;

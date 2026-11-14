-- Bills & subscriptions: manual entries, user overrides that survive Plaid syncs.
--   source          'plaid' (detected by /transactions/recurring/get) or 'manual' (added in the app)
--   kind            'subscription' | 'bill'; null = let the app decide
--   category_locked user picked the category; syncs keep it
--   hidden          user dismissed a detected stream (Plaid would re-create a deleted one)

alter table public.recurring_streams
  alter column plaid_stream_id drop not null,
  alter column account_id drop not null,
  add column if not exists source text not null default 'plaid' check (source in ('plaid', 'manual')),
  add column if not exists kind text check (kind in ('subscription', 'bill')),
  add column if not exists category_locked boolean not null default false,
  add column if not exists hidden boolean not null default false;

alter table public.recurring_streams
  add constraint recurring_source_stream check (source = 'manual' or plaid_stream_id is not null);

-- Users edit only their own preferences on detected streams; Plaid-maintained columns stay server-side.
-- Manual rows are fully theirs.
revoke update on public.recurring_streams from authenticated;
grant update (category_id, category_locked, kind, hidden,
              description, merchant_name, frequency, average_amount, last_amount, currency,
              predicted_next_date, account_id, is_active) on public.recurring_streams to authenticated;
grant insert, delete on public.recurring_streams to authenticated;

-- An account (if any) must be one of the user's own.
create or replace function public.owns_account_or_null(acc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select acc is null or exists (select 1 from public.accounts a where a.id = acc and a.user_id = auth.uid());
$$;

drop policy if exists "update own recurring" on public.recurring_streams;
create policy "update own recurring" on public.recurring_streams
  for update to authenticated using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.owns_account_or_null(account_id));

create policy "insert own manual recurring" on public.recurring_streams
  for insert to authenticated
  with check (user_id = auth.uid() and source = 'manual' and plaid_stream_id is null and public.owns_account_or_null(account_id));

create policy "delete own manual recurring" on public.recurring_streams
  for delete to authenticated using (user_id = auth.uid() and source = 'manual');

-- Detected rows: amount/schedule columns belong to Plaid. Block edits to them from clients.
create or replace function public.recurring_guard() returns trigger
language plpgsql as $$
begin
  if old.source = 'plaid' and current_user = 'authenticated' and (
       new.description is distinct from old.description or new.frequency is distinct from old.frequency or
       new.average_amount is distinct from old.average_amount or new.last_amount is distinct from old.last_amount or
       new.currency is distinct from old.currency or new.predicted_next_date is distinct from old.predicted_next_date or
       new.account_id is distinct from old.account_id or new.is_active is distinct from old.is_active or
       new.source is distinct from old.source) then
    raise exception 'detected recurring streams are maintained by the bank sync';
  end if;
  return new;
end $$;

drop trigger if exists recurring_guard on public.recurring_streams;
create trigger recurring_guard before update on public.recurring_streams
  for each row execute function public.recurring_guard();

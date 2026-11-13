-- akwe — "hide" an account, independent of "include in totals".
-- hidden = not shown in the Home account cards or account filters (still listed under
-- Accounts & cards › Hidden). include_in_totals still decides whether it counts.
alter table public.accounts add column if not exists hidden boolean not null default false;
grant update (hidden) on public.accounts to authenticated;

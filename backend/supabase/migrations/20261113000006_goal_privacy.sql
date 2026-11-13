-- akwe — tighten shared-goal access.
--
-- 1. goal_members: a member could read partners' raw rows (current_amount, earmark_amount,
--    account_id), bypassing "hide my amount". Members now read only their own row; partners'
--    progress is exposed solely through goal_member_progress, which applies the privacy choice.
-- 2. goal_invites: any user could insert an invite for any goal_id and redeem it from a second
--    account. Invites are created and redeemed only by the goal-action function (service role,
--    owner-checked), so clients get no direct access at all.
-- 3. goal_members.account_id: a member could point their row at someone else's account; the
--    server now ignores accounts the member doesn't own (see _shared/notifyCore.ts), and this
--    check rejects it at write time too.

-- 1 ---------------------------------------------------------------------------
drop policy if exists "members read members" on public.goal_members;
create policy "member reads own row" on public.goal_members
  for select to authenticated using (user_id = auth.uid());

-- The view must see co-members' rows, so it runs with its owner's rights and enforces
-- membership itself. Hidden amounts are null. share_pct stays: the app needs it to total the
-- goal, and with two members the total already implies the partner's share, so "hide my amount"
-- hides the per-person breakdown (and earmark / linked account), not the goal's total progress.
drop view if exists public.goal_member_progress;
create view public.goal_member_progress with (security_invoker = false) as
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
join public.goals g on g.id = m.goal_id
where public.is_goal_member(m.goal_id);

revoke all on public.goal_member_progress from anon, public;
grant select on public.goal_member_progress to authenticated;

-- 2 ---------------------------------------------------------------------------
drop policy if exists "owner manages invites" on public.goal_invites;
revoke all on public.goal_invites from anon, authenticated;

-- 3 ---------------------------------------------------------------------------
create or replace function public.goal_member_own_account() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.account_id is not null
     and not exists (select 1 from public.accounts a where a.id = new.account_id and a.user_id = new.user_id) then
    raise exception 'account does not belong to this member' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists goal_members_own_account on public.goal_members;
create trigger goal_members_own_account before insert or update of account_id on public.goal_members
  for each row execute function public.goal_member_own_account();

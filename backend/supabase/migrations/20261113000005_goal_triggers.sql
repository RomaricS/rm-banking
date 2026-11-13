-- akwe — keep goal_members.current_amount right for manual & earmark funding.
-- (Account-funded members are refreshed by the server after each bank sync.)

create or replace function public.apply_goal_event() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind in ('contribution', 'withdrawal') and new.amount is not null then
    update goal_members
       set current_amount = greatest(0, current_amount + case when new.kind = 'contribution' then new.amount else -new.amount end)
     where goal_id = new.goal_id and user_id = new.user_id and funding = 'manual';
  end if;
  return new;
end $$;

create trigger goal_events_apply after insert on public.goal_events
  for each row execute function public.apply_goal_event();

create or replace function public.apply_earmark() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.funding = 'earmark' then
    new.current_amount := coalesce(new.earmark_amount, 0);
  end if;
  return new;
end $$;

create trigger goal_members_earmark before insert or update of funding, earmark_amount on public.goal_members
  for each row execute function public.apply_earmark();

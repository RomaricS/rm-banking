-- akwe — default pockets & categories, created for each new user.
-- Icons are SF Symbols names. pfc_match = Plaid personal_finance_category prefixes (detailed or primary).

create or replace function public.seed_user_defaults(uid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  p_home uuid; p_food uuid; p_move uuid; p_life uuid; p_health uuid; p_other uuid; p_income uuid;
begin
  insert into pockets (user_id, key, name, icon, color, sort) values
    (uid, 'home', 'Home', 'house.fill', '#7C9CFF', 1) returning id into p_home;
  insert into pockets (user_id, key, name, icon, color, sort) values
    (uid, 'food', 'Food', 'fork.knife', '#FF9F5A', 2) returning id into p_food;
  insert into pockets (user_id, key, name, icon, color, sort) values
    (uid, 'getting_around', 'Getting around', 'car.fill', '#3DDC97', 3) returning id into p_move;
  insert into pockets (user_id, key, name, icon, color, sort) values
    (uid, 'lifestyle', 'Lifestyle', 'bag.fill', '#C084FC', 4) returning id into p_life;
  insert into pockets (user_id, key, name, icon, color, sort) values
    (uid, 'health', 'Health', 'heart.fill', '#FF7EB6', 5) returning id into p_health;
  insert into pockets (user_id, key, name, icon, color, sort) values
    (uid, 'other', 'Other', 'ellipsis', '#8B8B96', 6) returning id into p_other;
  insert into pockets (user_id, key, name, icon, color, is_income, sort) values
    (uid, 'income', 'Income', 'arrow.down.left', '#3DDC97', true, 7) returning id into p_income;

  insert into categories (user_id, pocket_id, key, name, icon, pfc_match, sort) values
    (uid, p_home, 'rent', 'Rent', 'key.fill', array['RENT_AND_UTILITIES_RENT'], 1),
    (uid, p_home, 'utilities', 'Utilities', 'bolt.fill', array['RENT_AND_UTILITIES_GAS_AND_ELECTRICITY','RENT_AND_UTILITIES_WATER','RENT_AND_UTILITIES_SEWAGE_AND_WASTE_MANAGEMENT','RENT_AND_UTILITIES_OTHER_UTILITIES'], 2),
    (uid, p_home, 'internet_phone', 'Internet & phone', 'wifi', array['RENT_AND_UTILITIES_INTERNET_AND_CABLE','RENT_AND_UTILITIES_TELEPHONE'], 3),
    (uid, p_home, 'household', 'Household', 'sofa.fill', array['HOME_IMPROVEMENT'], 4),
    (uid, p_home, 'insurance', 'Insurance', 'shield.fill', array['GENERAL_SERVICES_INSURANCE'], 5),

    (uid, p_food, 'groceries', 'Groceries', 'cart.fill', array['FOOD_AND_DRINK_GROCERIES'], 1),
    (uid, p_food, 'restaurants', 'Restaurants', 'fork.knife', array['FOOD_AND_DRINK_RESTAURANT','FOOD_AND_DRINK_FAST_FOOD','FOOD_AND_DRINK_OTHER_FOOD_AND_DRINK','FOOD_AND_DRINK_VENDING_MACHINES'], 2),
    (uid, p_food, 'coffee', 'Coffee', 'cup.and.saucer.fill', array['FOOD_AND_DRINK_COFFEE'], 3),
    (uid, p_food, 'bars', 'Bars & drinks', 'wineglass.fill', array['FOOD_AND_DRINK_BEER_WINE_AND_LIQUOR'], 4),

    (uid, p_move, 'gas', 'Gas', 'fuelpump.fill', array['TRANSPORTATION_GAS'], 1),
    (uid, p_move, 'rideshare', 'Rideshare & taxi', 'car.side.fill', array['TRANSPORTATION_TAXIS_AND_RIDE_SHARES'], 2),
    (uid, p_move, 'transit', 'Public transit', 'tram.fill', array['TRANSPORTATION_PUBLIC_TRANSIT','TRANSPORTATION_BIKES_AND_SCOOTERS'], 3),
    (uid, p_move, 'parking', 'Parking & tolls', 'parkingsign', array['TRANSPORTATION_PARKING','TRANSPORTATION_TOLLS'], 4),
    (uid, p_move, 'car', 'Car', 'wrench.and.screwdriver.fill', array['TRANSPORTATION_OTHER_TRANSPORTATION','LOAN_PAYMENTS_CAR_PAYMENT','GENERAL_SERVICES_AUTOMOTIVE'], 5),

    (uid, p_life, 'shopping', 'Shopping', 'bag.fill', array['GENERAL_MERCHANDISE'], 1),
    (uid, p_life, 'entertainment', 'Entertainment', 'ticket.fill', array['ENTERTAINMENT'], 2),
    (uid, p_life, 'subscriptions', 'Subscriptions', 'repeat', array['ENTERTAINMENT_TV_AND_MOVIES','ENTERTAINMENT_MUSIC_AND_AUDIO'], 3),
    (uid, p_life, 'travel', 'Travel', 'airplane', array['TRAVEL'], 4),
    (uid, p_life, 'personal_care', 'Personal care', 'scissors', array['PERSONAL_CARE'], 5),
    (uid, p_life, 'gifts', 'Gifts & donations', 'gift.fill', array['GOVERNMENT_AND_NON_PROFIT_DONATIONS','GENERAL_MERCHANDISE_GIFTS_AND_NOVELTIES'], 6),

    (uid, p_health, 'medical', 'Medical', 'cross.case.fill', array['MEDICAL'], 1),
    (uid, p_health, 'fitness', 'Fitness', 'figure.run', array['PERSONAL_CARE_GYMS_AND_FITNESS_CENTERS'], 2),

    (uid, p_other, 'fees', 'Fees', 'exclamationmark.circle', array['BANK_FEES'], 1),
    (uid, p_other, 'taxes', 'Taxes', 'building.columns.fill', array['GOVERNMENT_AND_NON_PROFIT'], 2),
    (uid, p_other, 'education', 'Education', 'graduationcap.fill', array['GENERAL_SERVICES_EDUCATION'], 3),
    (uid, p_other, 'cash', 'Cash', 'banknote.fill', array['TRANSFER_OUT_WITHDRAWAL'], 4),
    (uid, p_other, 'services', 'Services', 'briefcase.fill', array['GENERAL_SERVICES'], 5),
    (uid, p_other, 'uncategorized', 'Other', 'questionmark', array[]::text[], 9),

    (uid, p_income, 'paycheck', 'Paycheck', 'briefcase.fill', array['INCOME_WAGES'], 1),
    (uid, p_income, 'other_income', 'Other income', 'arrow.down.left', array['INCOME'], 2);
end $$;

-- On sign-up: profile, prefs, pay schedule placeholder, defaults.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name)
    values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'))
    on conflict (id) do nothing;
  insert into notification_prefs (user_id) values (new.id) on conflict do nothing;
  insert into pay_schedules (user_id) values (new.id) on conflict do nothing;
  perform seed_user_defaults(new.id);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

revoke execute on function public.seed_user_defaults(uuid) from public, anon, authenticated;

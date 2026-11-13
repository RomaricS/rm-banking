-- akwe — scheduled jobs (pg_cron + pg_net).
-- Requires two Vault secrets (see README, "Supabase setup"):
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
--   select vault.create_secret('<service-role-key>', 'service_role_key');

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function private.call_function(fn text, body jsonb default '{}'::jsonb) returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare
  base text;
  key text;
begin
  select decrypted_secret into base from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into key from vault.decrypted_secrets where name = 'service_role_key';
  if base is null or key is null then
    raise notice 'akwe cron: vault secrets project_url / service_role_key missing, skipping %', fn;
    return null;
  end if;
  return net.http_post(
    url := base || '/functions/v1/' || fn,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || key),
    body := body
  );
end $$;

-- Exchange rates: every day at 16:30 UTC (ECB publishes ~16:00 CET)
select cron.schedule('akwe-fx-refresh', '30 16 * * *', $$ select private.call_function('fx-refresh'); $$);

-- Safety-net sync of every bank (webhooks do the real-time work): every 6 hours
select cron.schedule('akwe-sync-all', '17 */6 * * *', $$ select private.call_function('plaid-sync', '{"all": true}'::jsonb); $$);

-- Daily notifications (bills due tomorrow, payday summary): 14:05 UTC (morning in the Americas, afternoon in Europe)
select cron.schedule('akwe-notify-daily', '5 14 * * *', $$ select private.call_function('notify', '{"mode": "daily"}'::jsonb); $$);

-- Extends push notifications (see supabase_migration_push_notifications.sql)
-- to also fire for new harvests, harvest sales, and supplier purchases -
-- not just transactions. Each trigger now builds its own title/body in
-- SQL (joining out for a customer/supplier name or harvest code where
-- needed) so the Edge Function can stay a thin relay. See claude.md's
-- "Push notifications" section for the full design.

create or replace function public.format_money(amount numeric, currency text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when currency = 'SLSH' then 'Sh' || to_char(round(amount), 'FM999,999,999')
    else '$' || to_char(round(amount, 2), 'FM999,999,999.00')
  end;
$$;

create or replace function public.notify_new_transaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_secret text;
  type_label text;
  title text;
  body text;
begin
  if new.type = 'advance_deduction' then
    return new;
  end if;

  type_label := case new.type
    when 'expense' then 'Expense'
    when 'payroll' then 'Payroll'
    when 'loan' then 'Loan given'
    when 'advance' then 'Advance given'
    when 'loan_repayment' then 'Loan repayment'
    else initcap(new.type)
  end;
  title := type_label || ': ' || public.format_money(new.amount, new.currency);
  body := coalesce(nullif(trim(new.note), ''), 'Tap to view in Janatayn Farms.');

  select public.get_decrypted_secret('notify_webhook_secret') into webhook_secret;
  perform net.http_post(
    url := 'https://jgxqvhryinoulpztprwz.supabase.co/functions/v1/notify-transaction',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', webhook_secret),
    body := jsonb_build_object('record', jsonb_build_object(
      'kind', 'transaction',
      'id', new.id,
      'title', title,
      'body', body,
      'type', new.type,
      'created_by', new.created_by
    ))
  );
  return new;
end;
$$;

create or replace function public.notify_new_harvest()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_secret text;
  title text;
  body text;
begin
  select public.get_decrypted_secret('notify_webhook_secret') into webhook_secret;
  title := 'New harvest: #H' || new.harvest_number;
  body := to_char(new.kg_harvested, 'FM999999990.0') || ' kg harvested'
    || case when coalesce(trim(new.note), '') <> '' then ' — ' || trim(new.note) else '' end;

  perform net.http_post(
    url := 'https://jgxqvhryinoulpztprwz.supabase.co/functions/v1/notify-transaction',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', webhook_secret),
    body := jsonb_build_object('record', jsonb_build_object(
      'kind', 'harvest',
      'id', new.id,
      'title', title,
      'body', body,
      'created_by', new.created_by
    ))
  );
  return new;
end;
$$;

drop trigger if exists on_harvest_insert_notify on public.harvests;
create trigger on_harvest_insert_notify
  after insert on public.harvests
  for each row execute function public.notify_new_harvest();

create or replace function public.notify_new_harvest_sale()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_secret text;
  harvest_code text;
  customer_name text;
  owed numeric;
  title text;
  body text;
begin
  select '#H' || harvest_number into harvest_code from public.harvests where id = new.harvest_id;
  select name into customer_name from public.customers where id = new.customer_id;
  owed := greatest(new.kg_sold * new.price_per_kg - coalesce(new.transport_fee, 0), 0);

  select public.get_decrypted_secret('notify_webhook_secret') into webhook_secret;
  title := 'Harvest sale: ' || public.format_money(owed, new.currency);
  body := to_char(new.kg_sold, 'FM999999990.0') || ' kg from ' || coalesce(harvest_code, 'a harvest')
    || ' to ' || coalesce(customer_name, 'a customer');

  perform net.http_post(
    url := 'https://jgxqvhryinoulpztprwz.supabase.co/functions/v1/notify-transaction',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', webhook_secret),
    body := jsonb_build_object('record', jsonb_build_object(
      'kind', 'harvest_sale',
      'id', new.id,
      'title', title,
      'body', body,
      'created_by', new.created_by
    ))
  );
  return new;
end;
$$;

drop trigger if exists on_harvest_sale_insert_notify on public.harvest_sales;
create trigger on_harvest_sale_insert_notify
  after insert on public.harvest_sales
  for each row execute function public.notify_new_harvest_sale();

create or replace function public.notify_new_supplier_purchase()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_secret text;
  supplier_name text;
  title text;
  body text;
begin
  select name into supplier_name from public.suppliers where id = new.supplier_id;

  select public.get_decrypted_secret('notify_webhook_secret') into webhook_secret;
  title := 'Purchase: ' || public.format_money(new.amount, new.currency);
  body := new.item || ' from ' || coalesce(supplier_name, 'a supplier');

  perform net.http_post(
    url := 'https://jgxqvhryinoulpztprwz.supabase.co/functions/v1/notify-transaction',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', webhook_secret),
    body := jsonb_build_object('record', jsonb_build_object(
      'kind', 'supplier_purchase',
      'id', new.id,
      'title', title,
      'body', body,
      'created_by', new.created_by
    ))
  );
  return new;
end;
$$;

drop trigger if exists on_supplier_purchase_insert_notify on public.supplier_purchases;
create trigger on_supplier_purchase_insert_notify
  after insert on public.supplier_purchases
  for each row execute function public.notify_new_supplier_purchase();

-- Postgres exposes even a trigger-only SECURITY DEFINER function to
-- direct RPC calls by default (anon/authenticated) - none of these four
-- are meant to be called except by their own trigger.
revoke all on function public.notify_new_transaction() from public, anon, authenticated;
revoke all on function public.notify_new_harvest() from public, anon, authenticated;
revoke all on function public.notify_new_harvest_sale() from public, anon, authenticated;
revoke all on function public.notify_new_supplier_purchase() from public, anon, authenticated;

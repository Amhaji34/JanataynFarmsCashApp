-- Push notifications: every 3 users get a push when a new transaction is
-- recorded (except the person who just made it). See claude.md's "Push
-- notifications" section for the full design.

-- One row per device registered for push, upserted by the Flutter app
-- (lib/services/push_notifications.dart) after login and on FCM token
-- refresh, deleted on logout. Read access is intentionally NOT public -
-- only the service role (used by the notify-transaction Edge Function)
-- can read every row; a user can only manage their own.
create table device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  token text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table device_tokens enable row level security;

create policy "device_tokens_read_own" on device_tokens for select
  using (user_id = auth.uid());
create policy "device_tokens_write_own" on device_tokens for insert
  with check (user_id = auth.uid());
create policy "device_tokens_update_own" on device_tokens for update
  using (user_id = auth.uid());
create policy "device_tokens_delete_own" on device_tokens for delete
  using (user_id = auth.uid());

create extension if not exists pg_net;

-- Shared secret between the transactions insert trigger and the
-- notify-transaction Edge Function, so the function can reject any
-- request that didn't actually come from this database. Randomly
-- generated - NOT the Firebase service account, which is a separate
-- secret added manually via the Supabase SQL Editor (never through a
-- migration or committed to the repo - see claude.md).
select vault.create_secret(
  encode(gen_random_bytes(32), 'hex'),
  'notify_webhook_secret',
  'Shared secret between the transactions insert trigger and the notify-transaction Edge Function.'
)
where not exists (select 1 from vault.secrets where name = 'notify_webhook_secret');

-- Lets the notify-transaction Edge Function (which only ever calls in
-- with the service role key) read secrets back out of Vault. Nobody
-- else can call this - execute is revoked from anon/authenticated.
create or replace function public.get_decrypted_secret(secret_name text)
returns text
language sql
security definer
set search_path = ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = secret_name limit 1;
$$;
revoke all on function public.get_decrypted_secret(text) from public, anon, authenticated;
grant execute on function public.get_decrypted_secret(text) to service_role;

-- Fires the notify-transaction Edge Function after every new
-- transactions row. Uses pg_net so the insert itself never blocks on
-- the HTTP call.
create or replace function public.notify_new_transaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  webhook_secret text;
begin
  select public.get_decrypted_secret('notify_webhook_secret') into webhook_secret;
  perform net.http_post(
    url := 'https://jgxqvhryinoulpztprwz.supabase.co/functions/v1/notify-transaction',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', webhook_secret
    ),
    body := jsonb_build_object('record', to_jsonb(new))
  );
  return new;
end;
$$;

drop trigger if exists on_transaction_insert_notify on public.transactions;
create trigger on_transaction_insert_notify
  after insert on public.transactions
  for each row execute function public.notify_new_transaction();

-- Run once, manually, in the Supabase SQL Editor (never via an agent or
-- a committed migration - this is a real secret):
--
-- select vault.create_secret(
--   '<paste the full Firebase service account JSON here>',
--   'firebase_service_account',
--   'FCM v1 API service account JSON for push notifications'
-- );

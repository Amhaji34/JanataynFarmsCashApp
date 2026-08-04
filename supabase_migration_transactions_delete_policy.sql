-- Run this in the Supabase SQL editor.
-- Fixes: editing a multi-invoice transaction inserts a replacement but
-- silently fails to delete the original, because RLS had no DELETE
-- policy on `transactions` (only insert/update were covered).

create policy "transactions_delete_admin"
  on public.transactions
  for delete
  using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

-- Optional cleanup: remove the duplicate rows already created by this bug.
-- Inspect first before running anything destructive:
--   select id, type, amount, transaction_date, note, created_at
--   from public.transactions
--   order by transaction_date desc, created_at desc;

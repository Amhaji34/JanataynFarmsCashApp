-- Allows account_transactions.type to also be 'exchange_in'/'exchange_out',
-- for converting an account's existing USD balance into SLSH or vice
-- versa (see exchange_screen.dart). An exchange writes both rows on the
-- SAME account_id (no related_account_id - it's not a transfer between
-- accounts, just a currency swap within one account), so account
-- balances stay correct without any other schema change.

alter table account_transactions drop constraint account_transactions_type_check;
alter table account_transactions add constraint account_transactions_type_check
  check (type = any (array['fund_add'::text, 'transfer_in'::text, 'transfer_out'::text, 'exchange_in'::text, 'exchange_out'::text]));

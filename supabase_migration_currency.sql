-- Dual-currency support: adds a `currency` column to every money-bearing
-- table. DEFAULT 'USD' backfills existing rows automatically since all
-- historical data was effectively USD. `transaction_items` intentionally
-- has no column of its own — it inherits its parent transaction's
-- currency (a transaction is one atomic event in one currency).
-- `accounts` also needs no column — each account's USD/SLSH balances are
-- just two separately-filtered sums over account_transactions.currency.

alter table transactions add column currency text not null default 'USD'
  check (currency in ('USD','SLSH'));

alter table account_transactions add column currency text not null default 'USD'
  check (currency in ('USD','SLSH'));

alter table harvests add column currency text not null default 'USD'
  check (currency in ('USD','SLSH'));

alter table customer_payments add column currency text not null default 'USD'
  check (currency in ('USD','SLSH'));

-- Reference currency for a staff member's base_salary and their default
-- payroll-line currency. Not summed into anything.
alter table staff add column currency text not null default 'USD'
  check (currency in ('USD','SLSH'));

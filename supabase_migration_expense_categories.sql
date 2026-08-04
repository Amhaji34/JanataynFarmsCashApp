-- Run this in the Supabase SQL editor.

-- 1. New table for managed expense categories (Fuel, Water, Food, ...)
create table if not exists public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

alter table public.expense_categories enable row level security;

create policy "expense_categories_read_all"
  on public.expense_categories
  for select
  using (true);

create policy "expense_categories_write_admin"
  on public.expense_categories
  for insert
  with check (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

create policy "expense_categories_update_admin"
  on public.expense_categories
  for update
  using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

-- 2. Rename the 'bill' transaction type to 'expense', drop 'other'.
--    If existing rows use 'other', fold them into 'expense' too -
--    remove the next line if you'd rather keep them as-is.
update public.transactions set type = 'expense' where type in ('bill', 'other');

-- 3. If you have a CHECK constraint on transactions.type, update it.
--    (Replace the constraint name below with your actual one if different -
--    check with: select conname from pg_constraint where conrelid = 'public.transactions'::regclass;)
alter table public.transactions drop constraint if exists transactions_type_check;
alter table public.transactions add constraint transactions_type_check
  check (type in ('expense', 'payroll', 'loan', 'advance', 'loan_repayment', 'advance_deduction'));

-- 4. Seed a few starter categories (optional - edit/add as you like).
insert into public.expense_categories (name) values
  ('Fuel'), ('Water'), ('Food')
on conflict (name) do nothing;

-- Suppliers: simple name lookup, same philosophy as customers/partners/staff.
create table suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  note text,
  created_at timestamptz not null default now()
);
alter table suppliers enable row level security;
create policy "suppliers_read_all" on suppliers for select using (true);
create policy "suppliers_write_admin" on suppliers for insert
  with check ((select role from public.users where id = auth.uid()) = 'admin');
create policy "suppliers_update_admin" on suppliers for update
  using ((select role from public.users where id = auth.uid()) = 'admin');
create policy "suppliers_delete_admin" on suppliers for delete
  using ((select role from public.users where id = auth.uid()) = 'admin');

-- One row per purchase (something bought) against a supplier. Amount is
-- the total cost owed for that purchase - paid separately/partially via
-- supplier_payments, same split as harvests/harvest_sales vs
-- customer_payments but reversed (we owe them, not the other way).
create table supplier_purchases (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references suppliers(id),
  item text not null,
  amount numeric not null check (amount >= 0),
  currency text not null default 'USD' check (currency in ('USD','SLSH')),
  purchase_date date not null default current_date,
  note text,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);
alter table supplier_purchases enable row level security;
create policy "supplier_purchases_read_all" on supplier_purchases for select using (true);
create policy "supplier_purchases_write_admin" on supplier_purchases for insert
  with check ((select role from public.users where id = auth.uid()) = 'admin');
create policy "supplier_purchases_update_admin" on supplier_purchases for update
  using ((select role from public.users where id = auth.uid()) = 'admin');
create policy "supplier_purchases_delete_admin" on supplier_purchases for delete
  using ((select role from public.users where id = auth.uid()) = 'admin');

-- Every payment made toward a supplier - the "paid now" amount recorded
-- at purchase time *and* any later payment - lands here as one ledger,
-- same shape as customer_payments.
create table supplier_payments (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references suppliers(id),
  purchase_id uuid references supplier_purchases(id),
  amount numeric not null check (amount > 0),
  currency text not null default 'USD' check (currency in ('USD','SLSH')),
  payment_date date not null default current_date,
  note text,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);
alter table supplier_payments enable row level security;
create policy "supplier_payments_read_all" on supplier_payments for select using (true);
create policy "supplier_payments_write_admin" on supplier_payments for insert
  with check ((select role from public.users where id = auth.uid()) = 'admin');
create policy "supplier_payments_update_admin" on supplier_payments for update
  using ((select role from public.users where id = auth.uid()) = 'admin');
create policy "supplier_payments_delete_admin" on supplier_payments for delete
  using ((select role from public.users where id = auth.uid()) = 'admin');

-- A supplier payment is cash actually leaving Petty Cash (unlike a
-- customer payment, which only credits Revenue and needs a separate
-- transfer into Petty Cash) - so it's recorded as a normal 'expense'
-- transaction too, under a dedicated category, so the existing Petty
-- Cash balance formula picks it up with no other code changes.
insert into expense_categories (name)
select 'Supplier purchases'
where not exists (select 1 from expense_categories where name = 'Supplier purchases');

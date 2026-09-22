-- Splits harvest (inventory intake) from sale (who it was sold to, how
-- much, for how much) so one harvest can be sold to more than one
-- customer, and a harvest can sit unsold for a few days before any sale
-- is recorded. Both `harvests` and `customer_payments` had 0 rows in
-- production when this was applied, so no data backfill was needed.

alter table harvests drop column customer_id;
alter table harvests drop column price_per_kg;
alter table harvests drop column currency;

create table harvest_sales (
  id uuid primary key default gen_random_uuid(),
  harvest_id uuid not null references harvests(id),
  customer_id uuid not null references customers(id),
  kg_sold numeric not null check (kg_sold > 0),
  price_per_kg numeric not null check (price_per_kg >= 0),
  currency text not null default 'USD' check (currency in ('USD','SLSH')),
  sale_date date not null default current_date,
  note text,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);

alter table harvest_sales enable row level security;

create policy "harvest_sales_select_all" on harvest_sales
  for select using (true);

create policy "harvest_sales_insert_admin" on harvest_sales
  for insert with check ((select role from public.users where id = auth.uid()) = 'admin');

create policy "harvest_sales_update_admin" on harvest_sales
  for update using ((select role from public.users where id = auth.uid()) = 'admin');

create policy "harvest_sales_delete_admin" on harvest_sales
  for delete using ((select role from public.users where id = auth.uid()) = 'admin');

-- A payment is against a specific sale now, not a harvest directly,
-- since one harvest can have several sales to different customers.
alter table customer_payments rename column harvest_id to sale_id;
alter table customer_payments drop constraint customer_payments_harvest_id_fkey;
alter table customer_payments add constraint customer_payments_sale_id_fkey
  foreign key (sale_id) references harvest_sales(id);

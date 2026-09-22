-- Applied directly to the project via the Supabase MCP (apply_migration,
-- name: add_customers_harvests_payments). Kept here for the record / in
-- case this ever needs to be replayed against another project.

-- Customers who buy harvest produce.
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  note text,
  created_at timestamptz not null default now()
);

alter table public.customers enable row level security;

create policy "customers_read_all"
  on public.customers for select using (true);
create policy "customers_write_admin"
  on public.customers for insert with check (
    (select role from public.users where id = auth.uid()) = 'admin'
  );
create policy "customers_update_admin"
  on public.customers for update using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );
create policy "customers_delete_admin"
  on public.customers for delete using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

-- One row per harvest, which doubles as the sale record to one customer.
-- total value = kg_harvested * price_per_kg, computed client-side, not
-- stored (same "calculated, never stored" philosophy as the rest of the
-- app).
create table public.harvests (
  id uuid primary key default gen_random_uuid(),
  harvest_date date not null default current_date,
  kg_harvested numeric not null check (kg_harvested > 0),
  price_per_kg numeric not null check (price_per_kg >= 0),
  customer_id uuid not null references public.customers(id),
  note text,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);

alter table public.harvests enable row level security;

create policy "harvests_read_all"
  on public.harvests for select using (true);
create policy "harvests_write_admin"
  on public.harvests for insert with check (
    (select role from public.users where id = auth.uid()) = 'admin'
  );
create policy "harvests_update_admin"
  on public.harvests for update using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );
create policy "harvests_delete_admin"
  on public.harvests for delete using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

-- Every payment a customer makes - the upfront amount recorded at harvest
-- time AND any later payments - lands here as one ledger, so a
-- customer's outstanding balance is always:
--   sum(harvests.kg_harvested * harvests.price_per_kg) - sum(customer_payments.amount)
-- harvest_id is nullable/for context only; a payment always reduces the
-- customer's overall balance, not a specific harvest's balance.
create table public.customer_payments (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  harvest_id uuid references public.harvests(id),
  amount numeric not null check (amount > 0),
  payment_date date not null default current_date,
  note text,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);

alter table public.customer_payments enable row level security;

create policy "customer_payments_read_all"
  on public.customer_payments for select using (true);
create policy "customer_payments_write_admin"
  on public.customer_payments for insert with check (
    (select role from public.users where id = auth.uid()) = 'admin'
  );
create policy "customer_payments_update_admin"
  on public.customer_payments for update using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );
create policy "customer_payments_delete_admin"
  on public.customer_payments for delete using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

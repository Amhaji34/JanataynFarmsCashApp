-- Applied directly to the project via the Supabase MCP (apply_migration,
-- name: add_accounts_and_account_transactions). Kept here for the record /
-- in case this ever needs to be replayed against another project.

-- Fixed set of 4 funding "accounts". Investment / Loans / Revenue are
-- fundable buckets; Petty Cash is the operating cash the app's dashboard,
-- expenses and payroll actually draw from. The only way money reaches
-- Petty Cash is a transfer from one of the other three.
create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

alter table public.accounts enable row level security;

create policy "accounts_read_all"
  on public.accounts for select using (true);

create policy "accounts_write_admin"
  on public.accounts for insert with check (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

create policy "accounts_update_admin"
  on public.accounts for update using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

create policy "accounts_delete_admin"
  on public.accounts for delete using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

insert into public.accounts (name) values
  ('Investment'), ('Loans'), ('Revenue'), ('Petty Cash');

-- Ledger of fund additions (into Investment/Loans/Revenue) and transfers
-- (from one of those three into Petty Cash). A transfer inserts two rows:
-- a transfer_out on the source account and a transfer_in on Petty Cash,
-- each pointing at the other via related_account_id, so either side's
-- history reads correctly on its own.
create table public.account_transactions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts(id),
  type text not null check (type in ('fund_add', 'transfer_in', 'transfer_out')),
  amount numeric not null check (amount > 0),
  related_account_id uuid references public.accounts(id),
  note text,
  transaction_date date not null default current_date,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);

alter table public.account_transactions enable row level security;

create policy "account_transactions_read_all"
  on public.account_transactions for select using (true);

create policy "account_transactions_write_admin"
  on public.account_transactions for insert with check (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

create policy "account_transactions_update_admin"
  on public.account_transactions for update using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

create policy "account_transactions_delete_admin"
  on public.account_transactions for delete using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

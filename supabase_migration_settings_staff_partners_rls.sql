-- Run this in the Supabase SQL editor.
-- Ensures `settings`, `staff`, and `partners` all follow the standard
-- read-all / write-admin RLS pattern used across the app. If a table
-- already has RLS enabled with these policies, the corresponding
-- statement will error with "already exists" - just skip that one.

-- settings
alter table public.settings enable row level security;

create policy "settings_read_all"
  on public.settings
  for select
  using (true);

create policy "settings_write_admin"
  on public.settings
  for update
  using (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

-- staff (in case insert policy is missing)
create policy "staff_write_admin"
  on public.staff
  for insert
  with check (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

-- partners (in case insert policy is missing)
create policy "partners_write_admin"
  on public.partners
  for insert
  with check (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

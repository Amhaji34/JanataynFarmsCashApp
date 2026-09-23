-- Sequential display code for each harvest (#H1, #H2, ...), backfilled
-- in creation order for existing harvests via a sequence-backed column
-- (not a naive `serial`, since ALTER TABLE ... ADD COLUMN serial would
-- backfill existing rows in physical/ctid order rather than creation
-- order).
alter table harvests add column harvest_number int;

update harvests set harvest_number = sub.rn
from (
  select id, row_number() over (order by created_at) as rn from harvests
) sub
where harvests.id = sub.id;

alter table harvests alter column harvest_number set not null;

create sequence harvests_harvest_number_seq;
select setval('harvests_harvest_number_seq', coalesce((select max(harvest_number) from harvests), 0), true);
alter table harvests alter column harvest_number set default nextval('harvests_harvest_number_seq');
alter sequence harvests_harvest_number_seq owned by harvests.harvest_number;

alter table harvests add constraint harvests_harvest_number_key unique (harvest_number);

-- Transportation fee on a sale, subtracted from what the customer owes
-- for that sale (see add_sale_screen.dart).
alter table harvest_sales add column transport_fee numeric not null default 0
  check (transport_fee >= 0);

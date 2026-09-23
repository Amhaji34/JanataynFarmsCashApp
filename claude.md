# Farm Cash Manager — Project Reference

A Flutter + Supabase app for tracking farm business cash flow: bills, payroll,
loans to partners, staff advances, and harvest sales to customers. Built by
one admin (the person who controls all cash) with two partners who have
read-only visibility.

## Stack

- **Frontend:** Flutter
- **Backend:** Supabase (Postgres + Auth + Row Level Security)
- **Auth:** Supabase Auth, but username-based in the UI (see Auth section)
- **Key packages:** `supabase_flutter`, `intl`

## People & roles

Three people use this app:

- **Admin (the founder/owner running this app):** full read/write access.
  Can add, edit transactions, manage partners/staff.
- **Two partners ("viewers"):** full **read-only** access. They see
  everything the admin sees — dashboard, transaction log, all balances —
  but have zero write access, enforced at the database level via RLS, not
  just hidden UI buttons.

Partners' ownership stake itself is still fixed and external to this
system — there is no per-partner equity/profit-share tracking. What *is*
tracked is cash flowing into the business through the `accounts` funding
buckets (Investment, Loans, Revenue) and from there into Petty Cash, the
account the app actually spends from — see "Funding accounts" below.
This reverses an earlier, deliberate "no capital tracking" decision;
that decision no longer stands as of the accounts feature.

## Auth: username-based login (Option A)

Supabase Auth is email-based under the hood, but users never see or type
an email:

- Every account's real email in `auth.users` follows the pattern
  `username@janatayn.local` (e.g. `ahmed@janatayn.local`).
- The login screen only shows "Username" and "Password" fields.
- Internally, the app appends `@janatayn.local` to whatever username is
  typed, then calls `signInWithPassword` with that constructed email.
- No `username` column exists anywhere — the username is purely the
  local-part of this fake email convention. Do not add a lookup table for
  this; it's intentionally kept this simple for 3 users.
- **Session persistence:** `Supabase.initialize` sets
  `autoRefreshToken: true`, and `AuthGate` (see file structure below)
  checks for a cached session on launch instead of always showing
  LoginScreen. Once logged in, a partner stays logged in across app
  restarts — no idle/inactivity logout is implemented client-side. (The
  hard ceiling on this is Supabase's own refresh-token expiry, configured
  in the Supabase dashboard under Authentication > Sessions, not in this
  codebase.)

## Database schema (Supabase Postgres)

### `users`
Extends `auth.users`. Holds app-level profile + role.
```
id                 uuid (PK, references auth.users.id)
name               text
role               text ('admin' | 'viewer')
linked_partner_id  uuid (nullable, unused currently)
created_at         timestamptz
```

### `partners`
Just a name reference for the two colleagues — used to link loan
transactions to a person. No financial fields live here; loan balances are
calculated from `transactions`, not stored.
```
id          uuid (PK)
name        text
created_at  timestamptz
```

### `staff`
Farm workers who receive payroll and advances.
```
id           uuid (PK)
name         text
base_salary  numeric
currency     text, 'USD' | 'SLSH' (default 'USD') — the currency
             base_salary is quoted in, and the default for this staff
             member's payroll line; not summed into anything
created_at   timestamptz
```

### `customers`
People/businesses who buy harvest produce. Simple name lookup, same
philosophy as `partners`/`staff` — no financial fields here; what a
customer owes is calculated from `harvests` and `customer_payments`.
```
id          uuid (PK)
name        text
phone       text (nullable)
note        text (nullable)
created_at  timestamptz
```

### `harvests`
Pure inventory intake — how much was picked and when. Deliberately
carries no customer, price, or currency: the produce may sit unsold for
a few days, and can end up sold to more than one customer over time. See
"Harvests and customer sales" below.
```
id                uuid (PK)
harvest_date      date
kg_harvested      numeric (> 0)
harvest_number    int (unique, auto-incrementing) — this harvest's
                  display code is `#H<harvest_number>` (e.g. "#H3"),
                  computed client-side, never a separate stored string.
                  Backed by a dedicated sequence
                  (`harvests_harvest_number_seq`), not a bare `serial`,
                  so it survives independently of the table
note              text (nullable)
created_by        uuid (FK -> auth.users.id)
created_at        timestamptz
```
A harvest's remaining (unsold) kg is **calculated, never stored**:
`kg_harvested - sum(harvest_sales.kg_sold for that harvest)`.

### `harvest_sales`
One row per sale against a harvest's stock — a harvest can have many of
these, to the same or different customers, on different dates and at
different prices.
```
id             uuid (PK)
harvest_id     uuid (FK -> harvests.id) — not nullable; which harvest
               batch this sale draws down
customer_id    uuid (FK -> customers.id) — not nullable
kg_sold        numeric (> 0)
price_per_kg   numeric (>= 0)
transport_fee  numeric (>= 0, default 0) — deducted from what the
               customer owes for this sale (see below); not itself
               recorded as a business expense anywhere
currency       text, 'USD' | 'SLSH' (default 'USD') — see "Currencies"
sale_date      date — independent of the harvest's own date; this is
               what lets a sale happen a few days after harvesting
note           text (nullable) — always includes the harvest's `#H<n>`
               code, appended automatically at save time (see
               "Harvests and customer sales" below)
created_by     uuid (FK -> auth.users.id)
created_at     timestamptz
```
What the customer owes for one sale is **calculated, never stored**:
`kg_sold * price_per_kg - transport_fee` (floored at 0). This — not the
raw `kg_sold * price_per_kg` — is the figure used everywhere a sale's
value feeds into a customer's balance or a "total sold"/"outstanding"
stat, so those totals stay internally consistent (outstanding = value
summed this way, minus payments). A sale can't exceed the harvest's
remaining stock; that's validated client-side in `add_sale_screen.dart`
(fetch existing sales for the chosen harvest, sum their `kg_sold`), the
same pattern as the multi-invoice "allocated must equal total" and
Transfer/Exchange "can't exceed available balance" checks — not a DB
constraint. Same client-side pattern for `transport_fee` not exceeding
the sale's raw value.

### `customer_payments`
Every payment a customer makes — the upfront amount recorded at sale
time *and* any later payment — lands here as one ledger.
```
id             uuid (PK)
customer_id    uuid (FK -> customers.id)
sale_id        uuid (nullable, FK -> harvest_sales.id) — context only; a
               payment always reduces the customer's overall balance,
               never one specific sale's balance
amount         numeric (> 0)
currency       text, 'USD' | 'SLSH' (default 'USD')
payment_date   date
note           text (nullable)
created_by     uuid (FK -> auth.users.id)
created_at     timestamptz
```
A customer's outstanding balance is always calculated, **per currency**
(a customer with sales in both currencies has two separate outstanding
figures, never blended):
```
outstanding[currency] = sum(harvest_sales.kg_sold * harvest_sales.price_per_kg
                             for that customer, where harvest_sales.currency = currency)
                       - sum(customer_payments.amount for that customer,
                             where customer_payments.currency = currency)
```

### `suppliers`
People/businesses the farm buys from — accounts payable, the mirror
image of `customers`. Simple name lookup, same philosophy: no financial
fields here; what's owed to a supplier is calculated from
`supplier_purchases` and `supplier_payments`.
```
id          uuid (PK)
name        text
phone       text (nullable)
note        text (nullable)
created_at  timestamptz
```

### `supplier_purchases`
One row per thing bought from a supplier — the total cost owed for that
purchase, separate from how much of it has actually been paid (that's
`supplier_payments`, below). Unlike harvests/harvest_sales there's no
inventory split here — a purchase is a single flat cost, not a quantity
sold down over time.
```
id             uuid (PK)
supplier_id    uuid (FK -> suppliers.id) — not nullable
item           text — free-text description of what was bought
amount         numeric (>= 0) — the total cost owed for this purchase
currency       text, 'USD' | 'SLSH' (default 'USD') — see "Currencies"
purchase_date  date
note           text (nullable)
created_by     uuid (FK -> auth.users.id)
created_at     timestamptz
```

### `supplier_payments`
Every payment made toward a supplier — the amount paid at purchase time
*and* any later payment — lands here as one ledger, same shape as
`customer_payments` but money flowing the other direction.
```
id             uuid (PK)
supplier_id    uuid (FK -> suppliers.id)
purchase_id    uuid (nullable, FK -> supplier_purchases.id) — context
               only; a payment always reduces the supplier's overall
               balance, never one specific purchase's balance
amount         numeric (> 0)
currency       text, 'USD' | 'SLSH' (default 'USD')
payment_date   date
note           text (nullable)
created_by     uuid (FK -> auth.users.id)
created_at     timestamptz
```
What's owed to a supplier is always calculated, **per currency**, same
formula shape as customers:
```
owed[currency] = sum(supplier_purchases.amount for that supplier,
                      where supplier_purchases.currency = currency)
                - sum(supplier_payments.amount for that supplier,
                      where supplier_payments.currency = currency)
```
**Cash impact — the one place this differs from customer payments:** a
customer payment only credits the Revenue funding account (see "Funding
accounts" below) and still needs a manual transfer into Petty Cash. A
supplier payment is the opposite — real cash actually leaving the
business right now — so `recordSupplierPayment()`
(`lib/services/supplier_payments.dart`) books it as a normal `expense`
transaction (in `transactions` + `transaction_items`, category
"Supplier purchases", seeded once via migration into
`expense_categories`) rather than touching `accounts` at all. This means
a supplier payment draws down Petty Cash through the existing formula
with no other code changes, and shows up naturally in the Transaction
Log and the Reports Expenses tab under its own category.

### `transactions`
The parent record for every cash event. One row per "payment event" —
whether it's a single $4 fuel purchase or a $10 payment covering multiple
invoices across fuel/water/food.
```
id                  uuid (PK)
type                text, one of:
                    'expense' | 'payroll' | 'loan' | 'advance' |
                    'loan_repayment' | 'advance_deduction'
amount              numeric (the total; for multi-invoice transactions,
                    must equal the sum of its transaction_items amounts)
currency            text, 'USD' | 'SLSH' (default 'USD') — governs the
                    whole transaction; every transaction_items row under
                    it inherits this currency (see "Currencies" below)
transaction_date    date
related_partner_id  uuid (nullable, FK -> partners.id) — set for 'loan'
related_staff_id    uuid (nullable, FK -> staff.id) — set for 'payroll'
                    and 'advance'
note                text
receipt_image_url   text (nullable, not yet implemented in UI)
created_by          uuid (FK -> auth.users.id)
created_at          timestamptz
```

### `transaction_items`
Line items under a transaction. Every transaction gets at least one item
row (even simple, single-invoice ones use a single item) — this keeps
category-reporting logic uniform whether or not there were multiple
invoices. `category` stores the category **name** (text, not a foreign
key) copied from `expense_categories` at save time — kept denormalized so
historical items still read correctly even if a category is later renamed.
```
id                uuid (PK)
transaction_id    uuid (FK -> transactions.id, on delete cascade)
category          text (e.g. 'Fuel', 'Water', 'Food')
amount            numeric
note              text (nullable)
created_at        timestamptz
```

### `expense_categories`
Admin-managed list of categories for `expense` transactions (Fuel, Water,
Food, etc.), so spending can be tracked per category over time. Chosen via
a dropdown on the Add Transaction screen; new categories are added from
the "Manage categories" screen, not typed freely into transactions.
```
id          uuid (PK)
name        text (unique)
created_at  timestamptz
```

### `accounts`
Fixed set of 4 funding buckets, seeded once and not user-addable from the
UI: `Investment`, `Loans`, `Revenue`, `Petty Cash`.
```
id          uuid (PK)
name        text (unique)
created_at  timestamptz
```

### `account_transactions`
Ledger of fund additions and transfers between accounts — separate from
`transactions`, which is the expense/payroll/partner-loan ledger. See
"Funding accounts" below for the full model.
```
id                  uuid (PK)
account_id          uuid (FK -> accounts.id)
type                text, one of: 'fund_add' | 'transfer_in' |
                    'transfer_out' | 'exchange_in' | 'exchange_out'
amount              numeric (> 0)
currency            text, 'USD' | 'SLSH' (default 'USD') — a transfer's
                    transfer_out/transfer_in pair always share one
                    currency (there is no conversion on a transfer); an
                    exchange's exchange_out/exchange_in pair are
                    deliberately in *different* currencies — see
                    "Currency exchange" below
related_account_id  uuid (nullable, FK -> accounts.id) — the other side of
                    a transfer; null for exchange_out/exchange_in, since
                    an exchange has no "other account", just another
                    currency on the same one
note                text (nullable)
transaction_date    date
created_by          uuid (FK -> auth.users.id)
created_at          timestamptz
```

### `settings`
Single-purpose key/value table. Currently holds one row:
```
key         text (PK)   e.g. 'opening_balance'
value       numeric
updated_at  timestamptz
```
`opening_balance` is still summed into Petty Cash's balance (see "Funding
accounts" below) but is pinned at `0` and has **no editable UI** — capital
now enters the system exclusively via `account_transactions` (fund a
fundable account, then transfer it into Petty Cash). Don't re-add a
Settings screen field for this column; if it ever needs to be nonzero
again, that's a deliberate one-off SQL update, not a UI.

## Transaction type semantics (critical business logic)

| Type | Cash movement | Meaning |
|---|---|---|
| `expense` | Out | General expense, categorized via a dropdown sourced from `expense_categories` (fuel, water, food, etc.). Supports "Multiple invoices" — one payment covering several categorized invoices. |
| `payroll` | Out | Net amount actually paid to a staff member (after any advance deduction that period). |
| `loan` | Out | Admin lending money to a colleague (`related_partner_id` set). |
| `advance` | Out | Admin giving a staff member an advance (`related_staff_id` set). |
| `loan_repayment` | In | A colleague repaying a loan. |
| `advance_deduction` | **None** | Records that part of a staff member's outstanding advance was cleared against payroll. No real cash moves — this is internal bookkeeping only. |

**Advance handling detail:** staff advances are not repaid directly by the
employee — they're deducted from future salary. If an advance is large,
the deduction can be spread across multiple payroll cycles (e.g. $100 this
month, $100 next month). Each deduction is its own `advance_deduction` row
with `related_staff_id` set. A staff member's outstanding advance balance
is always **calculated**, never stored:
```
outstanding = sum(advance.amount) - sum(advance_deduction.amount)
```
Similarly, a partner's outstanding loan balance is calculated:
```
outstanding = sum(loan.amount) - sum(loan_repayment.amount)
```

**Recording a loan repayment:** the Add Transaction screen's `loan` type
has a "This is a repayment" toggle. Off, it saves as `loan` (money going
out); on, it saves as `loan_repayment` (money coming in) — same partner
dropdown either way, just flips the saved `type` and cash direction.

**Recording payroll with an advance deduction:** payroll is **not** a
type in the Add Transaction screen (see `payroll_screen.dart` in the file
structure below) — it's a dedicated batch screen, since paying staff
happens for a whole team at once, not one person at a time like an
expense or a loan. For each staff member the screen shows their base
salary and currently owed advance balance (both read-only, fetched from
`transactions`), plus an editable "Repay amount" field; the net to
receive auto-computes as `base_salary - repay_amount`. Saving loops over
every *included* staff member (a per-row toggle lets you skip someone
that cycle) and, for each one, inserts the `payroll` transaction for
their net amount, plus — if repay amount > 0 — a separate
`advance_deduction` transaction (same shared run date, `related_staff_id`
set) for the repay amount, mirroring the "Advance handling detail"
above. Repay amount is validated per-staff against both their owed
balance and their base salary before saving.

## Funding accounts

Four fixed accounts (`accounts` table) sit above the transaction ledger:
**Investment**, **Loans**, **Revenue**, and **Petty Cash**. The first
three are "fundable" — money is added to them directly (a capital
investment, loan proceeds received, revenue collected **including harvest
sale payments — see "Harvests and customer sales" below**). None of them
can be spent from directly. Petty Cash is never funded directly either —
capital always enters via one of the other three first. The only way
money moves into or out of Petty Cash is a **transfer**, and transfers go
both ways: **Transfer to Petty Cash** (from Investment/Loans/Revenue —
the original, and still the only way Petty Cash ever gets funded) and
**Transfer from Petty Cash** (back into one of the other three, e.g. to
correct a misallocation or move cash back into a capital account). The
Transfer screen (`transfer_funds_screen.dart`) has a direction toggle for
this; which side is the fixed "Petty Cash" leg and which side is the
picker flips with it. This is enforced by the UI (Add Funds only ever
targets the fundable three, never Petty Cash directly), not by a DB
constraint.

Every fundable account's balance is **calculated**, never stored, same
philosophy as everywhere else in this app, and — since the `currency`
column landed (see "Currencies" below) — computed **once per currency**,
so each account shows a USD balance and a SLSH balance side by side
rather than one blended number:
```
investment/loans/revenue balance[currency] = sum(fund_add.amount where currency = currency)
                                            + sum(transfer_in.amount where currency = currency)
                                            - sum(transfer_out.amount where currency = currency)
```
(`transfer_in` only happens on these three if money was transferred back
from Petty Cash.) A transfer writes two `account_transactions` rows in
one insert — a `transfer_out` on the source account and a `transfer_in`
on the destination — so each account's history page reads correctly on
its own without a join.

**Petty Cash is the account the rest of the app actually means by "cash
on hand".** Its balance folds in both the accounts ledger and the main
transaction ledger, again **per currency** (`opening_balance` only ever
seeds the USD figure — see "Currencies" below):
```
petty_cash_balance[currency] = (currency == USD ? opening_balance : 0)
                    + sum(account_transactions: transfer_in on Petty Cash where currency = currency)
                    - sum(account_transactions: transfer_out on Petty Cash where currency = currency)
                    + sum(loan_repayment.amount where currency = currency)
                    - sum(expense.amount where currency = currency)
                    - sum(payroll.amount where currency = currency)
                    - sum(loan.amount where currency = currency)
                    - sum(advance.amount where currency = currency)
```
`advance_deduction` is excluded entirely — it never affects cash. The
dashboard's cash-on-hand figure, and the balance that expense/payroll
transactions actually draw down, are this Petty Cash figure — not a
separate global total.

This is all computed client-side in Dart by fetching the small ledger
tables and summing (fine at current scale — a 3-person farm business). If
volume grows significantly, move this aggregation into a Postgres view or
RPC function so the database does the math instead of the client.

**Petty Cash transfers also appear in the Transactions log**, even though
they live in `account_transactions`, not `transactions` — since they move
the same cash-on-hand balance the log is supposed to represent. The
Transactions screen fetches Petty Cash's `transfer_in`/`transfer_out`
rows alongside the `transactions` table and merges them into one
date-sorted list purely for display (as pseudo-rows tagged
`is_transfer: true`); nothing is written to the `transactions` table
itself, so this doesn't create a new "transfer" transaction type or
require a migration. These entries are excluded from the per-type total
cards and the Edit button (there's no edit flow for a transfer — delete
and redo via a fresh transfer if a mistake needs correcting), but do show
under a dedicated "Transfers" filter chip and count toward "All".

## Currencies

The app tracks two currencies — **USD** and **SLSH** (Somaliland
Shilling) — as two parallel ledgers that happen to share the same
tables. There is **no exchange rate anywhere in this app** and never
converts between them; every balance, total, and chart is computed once
per currency and shown side by side (or picked via a toggle — see
below), never summed together into one blended figure.

- **Schema:** a `currency` column (`text`, `'USD' | 'SLSH'`, default
  `'USD'`) lives on every money-bearing table: `transactions`,
  `account_transactions`, `harvests`, `customer_payments`, and `staff`
  (that last one is just a reference default, not summed into anything —
  see the `staff` table doc above). `transaction_items` has **no**
  column of its own: a transaction is one atomic event in one currency,
  so every item under it inherits the parent `transactions.currency`,
  and the existing "items must sum to the parent amount" invariant is
  unaffected. `accounts` (the 4 fixed buckets) also needs no column —
  each account's USD and SLSH balances are just two separately-filtered
  sums over `account_transactions.currency` for that `account_id`.
- **Shared utility:** `lib/utils/currency.dart` defines `enum
  AppCurrency { usd, slsh }` (with `code`, `symbol`, `decimalDigits` —
  SLSH uses 0 decimal places, USD uses 2), the `formatMoney(amount,
  currency)` function every screen calls instead of declaring its own
  `NumberFormat.currency`, a `CurrencyToggle` widget (a two-segment pill
  for picking a currency on an entry form), and a `DualCurrencyStat`
  widget (stacks a USD line and a SLSH line, skipping a line that's
  exactly zero unless both are, for stats that must show both
  currencies at once).
- **Entry forms** each get a `CurrencyToggle` next to their amount
  field: add_transaction_screen.dart, add_funds_screen.dart,
  transfer_funds_screen.dart, exchange_screen.dart,
  add_sale_screen.dart, record_payment_screen.dart, staff_screen.dart's
  add-form, and transaction_log_screen.dart's single-invoice quick-edit
  sheet. A sale's currency is forced onto its upfront payment too (a
  sale and its upfront payment can't be in different currencies without
  a conversion). `add_harvest_screen.dart` has no currency toggle at all
  — a harvest is pure inventory, no price attached until it's sold (see
  "Harvests and customer sales" below). `payroll_screen.dart` is the one
  exception to "one toggle per form": since different staff can be paid
  in different currencies within the same batch run, the toggle is
  **per staff line** (defaulting to that staff member's
  `staff.currency`), and the "Pay N staff" button shows one total per
  currency actually being paid.
- **Display screens** show both currencies at once via
  `DualCurrencyStat` wherever there's a per-entity balance (the
  dashboard's cash-on-hand hero and stat tiles, the Accounts grid,
  account history, customer/partner/staff owed badges and detail
  screens, harvest totals) — this is what "see both, separate" means in
  practice. Screens built around a bar chart or a single running total
  across many transactions (report_screen.dart, transaction_log_screen.
  dart's per-type total cards) instead get a `CurrencyToggle` that
  narrows *only the totals/charts* to one currency at a time (each list
  row still shows its own currency inline regardless of the toggle) —
  a chart can't sensibly overlay two currencies on one axis.
- **Selecting who owes what:** a person or account can owe/hold balances
  in both currencies simultaneously (e.g. a customer with harvests
  priced in both, or a staff member advanced money twice in different
  currencies) — every "owed" or "outstanding" calculation in this app
  is therefore a `Map<AppCurrency, double>`, not a single number, and a
  screen that needs to act on "the" balance (like
  record_payment_screen.dart validating a payment) first has the user
  pick which currency's balance they mean.

### Currency exchange

The one deliberate exception to "no exchange rate anywhere in this
app": `exchange_screen.dart` lets the admin convert part of one
account's existing balance from USD to SLSH or back, for when they
physically exchange cash with a money changer. There's still no
*stored* rate — the form has "You give" and "You receive" fields and the
user types both amounts directly (exactly what the money changer hands
back), rather than the app computing one from a rate it would have to
keep updated. Saving writes two `account_transactions` rows on the
**same** `account_id` (no `related_account_id` — an exchange isn't a
transfer to another account): an `exchange_out` in the source currency
for the "give" amount, and an `exchange_in` in the destination currency
for the "receive" amount. Available balance is validated against that
account's existing balance in the source currency, same pattern as
Transfer. Reached from the Accounts screen's "Exchange" button
(alongside "Add funds"); works on any of the 4 accounts, including
Petty Cash. Every place that sums `account_transactions` by type to
compute a balance (`settings_screen.dart`, `transfer_funds_screen.dart`,
`account_history_screen.dart`, `dashboard_screen.dart`'s cash-on-hand)
treats `exchange_in` like `transfer_in` (+) and `exchange_out` like
`transfer_out` (-) — the same "sum grouped by currency" pattern as the
rest of "Currencies" above, just with two more type values folded in.
Exchanges don't currently show up in the Transactions log's merged
Petty Cash view (that only merges transfers) — they're visible via each
account's own History screen.

## Harvests and customer sales

Harvesting and selling are two separate steps, on purpose: a harvest is
logged as pure inventory (kg + date, `add_harvest_screen.dart`), and can
sit unsold for a few days before anything is sold from it. Every harvest
gets a sequential display code, `#H<harvest_number>` (e.g. "#H3"),
shown as its primary label everywhere it appears (harvests_screen.dart
rows, harvest_detail_screen.dart's AppBar, the harvest picker in
add_sale_screen.dart) — see the `harvests` table doc above for how the
number itself is generated.

Selling — `add_sale_screen.dart` — records one `harvest_sales` row
against a chosen harvest's remaining stock: kg sold, price/kg,
transportation fee (optional), currency, customer, sale date. A single
harvest can have many of these, to different customers, at different
prices, on different dates — `harvest_detail_screen.dart` (reached by
tapping a harvest on `harvests_screen.dart`) is where that shows up: kg
harvested / sold / remaining, and the list of individual sales. A
harvest with 0 remaining kg shows "Fully sold" and its "Add sale" button
disappears.

**Transportation fee:** `add_sale_screen.dart` has an optional
"Transportation fee" field, deducted from what the customer owes for
that sale — the summary box on the form shows "Total value" (raw
`kg_sold * price_per_kg`), "Transportation fee", and "Customer owes"
(the difference) as three distinct lines, but only the fee-adjusted
"Customer owes" figure is what actually flows into the customer's
balance, the harvest's/customer's/dashboard's "total sold"/"outstanding"
stats, and the upfront-payment cap — see the `harvest_sales` table doc
above for the exact formula. The fee itself isn't recorded as a business
expense anywhere; it purely reduces the customer's obligation.

**Note-tagging with the harvest code:** every note field touched by
recording a sale — the `harvest_sales` row's own `note`, the
`customer_payments` row for an upfront payment, and the `fund_add` note
on the Revenue account it triggers — automatically gets that harvest's
`#H<n>` code appended (e.g. a custom note becomes `"some note (#H3)"`;
an empty note just becomes `"#H3"`). This is built in
`add_sale_screen.dart._save()`, not a DB trigger, so it only applies
going forward. It's what makes a Revenue account_transactions row (seen
in account_history_screen.dart, which now shows every entry's note — see
"Funding accounts" above) traceable back to the harvest that produced
it, without a formal FK from `account_transactions` to `harvests`.

The customer can pay some, all, or none of a sale's fee-adjusted value up
front (the upfront field on `add_sale_screen.dart` defaults to `0.00`
and is capped at what the customer owes for that sale, after the
transportation fee). Any unpaid remainder simply adds to the customer's
running balance, to be collected later via the Customers > customer
detail > "Record payment" screen. Both paths — the upfront payment at
sale time and a later standalone payment — go through the same shared
function, `recordCustomerPayment()` (`lib/services/customer_payments.
dart`), which does two things atomically from the app's point of view:
inserts the `customer_payments` row (`sale_id` set for an upfront
payment, null for a standalone one), then inserts a `fund_add` into the
**Revenue** funding account for that same amount **and currency**. This
is the mechanism by which harvest sale proceeds flow into the
funding-accounts system described above — a customer payment always
credits Revenue in its own currency, exactly like an admin manually
adding funds would.

A customer's outstanding balance is always **calculated**, never
stored, and computed **per currency** (see "Currencies" above) since a
customer can owe in either or both — see the `customer_payments` table
doc above for the exact formula.

There is no edit UI for harvests, sales, or customer payments yet — only
add/record and view. If a correction is needed, it's a manual SQL fix for
now, same stance as other not-yet-built edit paths in this app.

## Multiple invoices (multi-category expense entries)

Some payments cover several invoices at once (e.g. "$10 sent, but it's $4
fuel + $3 water + $3 food"). Only the `expense` type supports this. It's
modeled as:
- One `transactions` row with the total amount.
- Multiple `transaction_items` rows underneath, each with a category
  (selected from `expense_categories`), amount, and an optional
  per-invoice note, which must sum (amounts, not notes) to the parent
  transaction's `amount`.

The "Add transaction" screen has a "Multiple invoices" toggle (only shown
when type = `expense`). When off, a single "Category" dropdown is shown
and the one implicit item takes that category (its `transaction_items`
row has no note — only split invoices get a per-row note field). When
on, each invoice row has its own category dropdown, amount field, and a
one-line "Note for this invoice" field underneath (`_LineItem.
noteController` in add_transaction_screen.dart, saved to that item's
`transaction_items.note`), and the UI shows an "Allocated: $X of $Y"
indicator that turns green only when the line items' amounts sum to the
total — this is the validation mechanism, enforced in the Flutter form
before saving (not in SQL). Categories are always chosen from the
managed `expense_categories` list, never typed freely — new categories
are added via the "Manage categories" screen (reachable from the
category dropdown's "Manage categories" link).

**Editing:** single-invoice transactions are edited in place via a bottom
sheet (date, note, amount). Multi-invoice transactions are edited by
reopening the Add Transaction screen pre-filled with the existing data;
saving inserts a new transaction and deletes the original, rather than
updating in place — this avoids having to diff/reconcile individual
`transaction_items` rows.

## Row Level Security (RLS) — the core security model

Every table has RLS enabled. The pattern across `partners`, `staff`,
`transactions`, `transaction_items`, `expense_categories`, `settings`,
`accounts`, `account_transactions`, `customers`, `harvests`,
`harvest_sales`, and `customer_payments` is:

- **Read:** any authenticated user (admin or viewer) — `using (true)`.
- **Write (insert/update/delete):** only rows where the requesting user's
  role in `users` is `admin`:
  ```sql
  (select role from public.users where id = auth.uid()) = 'admin'
  ```
  `transactions` needs an explicit DELETE policy alongside insert/update —
  editing a multi-invoice transaction inserts a replacement and deletes
  the original (see "Editing" above), so without a DELETE policy that
  step silently no-ops (0 rows matched, no error) instead of failing
  loudly, leaving a duplicate behind.

This is enforced at the database level specifically so a technically
savvy partner can't bypass the UI and write data directly via the
Supabase client — hiding buttons in Flutter is a UX nicety, RLS is the
actual security boundary. Any new table added to this project should
follow the same read-all / write-admin-only pattern unless there's a
specific reason to deviate.

## Push notifications

Four kinds of inserts trigger a real Android push notification to the
other two users (not the person who just made it), even if their app is
closed: a `transactions` row (expense/payroll/loan/advance/
loan_repayment — `advance_deduction` is skipped, no real cash moves), a
`harvests` row, a `harvest_sales` row, and a `supplier_purchases` row.
A supplier purchase paid for on the spot would otherwise also fire the
`transactions` push that `services/supplier_payments.dart` triggers for
the paid amount — `notify_new_transaction()` deliberately skips that
one specific case (an `expense` row whose note is exactly
`'Paid for <item>'`, a pattern only `add_purchase_screen.dart` ever
produces) so it's one notification, not two; a standalone supplier
payment (`record_supplier_payment_screen.dart`, free-text note) still
notifies normally, since there's no purchase-level push to cover it.
Firebase Cloud Messaging (FCM) is the delivery mechanism; Supabase is
the trigger.

**Flow:** insert on one of those four tables → its own Postgres trigger
(`notify_new_transaction()` / `notify_new_harvest()` /
`notify_new_harvest_sale()` / `notify_new_supplier_purchase()`,
migrations `supabase_migration_push_notifications.sql` +
`supabase_migration_push_notifications_extended.sql`) → each trigger
builds its own ready-to-send `title`/`body` in SQL (money formatted via
the shared `public.format_money(amount, currency)` helper; the harvest
sale and supplier purchase triggers each join out to look up the
customer/supplier name and, for a sale, the harvest's `#H<n>` code) →
`pg_net.http_post()` to the `notify-transaction` Edge Function
(`supabase/functions/notify-transaction/index.ts`), authenticated by a
shared secret header (not a user JWT — the function has
`verify_jwt: false` and checks the header itself) → the function is now
a thin relay: it just reads every *other* user's rows from
`device_tokens`, gets an FCM v1 OAuth access token from the Firebase
service account, and POSTs one push per device with the trigger's
title/body plus a `data` payload (`kind`, `id`, `title`, `body`, and
`type` for a transaction) for the tapped-notification flow below. A push
whose response says the token is unregistered/invalid gets that
`device_tokens` row deleted, so stale devices clean themselves up over
time. All four trigger functions (and `get_decrypted_secret`, below)
have `execute` revoked from `anon`/`authenticated` — Postgres exposes
even a trigger-only function to direct RPC calls by default, and none of
these are meant to be called except by their own trigger.

**Tapping a notification** opens `notification_detail_screen.dart`, a
single screen shared by all four kinds — it renders straight from the
notification's own `data` payload (no extra fetch), picking its icon,
accent color (via `AppColors.forType()` for a transaction, fixed colors
for the other three kinds) and section label from `data['kind']`.
Getting there is three separate code paths in
`services/push_notifications.dart`'s `setUpPushNotifications()`, since
Android delivers a tap differently depending on what the app was doing:
foreground (the local notification shown by
`flutter_local_notifications` carries the data as its JSON-encoded
`payload`, read back in `onDidReceiveNotificationResponse`), backgrounded
(`FirebaseMessaging.onMessageOpenedApp`), and cold-start / terminated
(`FirebaseMessaging.instance.getInitialMessage()`, checked once at
startup and pushed after the first frame via
`WidgetsBinding.instance.addPostFrameCallback`, so it doesn't race
`AuthGate`'s own routing). All three funnel into the same
`_openNotificationDetail()` helper, which pushes the detail screen via
`main.dart`'s top-level `navigatorKey` — needed because a tap can arrive
before any screen has a `BuildContext` ready (cold start) or from
outside the widget tree entirely.

**`device_tokens`** — one row per device registered for push (a user can
have more than one, e.g. two phones), upserted by
`lib/services/push_notifications.dart`'s `setUpPushNotifications()`
after every login and on FCM token refresh (called from
`auth_gate.dart`), deleted on logout (`app_drawer.dart`'s `_logout`,
before `signOut()` — has to happen before, since deleting needs a still-
valid session to satisfy RLS).
```
id          uuid (PK)
user_id     uuid (FK -> auth.users.id)
token       text (unique)
created_at  timestamptz
updated_at  timestamptz
```
RLS here is *not* the usual read-all/write-admin pattern — a user can
only read/write/delete their **own** rows (`user_id = auth.uid()`).
Nobody's app needs to see anyone else's device tokens; only the
notify-transaction Edge Function does, and it uses the service role key,
which bypasses RLS entirely.

**Secrets live in Supabase Vault, never in the repo or in application
code:**
- `notify_webhook_secret` — a random string, created by the migration
  itself (`vault.create_secret(encode(gen_random_bytes(32), 'hex'), ...)`)
  since it's not really a "secret from somewhere" — it's just proof a
  request came from this database's own trigger, not the internet at
  large.
- `firebase_service_account` — the actual Firebase service account JSON
  (from Firebase Console → Project Settings → Service Accounts →
  "Generate new private key"). This one is a **real credential** and was
  deliberately never passed through an agent or committed anywhere — it
  was added by hand, once, directly in the Supabase SQL Editor. If it
  ever needs rotating, that's the same manual step again, not a
  migration.

Both secrets are read back out by `public.get_decrypted_secret(name)`, a
`security definer` SQL function whose `execute` privilege is revoked
from `anon`/`authenticated` and granted only to `service_role` — so only
the Edge Function (which always calls in with the service role key) can
ever read them, never a logged-in app user.

**Client side (Android only — this app doesn't ship on other
platforms):** `firebase_options.dart` holds this project's Firebase
config, generated by hand from the Android `google-services.json`
downloaded from the Firebase console (safe to commit — scoped to this
Android package name, not a secret the way the service account is).
`android/app/build.gradle.kts` needed `isCoreLibraryDesugaringEnabled`
and the `coreLibraryDesugaring` dependency for
`flutter_local_notifications` (which shows the notification banner when
a push arrives while the app is already in the foreground — FCM only
auto-shows one when the app is backgrounded/terminated), and
`minSdk` was bumped to 23 (`firebase_messaging`'s floor). The
`POST_NOTIFICATIONS` permission (Android 13+) is requested at runtime
via `messaging.requestPermission()` inside `setUpPushNotifications()`.

## Branding

The "Jannatein Agro Business" logo (`assets/images/logo_main.jpeg`) is the
app's one brand asset — shown on the login screen and in the drawer
header. `assets/icon/app_icon.png` is a square, padded version of the
same artwork (letterboxed onto its own sampled background color,
`#EEEFEA`, since the source logo is a wide 1280x714 lockup, not a square
mark) used only as the source for `flutter_launcher_icons` — it generates
the real per-platform launcher icons (Android/iOS/web/Windows/macOS) into
each platform folder. After changing either source image, re-run `dart
run flutter_launcher_icons` to regenerate.

## Flutter project structure

```
lib/
├── main.dart                      — Firebase init (for push
│                                     notifications — see "Push
│                                     notifications" above) then Supabase
│                                     init (autoRefreshToken on, for
│                                     persistent login), MaterialApp,
│                                     exposes the global `supabase` client
│                                     and the top-level `navigatorKey`
│                                     (lets a tapped push notification
│                                     navigate without its own
│                                     BuildContext). `home` is AuthGate,
│                                     not LoginScreen.
├── firebase_options.dart          — this project's Firebase config
│                                     (Android only), hand-generated from
│                                     `android/app/google-services.json`.
│                                     Safe to commit — see "Push
│                                     notifications" above for why this is
│                                     not the same as the Firebase service
│                                     account secret.
├── utils/
│   └── currency.dart               — `AppCurrency` enum (USD/SLSH),
│                                     `formatMoney()`, `CurrencyToggle`,
│                                     and `DualCurrencyStat` — see
│                                     "Currencies" above. Every screen
│                                     that shows or collects money uses
│                                     this instead of a local
│                                     `NumberFormat.currency`.
├── widgets/
│   └── app_drawer.dart            — side navigation Drawer, opened via
│                                     the dashboard's hamburger icon.
│                                     Two visual groups (a plain Divider
│                                     between them, no header text since
│                                     the second group isn't purely
│                                     admin-only): **group 1** — Accounts,
│                                     Harvests, Run Payroll, Transactions,
│                                     Reports; **group 2** — Expense
│                                     categories, Customers, Suppliers,
│                                     Staff, Partners. Accounts/Run
│                                     Payroll/Expense categories/Staff/
│                                     Partners are admin-only (each
│                                     individually gated, not a block
│                                     spread, since group 2 mixes
│                                     admin-only items with Customers/
│                                     Suppliers, which viewers see too);
│                                     Harvests, Transactions, Reports,
│                                     Customers, Suppliers, and Log out are
│                                     always shown, so a viewer sees a
│                                     shorter version of the same two
│                                     groups rather than the groups
│                                     disappearing outright.
│                                     "Accounts" navigates to
│                                     settings_screen.dart — the nav label
│                                     was renamed from "Settings" since
│                                     that screen is entirely about the 4
│                                     funding accounts now (see the
│                                     settings_screen.dart entry below).
├── services/
│   ├── customer_payments.dart     — `recordCustomerPayment()`, the shared
│   │                                 function used by both
│   │                                 add_sale_screen.dart (upfront
│   │                                 payment) and record_payment_screen.dart
│   │                                 (standalone payment): inserts the
│   │                                 `customer_payments` row (`sale_id`
│   │                                 set or null), then a `fund_add` into
│   │                                 the Revenue account for the same
│   │                                 amount. Extracted here specifically
│   │                                 to avoid duplicating that two-step
│   │                                 logic in both screens.
│   ├── supplier_payments.dart     — `recordSupplierPayment()`, the mirror
│   │                                 of `recordCustomerPayment()` for
│   │                                 accounts payable, used by both
│   │                                 add_purchase_screen.dart (paid-now
│   │                                 amount) and
│   │                                 record_supplier_payment_screen.dart
│   │                                 (standalone payment): inserts the
│   │                                 `supplier_payments` row (`purchase_id`
│   │                                 set or null), then — unlike the
│   │                                 customer side — books the same amount
│   │                                 as a real `expense` transaction (see
│   │                                 the `supplier_payments` table doc
│   │                                 above for why) so it draws down
│   │                                 Petty Cash immediately.
│   └── push_notifications.dart    — `setUpPushNotifications()` and
│                                     `unregisterPushToken()` — see "Push
│                                     notifications" above for the full
│                                     flow. Requests the
│                                     `POST_NOTIFICATIONS` permission,
│                                     upserts this device's FCM token into
│                                     `device_tokens`, shows a local
│                                     notification for pushes that arrive
│                                     while the app is already in the
│                                     foreground (FCM only auto-displays
│                                     one when backgrounded/terminated),
│                                     and wires up all three
│                                     tapped-notification paths
│                                     (foreground/background/cold-start)
│                                     to open notification_detail_screen.dart
│                                     via the top-level `navigatorKey`.
├── screens/
│   ├── auth_gate.dart             — the actual `home` widget. Renders
│   │                                 DashboardScreen if a session is
│   │                                 already cached (persisted locally by
│   │                                 supabase_flutter), else LoginScreen;
│   │                                 also reacts live to onAuthStateChange.
│   ├── login_screen.dart          — username/password login (appends
│   │                                 @janatayn.local internally)
│   ├── dashboard_screen.dart      — main screen after login. Fetches
│   │                                 profile (name/role) + all
│   │                                 transactions, harvest_sales,
│   │                                 customer payments, and Revenue
│   │                                 account fund_add rows; computes cash on
│   │                                 hand, outstanding loans/advances,
│   │                                 owed-by-customers, and this-month
│   │                                 totals (including revenue collected
│   │                                 and harvest sales value). The
│   │                                 "This month's cash out" stat
│   │                                 (`_monthCashOut`) sums every
│   │                                 same-month expense + payroll + loan
│   │                                 + advance — deliberately not just
│   │                                 `expense`-type transactions, since
│   │                                 the point is total money leaving the
│   │                                 business this month, not one
│   │                                 category of it (`loan_repayment` and
│   │                                 `advance_deduction` are cash-in /
│   │                                 non-cash respectively, so excluded).
│   │                                 Pull to refresh (`RefreshIndicator`
│   │                                 around the body) re-runs the same
│   │                                 load. Every stat tile and "This
│   │                                 month" row is tappable and
│   │                                 deep-links into the screen with the
│   │                                 underlying log: the cash hero →
│   │                                 Petty Cash's AccountHistoryScreen;
│   │                                 owed-by-partners → PartnersScreen;
│   │                                 owed-by-staff → StaffScreen (both
│   │                                 list every person with their
│   │                                 outstanding balance and open a
│   │                                 detail/history screen on tap — see
│   │                                 those entries below); owed-by-
│   │                                 customers → CustomersScreen (same
│   │                                 list+detail pattern); "This month's
│   │                                 cash out" → TransactionLogScreen
│   │                                 pre-filtered to the current month;
│   │                                 the Expenses/Payroll/Advances "this
│   │                                 month" rows → ReportScreen (with
│   │                                 `initialAccount` and
│   │                                 `initialDateRange` pre-set to the
│   │                                 current calendar month via the
│   │                                 top-level `_thisMonthRange()`
│   │                                 helper); the Revenue row → Revenue's
│   │                                 AccountHistoryScreen; the "Harvest
│   │                                 sales" row (sums `harvest_sales`
│   │                                 where `sale_date` is this month,
│   │                                 not `harvests` - harvesting alone
│   │                                 has no price) → HarvestsScreen. FAB
│   │                                 to add a
│   │                                 transaction (admin only); drawer for
│   │                                 navigation to everything else.
│   ├── add_transaction_screen.dart — type selector (expense/loan/advance
│   │                                 — no payroll, see payroll_screen.dart),
│   │                                 partner/staff dropdown when relevant,
│   │                                 category dropdown (expense only,
│   │                                 sourced from expense_categories),
│   │                                 total amount, "Multiple invoices"
│   │                                 toggle with per-invoice category
│   │                                 dropdowns and allocation validation,
│   │                                 note field. Loan type has a
│   │                                 repayment toggle. Also used for
│   │                                 editing multi-invoice transactions
│   │                                 (pre-filled).
│   ├── payroll_screen.dart        — batch payroll: pays some or all
│   │                                 staff in one run instead of one
│   │                                 transaction at a time. One shared
│   │                                 date for the run; per staff member,
│   │                                 an include toggle plus the same
│   │                                 base salary/owed-advance/repay-amount
│   │                                 breakdown the old payroll type had
│   │                                 (see "Recording payroll with an
│   │                                 advance deduction" above). Reached
│   │                                 from the drawer, admin only.
│   ├── expense_categories_screen.dart — list of expense categories with
│   │                                 an add-new form; reached via the
│   │                                 "Manage categories" link on the Add
│   │                                 Transaction screen or the drawer.
│   ├── staff_screen.dart          — list of staff, each showing base
│   │                                 salary and an "Owes"/"Settled" badge
│   │                                 with their outstanding advance
│   │                                 balance (sum(advance.amount) -
│   │                                 sum(advance_deduction.amount) for
│   │                                 that staff member, same formula as
│   │                                 the "Advance handling detail"
│   │                                 section above), plus an add-new
│   │                                 form. Tapping a staff member opens
│   │                                 staff_detail_screen.dart. Reached
│   │                                 from the drawer.
│   ├── staff_detail_screen.dart   — one staff member's outstanding
│   │                                 advance balance plus their merged
│   │                                 history: "Advance given" (increases
│   │                                 what they owe), "Deducted from
│   │                                 payroll" (reduces it, shown without
│   │                                 a +/- sign since — per the Design
│   │                                 language section — advance_deduction
│   │                                 moves no real cash), and "Payroll
│   │                                 paid" (shown for context; doesn't
│   │                                 affect the advance balance). Same
│   │                                 merge-and-sort-by-date shape as
│   │                                 customer_detail_screen.dart, but
│   │                                 read-only — no record-payment flow,
│   │                                 since advances are only ever cleared
│   │                                 via a payroll deduction, not repaid
│   │                                 directly.
│   ├── partners_screen.dart       — list of partners, each showing an
│   │                                 "Owes"/"Settled" badge with their
│   │                                 outstanding loan balance (calculated
│   │                                 the same way as everywhere else:
│   │                                 sum(loan.amount) -
│   │                                 sum(loan_repayment.amount) for that
│   │                                 partner), plus an add-new form.
│   │                                 Tapping a partner opens
│   │                                 partner_detail_screen.dart. Reached
│   │                                 from the drawer.
│   ├── partner_detail_screen.dart — one partner's outstanding loan
│   │                                 balance plus their merged history:
│   │                                 "Loan given" (increases what they
│   │                                 owe) and "Repayment" (reduces it),
│   │                                 sorted newest first — same
│   │                                 merge-and-sort-by-date shape as
│   │                                 staff_detail_screen.dart /
│   │                                 customer_detail_screen.dart. Each
│   │                                 entry's label appends the
│   │                                 transaction's own note when present.
│   │                                 Read-only — no add/edit flow here;
│   │                                 loans and repayments are still
│   │                                 recorded via
│   │                                 add_transaction_screen.dart's loan
│   │                                 type and its "This is a repayment"
│   │                                 toggle.
│   ├── settings_screen.dart       — the "Accounts" section: the 4
│   │                                 funding-account balances as tappable
│   │                                 cards (→ AccountHistoryScreen) plus
│   │                                 "Add funds"/"Exchange" buttons and a
│   │                                 "Transfer" link. No opening-balance
│   │                                 field anymore - see the `settings`
│   │                                 table note above. Reached from the
│   │                                 drawer.
│   ├── add_funds_screen.dart      — adds funds to Investment, Loans, or
│   │                                 Revenue only (Petty Cash excluded).
│   │                                 Inserts one `fund_add` row.
│   ├── exchange_screen.dart       — converts part of one account's
│   │                                 existing balance from USD to SLSH
│   │                                 or back (see "Currency exchange"
│   │                                 above). Works on any of the 4
│   │                                 accounts, including Petty Cash.
│   │                                 User types both the amount given
│   │                                 and the amount received — no rate
│   │                                 is stored. Inserts an
│   │                                 exchange_out + exchange_in pair on
│   │                                 the same account.
│   ├── transfer_funds_screen.dart — moves funds between Petty Cash and one
│   │                                 of Investment/Loans/Revenue, either
│   │                                 direction. A "To Petty Cash / From
│   │                                 Petty Cash" toggle at the top swaps
│   │                                 which side is the fixed Petty Cash
│   │                                 leg and which side is the picker;
│   │                                 the picker always shows each
│   │                                 candidate account's available
│   │                                 balance and validates the amount
│   │                                 against it (Petty Cash's own balance
│   │                                 is computed with the same formula as
│   │                                 the dashboard/account history when
│   │                                 it's the source). Inserts a
│   │                                 transfer_out + transfer_in pair
│   │                                 either way.
│   ├── account_history_screen.dart — balance + ledger for one account.
│   │                                 For Petty Cash, folds in the main
│   │                                 `transactions` table (expenses,
│   │                                 payroll, loans, advances,
│   │                                 repayments) alongside its
│   │                                 transfer_in/transfer_out rows, since
│   │                                 that's what actually moves its
│   │                                 balance (transfer_out on Petty Cash
│   │                                 only exists since transfers became
│   │                                 bidirectional). Also shows
│   │                                 exchange_in/exchange_out rows
│   │                                 ("Exchanged from/to <currency>")
│   │                                 for any account, including Petty
│   │                                 Cash - not shown in the Transactions
│   │                                 log, only here. Each card also shows
│   │                                 that entry's `note` when present
│   │                                 (e.g. a Revenue fund_add from a
│   │                                 harvest sale payment shows its
│   │                                 `#H<n>` code here - see "Harvests
│   │                                 and customer sales" above).
│   ├── transaction_log_screen.dart — searchable, filterable list of all
│   │                                 transactions, plus Petty Cash's
│   │                                 transfer_in/transfer_out rows merged
│   │                                 in for display only (see "Funding
│   │                                 accounts" above). Takes an optional
│   │                                 `initialDateRange` constructor param
│   │                                 (seeds `_dateRange`) so a dashboard
│   │                                 tile can deep-link straight into a
│   │                                 pre-filtered view. Search bar (matches
│   │                                 note/partner/staff/category), date
│   │                                 range filter, the 4 main per-type
│   │                                 total cards (Expenses/Payroll/
│   │                                 Loans/Advances — transfers excluded),
│   │                                 type filter chips (including
│   │                                 "Transfers"), and admin-only edit
│   │                                 button per row, hidden for merged
│   │                                 transfer rows since there's no edit
│   │                                 flow for them (row title always
│   │                                 shows the category for expense
│   │                                 transactions; tapping edit opens a
│   │                                 bottom sheet for single-invoice,
│   │                                 full screen for multi-invoice).
│   ├── report_screen.dart         — per-account reporting, reached from
│   │                                 the drawer (defaults to the Payroll
│   │                                 tab with no date filter) or
│   │                                 deep-linked from a dashboard stat
│   │                                 tile via its optional
│   │                                 `initialAccount`/`initialDateRange`
│   │                                 constructor params, which just seed
│   │                                 `_selectedAccount`/`_dateRange` — the
│   │                                 screen behaves identically either
│   │                                 way once opened. A "Payroll /
│   │                                 Advances / Loans / Expenses" chip
│   │                                 selector switches which transaction
│   │                                 type(s) are shown, with a contextual
│   │                                 filter (staff for Payroll/Advances,
│   │                                 partner for Loans, category for
│   │                                 Expenses) plus a shared date-range
│   │                                 filter and summary total cards.
│   │                                 Payroll/
│   │                                 Advances/Loans show a filtered
│   │                                 transaction list; Expenses instead
│   │                                 shows two bar charts (spend by
│   │                                 category, capped to top 7 + "Other";
│   │                                 spend by month, last 6 months) built
│   │                                 with `fl_chart`, single-hue (the
│   │                                 app's expense red) since it's a
│   │                                 magnitude comparison, not identity -
│   │                                 see the dataviz skill's form-choice
│   │                                 guidance before changing this.
│   │                                 Read-only, so visible to viewers too.
│   ├── harvests_screen.dart       — every harvest logged, newest first,
│   │                                 labeled by its `#H<n>` display code
│   │                                 (`harvest_number`) rather than just
│   │                                 its date. Top summary is two stat
│   │                                 tiles — "Total harvests" (count, with
│   │                                 total kg harvested as a parenthetical
│   │                                 sub-line) and "Total kg sold" (with
│   │                                 total kg remaining as a parenthetical
│   │                                 sub-line, via the local
│   │                                 `_StatValueWithSub` widget) — plus two
│   │                                 cards for total sold value / total
│   │                                 outstanding, both `DualCurrencyStat`s
│   │                                 summed from `harvest_sales`
│   │                                 fee-adjusted (`kg_sold * price_per_kg
│   │                                 - transport_fee`), not `harvests`,
│   │                                 since a harvest alone has no price.
│   │                                 Each row shows kg harvested/sold,
│   │                                 either "Fully sold" or "`X` kg left",
│   │                                 and — when that harvest has any sales
│   │                                 — a `DualCurrencyStat` of its own
│   │                                 fee-adjusted sale value underneath;
│   │                                 tapping one opens
│   │                                 harvest_detail_screen.dart. FAB to
│   │                                 add a harvest, admin only. Read-only
│   │                                 list visible to viewers.
│   ├── add_harvest_screen.dart    — logs a harvest as pure inventory
│   │                                 intake: date, kg, note. No
│   │                                 customer/price/currency — see
│   │                                 "Harvests and customer sales" above.
│   │                                 Admin only.
│   ├── harvest_detail_screen.dart — one harvest's kg harvested/sold/
│   │                                 remaining plus the list of
│   │                                 individual sales against it (a
│   │                                 harvest can be sold to more than
│   │                                 one customer). Takes a required
│   │                                 `harvestNumber` param; AppBar title
│   │                                 is `#H<n> · <date>`. Each sale row
│   │                                 shows its transport fee inline
│   │                                 (`− <fee> transport`) when set, and
│   │                                 its trailing amount is the
│   │                                 fee-adjusted amount the customer
│   │                                 owes for that sale, not the raw
│   │                                 kg × price value. "Add sale" button
│   │                                 (admin only) opens
│   │                                 add_sale_screen.dart pre-selecting
│   │                                 this harvest; replaced by a "Fully
│   │                                 sold" indicator once remaining kg
│   │                                 is ~0.
│   ├── add_sale_screen.dart       — records one sale against a chosen
│   │                                 harvest's remaining stock: harvest
│   │                                 picker (only harvests with
│   │                                 remaining kg > 0, each row labeled
│   │                                 by its `#H<n>` code, pre-selected
│   │                                 when opened from
│   │                                 harvest_detail_screen.dart),
│   │                                 customer dropdown (with a
│   │                                 "+ Add customer" shortcut into
│   │                                 customers_screen.dart), kg to sell
│   │                                 (validated against that harvest's
│   │                                 remaining stock), currency, price/kg
│   │                                 (computed total value shown live),
│   │                                 an optional transportation fee
│   │                                 (subtracted from the total value to
│   │                                 get what the customer owes for this
│   │                                 sale — the summary box shows Total
│   │                                 value, and, only when a fee is set,
│   │                                 Transportation fee and the
│   │                                 fee-adjusted Customer owes),
│   │                                 sale date (independent of the
│   │                                 harvest's own date — this is what
│   │                                 lets a sale happen a few days
│   │                                 later), and an optional upfront
│   │                                 payment (defaults to 0, capped at
│   │                                 the fee-adjusted amount owed, not
│   │                                 the raw total value). On save, the
│   │                                 sale's `note` has the harvest's
│   │                                 `#H<n>` code appended automatically
│   │                                 (`(#H<n>)`, or just the code if the
│   │                                 note was empty); if upfront > 0,
│   │                                 calls `recordCustomerPayment()`
│   │                                 after inserting the `harvest_sales`
│   │                                 row, passing a note that also carries
│   │                                 the `#H<n>` code — see "Harvests and
│   │                                 customer sales" above. Admin only.
│   ├── customers_screen.dart      — list of customers with each one's
│   │                                 current owed/settled balance
│   │                                 (calculated from harvest_sales +
│   │                                 customer_payments), plus an add-new
│   │                                 form (name, phone, note). Tapping a
│   │                                 customer opens
│   │                                 customer_detail_screen.dart.
│   ├── customer_detail_screen.dart — one customer's balance plus a merged,
│   │                                 date-sorted history of their
│   │                                 harvest sales and payments. "Record
│   │                                 payment" button (admin only) opens
│   │                                 record_payment_screen.dart.
│   ├── record_payment_screen.dart — standalone form (date, amount, note)
│   │                                 for a customer paying down their
│   │                                 balance outside of a sale;
│   │                                 validates against their current
│   │                                 outstanding balance and calls the
│   │                                 same `recordCustomerPayment()`
│   │                                 shared function. Admin only.
│   ├── suppliers_screen.dart      — accounts-payable mirror of
│   │                                 customers_screen.dart: list of
│   │                                 suppliers with each one's current
│   │                                 owed/settled balance (calculated from
│   │                                 supplier_purchases + supplier_payments,
│   │                                 "You owe"/"Settled" instead of
│   │                                 "Owes"/"Settled" since the direction
│   │                                 is reversed), plus an add-new form
│   │                                 (name, phone, note). FAB ("Purchase",
│   │                                 admin only) opens
│   │                                 add_purchase_screen.dart with no
│   │                                 supplier pre-selected. Tapping a
│   │                                 supplier opens
│   │                                 supplier_detail_screen.dart.
│   ├── add_purchase_screen.dart   — records something bought from a
│   │                                 supplier: supplier dropdown (with a
│   │                                 "+ Add supplier" shortcut into
│   │                                 suppliers_screen.dart, pre-selected
│   │                                 when opened from
│   │                                 supplier_detail_screen.dart), a
│   │                                 free-text item description, currency,
│   │                                 total cost, and how much was paid
│   │                                 right now (defaults to 0, capped at
│   │                                 the total cost — same "often partial
│   │                                 or nothing" shape as a harvest sale's
│   │                                 upfront payment, just for money going
│   │                                 out instead of in), date, note. On
│   │                                 save, inserts the
│   │                                 `supplier_purchases` row, then — if
│   │                                 paid-now > 0 — calls
│   │                                 `recordSupplierPayment()`. Admin only.
│   ├── supplier_detail_screen.dart — one supplier's balance plus a merged,
│   │                                 date-sorted history of purchases
│   │                                 (labeled by their item description)
│   │                                 and payments — same shape as
│   │                                 customer_detail_screen.dart, signs
│   │                                 flipped to match ("+"/cashIn for a
│   │                                 payment made, "-"/expense for a
│   │                                 purchase). "Add purchase" and "Record
│   │                                 payment" buttons (admin only) open
│   │                                 add_purchase_screen.dart (pre-selecting
│   │                                 this supplier) and
│   │                                 record_supplier_payment_screen.dart.
│   ├── record_supplier_payment_screen.dart — standalone form (date,
│   │                                 amount, note) for paying a supplier
│   │                                 down outside of a purchase; validates
│   │                                 against what's currently owed to them
│   │                                 and calls the same
│   │                                 `recordSupplierPayment()` shared
│   │                                 function. Admin only.
│   └── notification_detail_screen.dart — opened by tapping a push
│                                     notification (see "Push
│                                     notifications" above); renders
│                                     entirely from the tapped
│                                     notification's own data payload, no
│                                     fetch. Shared by all four
│                                     notification kinds.
```

Dashboard and transaction log both independently fetch and sum
transactions client-side — there's no shared state/provider layer yet. If
more screens need the same aggregated numbers, consider introducing a
shared data layer (e.g. Riverpod/Provider) rather than each screen
re-fetching and re-summing independently.

## Design language

**All tokens live in `lib/theme/app_theme.dart` and the shared widgets in
`lib/widgets/app_ui.dart`. Use those rather than hardcoding colors,
radii or shadows** — a screen that reaches for `Colors.grey.shade200` or
a raw hex is drifting from the system.

- **Brand palette** (`AppColors`), taken from the logo: `brandGreen`
  `#1B5E3A` (primary), `brandGreenLight` `#2E8B57`, `brandGreenDeep`
  `#0F3D25`, `brandNavy` `#1E3A5F`, `brandRed` `#B93B36`, `cream`
  `#EEEFEA`.
- Background: `AppColors.canvas` `#F5F6F1` (soft, faintly warm off-white);
  AppBars are flat (`elevation: 0`) on that same background, styled once
  in `AppTheme.light` rather than per screen.
- Ink: `AppColors.ink` for primary text, `inkSecondary` for labels,
  `inkMuted` for dates/hints. Don't use `Colors.grey[...]`.
- Currency: always formatted via `formatMoney(amount, currency)`
  (`lib/utils/currency.dart`) — never a local `NumberFormat.currency`
  declaration or manual string interpolation like
  `'\$${value.toStringAsFixed(2)}'`. See "Currencies" above for the full
  model (`AppCurrency`, `CurrencyToggle`, `DualCurrencyStat`).
- **Cards** use the `AppCard` widget (or `AppStyles.card`): white, 16px
  radius, hairline border, and a soft low-contrast shadow. Stat tiles use
  `AppCard(accent: color)` / `AppStyles.accentCard`, which tints the
  border with the metric's color.
- **Color coding by transaction type** — `AppColors.forType(type)` is the
  single source of truth: `expense` = red, `payroll` = orange, `loan` =
  blue, `advance` = purple, `loan_repayment`/cash-in = green,
  `advance_deduction`/neutral = grey (shown without a +/- sign since no
  cash moves). Each type also carries an icon, rendered in an `IconBadge`
  (a tinted rounded square) — that badge is the app's main splash of
  color and appears in lists, the drawer, and the dashboard.
- **The cash-on-hand hero** on the dashboard is the one gradient surface
  (brand green, white text, decorative rings). Keep gradients rare — one
  hero per screen at most, or the app starts to look noisy.
- Categories/staff/partners get a *decorative* stable color via
  `AppColors.accentFor(name)` and initials via `InitialsAvatar`. This
  encodes nothing; it just keeps long lists lively.
- Type selector on Add Transaction uses tinted, icon-bearing buttons in a
  2×2 grid; filter chips elsewhere are `ChoiceChip` pills tinted with the
  type's own color when selected.
- Shared states: `EmptyState` for empty lists, `ErrorNote` for inline
  errors (never bare red text), `SectionLabel` for uppercase group
  headers, `BrandLogo` for the logo on its cream plate.

## Conventions to preserve when adding features

0. New screens should be built from `AppTheme` + `lib/widgets/app_ui.dart`
   (`AppCard`, `IconBadge`, `StatTile`, `SectionLabel`, `EmptyState`,
   `ErrorNote`). Don't set `backgroundColor`/`elevation` on Scaffold or
   AppBar — the theme already does, and overriding it is what makes
   screens drift apart visually.
1. Any new writable table needs the same RLS pattern: read = all
   authenticated users, write = admin role only.
2. New transaction-adjacent features should go through `transactions` +
   `transaction_items` (expense/payroll/partner-loan events),
   `accounts` + `account_transactions` (funding/capital events),
   `customers` + `harvests` + `customer_payments` (harvest sales and what
   customers owe), or `suppliers` + `supplier_purchases` +
   `supplier_payments` (purchases on credit and what's owed to
   suppliers), not new bespoke tables, unless the data genuinely isn't a
   cash event.
3. Partners are still just a simple name lookup — no per-partner
   equity/profit-share fields. Capital *is* tracked now (see "Funding
   accounts"), but it's tracked at the business level via `accounts`, not
   attributed to individual partners.
4. Keep the opening balance / calculated-balance approach — avoid adding
   stored running-balance columns (including a stored balance on
   `accounts`) that could drift out of sync with the ledger tables.
5. Every money-bearing insert must set `currency` (from an `AppCurrency`
   the user picked via `CurrencyToggle`, not a hardcoded default) and
   every aggregate/sum must group by currency — never add a USD amount
   to a SLSH amount. See "Currencies" above.
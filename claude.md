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
One row per harvest, which doubles as its sale record — see "Harvests
and customer sales" below.
```
id                uuid (PK)
harvest_date      date
kg_harvested      numeric (> 0)
price_per_kg      numeric (>= 0)
customer_id       uuid (FK -> customers.id) — not nullable; a harvest is
                  logged already knowing who it was sold to
note              text (nullable)
created_by        uuid (FK -> auth.users.id)
created_at        timestamptz
```
Total sale value (`kg_harvested * price_per_kg`) is **calculated, never
stored** — same philosophy as everywhere else in this app.

### `customer_payments`
Every payment a customer makes — the upfront amount recorded at harvest
time *and* any later payment — lands here as one ledger.
```
id             uuid (PK)
customer_id    uuid (FK -> customers.id)
harvest_id     uuid (nullable, FK -> harvests.id) — context only; a
               payment always reduces the customer's overall balance,
               never one specific harvest's balance
amount         numeric (> 0)
payment_date   date
note           text (nullable)
created_by     uuid (FK -> auth.users.id)
created_at     timestamptz
```
A customer's outstanding balance is always calculated:
```
outstanding = sum(harvests.kg_harvested * harvests.price_per_kg for that customer)
            - sum(customer_payments.amount for that customer)
```

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
type                text, one of: 'fund_add' | 'transfer_in' | 'transfer_out'
amount              numeric (> 0)
related_account_id  uuid (nullable, FK -> accounts.id) — the other side of
                    a transfer
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
can be spent from directly, and Petty Cash cannot be funded any other
way: the **only** path into Petty Cash is a transfer from one of the
other three. This is enforced by the UI (Add Funds only offers the
fundable three; Transfer only offers them as a source and always targets
Petty Cash), not by a DB constraint.

Every account's balance is **calculated**, never stored, same philosophy
as everywhere else in this app:
```
investment/loans/revenue balance = sum(fund_add.amount)
                                  - sum(transfer_out.amount)
```
A transfer writes two `account_transactions` rows in one insert — a
`transfer_out` on the source account and a `transfer_in` on Petty Cash —
so each account's history page reads correctly on its own without a join.

**Petty Cash is the account the rest of the app actually means by "cash
on hand".** Its balance folds in both the accounts ledger and the main
transaction ledger:
```
petty_cash_balance = opening_balance
                    + sum(account_transactions: transfer_in on Petty Cash)
                    + sum(loan_repayment.amount)
                    - sum(expense.amount)
                    - sum(payroll.amount)
                    - sum(loan.amount)
                    - sum(advance.amount)
```
`advance_deduction` is excluded entirely — it never affects cash. The
dashboard's cash-on-hand figure, and the balance that expense/payroll
transactions actually draw down, are this Petty Cash figure — not a
separate global total.

This is all computed client-side in Dart by fetching the small ledger
tables and summing (fine at current scale — a 3-person farm business). If
volume grows significantly, move this aggregation into a Postgres view or
RPC function so the database does the math instead of the client.

## Harvests and customer sales

A `harvests` row doubles as its own sale record: logging a harvest means
recording how many kg were picked, the price per kg, and which customer
it was sold to, all at once — there's no separate "sale" step. Total sale
value (`kg_harvested * price_per_kg`) is **calculated, never stored**,
same philosophy as everywhere else.

The customer can pay some, all, or none of that value up front (the
upfront field defaults to `0.00` and is capped at the total value). Any
unpaid remainder simply adds to the customer's running balance, to be
collected later via the Customers > customer detail > "Record payment"
screen. Both paths — the upfront payment at harvest time and a later
standalone payment — go through the same shared function,
`recordCustomerPayment()` (`lib/services/customer_payments.dart`), which
does two things atomically from the app's point of view: inserts the
`customer_payments` row, then inserts a `fund_add` into the **Revenue**
funding account for that same amount. This is the mechanism by which
harvest sale proceeds flow into the funding-accounts system described
above — a customer payment always credits Revenue, exactly like an
admin manually adding funds would.

A customer's outstanding balance is always **calculated**, never stored:
```
outstanding = sum(harvests.kg_harvested * harvests.price_per_kg for that customer)
            - sum(customer_payments.amount for that customer)
```
`customer_payments.harvest_id` is nullable and purely contextual (which
harvest a payment was originally tied to, if any) — a payment always
reduces the customer's overall balance, never one specific harvest's
balance, since there's no per-harvest balance concept.

There is no edit UI for harvests or customer payments yet — only
add/record and view. If a correction is needed, it's a manual SQL fix for
now, same stance as other not-yet-built edit paths in this app.

## Multiple invoices (multi-category expense entries)

Some payments cover several invoices at once (e.g. "$10 sent, but it's $4
fuel + $3 water + $3 food"). Only the `expense` type supports this. It's
modeled as:
- One `transactions` row with the total amount.
- Multiple `transaction_items` rows underneath, each with a category
  (selected from `expense_categories`) and amount, which must sum to the
  parent transaction's `amount`.

The "Add transaction" screen has a "Multiple invoices" toggle (only shown
when type = `expense`). When off, a single "Category" dropdown is shown
and the one implicit item takes that category. When on, each invoice row
has its own category dropdown + amount field, and the UI shows an
"Allocated: $X of $Y" indicator that turns green only when the line items
sum matches the total — this is the validation mechanism, enforced in the
Flutter form before saving (not in SQL). Categories are always chosen from
the managed `expense_categories` list, never typed freely — new
categories are added via the "Manage categories" screen (reachable from
the category dropdown's "Manage categories" link).

**Editing:** single-invoice transactions are edited in place via a bottom
sheet (date, note, amount). Multi-invoice transactions are edited by
reopening the Add Transaction screen pre-filled with the existing data;
saving inserts a new transaction and deletes the original, rather than
updating in place — this avoids having to diff/reconcile individual
`transaction_items` rows.

## Row Level Security (RLS) — the core security model

Every table has RLS enabled. The pattern across `partners`, `staff`,
`transactions`, `transaction_items`, `expense_categories`, `settings`,
`accounts`, `account_transactions`, `customers`, `harvests`, and
`customer_payments` is:

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
├── main.dart                      — Supabase init (autoRefreshToken on,
│                                     for persistent login), MaterialApp,
│                                     exposes the global `supabase` client.
│                                     `home` is AuthGate, not LoginScreen.
├── widgets/
│   └── app_drawer.dart            — side navigation Drawer, opened via
│                                     the dashboard's hamburger icon.
│                                     Always shows Transactions + Reports
│                                     + Log out (read-only, so viewers see
│                                     them too); shows "Run Payroll" plus a
│                                     "MANAGE" section (Expense categories,
│                                     Staff, Partners, Accounts) for
│                                     admins only. Also always shows
│                                     Harvests + Customers (read-only for
│                                     viewers, same as Transactions/Reports).
│                                     "Accounts" navigates to
│                                     settings_screen.dart — the nav label
│                                     was renamed from "Settings" since
│                                     that screen is entirely about the 4
│                                     funding accounts now (see the
│                                     settings_screen.dart entry below).
├── services/
│   └── customer_payments.dart     — `recordCustomerPayment()`, the shared
│                                     function used by both
│                                     add_harvest_screen.dart (upfront
│                                     payment) and record_payment_screen.dart
│                                     (standalone payment): inserts the
│                                     `customer_payments` row, then a
│                                     `fund_add` into the Revenue account
│                                     for the same amount. Extracted here
│                                     specifically to avoid duplicating
│                                     that two-step logic in both screens.
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
│   │                                 transactions, harvests, customer
│   │                                 payments, and Revenue account
│   │                                 fund_add rows; computes cash on
│   │                                 hand, outstanding loans/advances,
│   │                                 owed-by-customers, and this-month
│   │                                 totals (including revenue collected
│   │                                 and harvest sales value). Pull to
│   │                                 refresh (`RefreshIndicator` around
│   │                                 the body) re-runs the same load.
│   │                                 FAB to add a transaction (admin
│   │                                 only); drawer for navigation to
│   │                                 everything else.
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
│   ├── staff_screen.dart          — list of staff (name + base salary)
│   │                                 with an add-new form. Reached from
│   │                                 the drawer.
│   ├── partners_screen.dart       — list of partners with an add-new
│   │                                 form. Reached from the drawer.
│   ├── settings_screen.dart       — the "Accounts" section: the 4
│   │                                 funding-account balances as tappable
│   │                                 cards (→ AccountHistoryScreen) plus
│   │                                 "Add funds" and "Transfer" buttons.
│   │                                 No opening-balance field anymore -
│   │                                 see the `settings` table note above.
│   │                                 Reached from the drawer.
│   ├── add_funds_screen.dart      — adds funds to Investment, Loans, or
│   │                                 Revenue only (Petty Cash excluded).
│   │                                 Inserts one `fund_add` row.
│   ├── transfer_funds_screen.dart — moves funds from Investment/Loans/
│   │                                 Revenue into Petty Cash — the only
│   │                                 way Petty Cash is funded. Shows each
│   │                                 source account's available balance
│   │                                 and validates against it. Inserts a
│   │                                 transfer_out + transfer_in pair.
│   ├── account_history_screen.dart — balance + ledger for one account.
│   │                                 For Petty Cash, folds in the main
│   │                                 `transactions` table (expenses,
│   │                                 payroll, loans, advances,
│   │                                 repayments) alongside its
│   │                                 transfer_in rows, since that's what
│   │                                 actually moves its balance.
│   ├── transaction_log_screen.dart — searchable, filterable list of all
│   │                                 transactions. Search bar (matches
│   │                                 note/partner/staff/category), date
│   │                                 range filter, the 4 main per-type
│   │                                 total cards (Expenses/Payroll/
│   │                                 Loans/Advances), type filter chips,
│   │                                 and admin-only edit button per row
│   │                                 (row title always shows the
│   │                                 category for expense transactions;
│   │                                 tapping edit opens a bottom sheet for
│   │                                 single-invoice, full screen for
│   │                                 multi-invoice).
│   ├── report_screen.dart         — per-account reporting, reached from
│   │                                 the drawer. A "Payroll / Advances /
│   │                                 Loans / Expenses" chip selector
│   │                                 switches which transaction type(s)
│   │                                 are shown, with a contextual filter
│   │                                 (staff for Payroll/Advances, partner
│   │                                 for Loans, category for Expenses)
│   │                                 plus a shared date-range filter and
│   │                                 summary total cards. Payroll/
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
│   │                                 with summary stats (count, total kg,
│   │                                 total value, total outstanding). FAB
│   │                                 to add a harvest, admin only.
│   │                                 Read-only list visible to viewers.
│   ├── add_harvest_screen.dart    — logs a harvest and its sale in one
│   │                                 form: date, kg, price/kg (computed
│   │                                 total value shown live), customer
│   │                                 dropdown (with a "+ Add customer"
│   │                                 shortcut into customers_screen.dart),
│   │                                 and an optional upfront payment
│   │                                 (defaults to 0, capped at total
│   │                                 value). If upfront > 0, calls
│   │                                 `recordCustomerPayment()` after
│   │                                 inserting the harvest. Admin only.
│   ├── customers_screen.dart      — list of customers with each one's
│   │                                 current owed/settled balance
│   │                                 (calculated from harvests +
│   │                                 customer_payments), plus an add-new
│   │                                 form (name, phone, note). Tapping a
│   │                                 customer opens
│   │                                 customer_detail_screen.dart.
│   ├── customer_detail_screen.dart — one customer's balance plus a merged,
│   │                                 date-sorted history of their
│   │                                 harvest sales and payments. "Record
│   │                                 payment" button (admin only) opens
│   │                                 record_payment_screen.dart.
│   └── record_payment_screen.dart — standalone form (date, amount, note)
│                                     for a customer paying down their
│                                     balance outside of a harvest;
│                                     validates against their current
│                                     outstanding balance and calls the
│                                     same `recordCustomerPayment()`
│                                     shared function. Admin only.
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
- Currency: always formatted via `intl`'s `NumberFormat.currency(symbol:
  '\$', decimalDigits: 2)` — never manual string interpolation like
  `'\$${value.toStringAsFixed(2)}'`, to keep thousands separators
  consistent everywhere.
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
   `accounts` + `account_transactions` (funding/capital events), or
   `customers` + `harvests` + `customer_payments` (harvest sales and what
   customers owe), not new bespoke tables, unless the data genuinely
   isn't a cash event.
3. Partners are still just a simple name lookup — no per-partner
   equity/profit-share fields. Capital *is* tracked now (see "Funding
   accounts"), but it's tracked at the business level via `accounts`, not
   attributed to individual partners.
4. Keep the opening balance / calculated-balance approach — avoid adding
   stored running-balance columns (including a stored balance on
   `accounts`) that could drift out of sync with the ledger tables.
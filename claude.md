# Farm Cash Manager — Project Reference

A Flutter + Supabase app for tracking farm business cash flow: bills, payroll,
loans to partners, and staff advances. Built by one admin (the person who
controls all cash) with two partners who have read-only visibility.

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

There is no capital-tracking feature. Initial investments are recorded in
external documents, not in the app. No new capital injections are tracked
either — partners' ownership stake is fixed and external to this system.

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

### `settings`
Single-purpose key/value table. Currently holds one row:
```
key         text (PK)   e.g. 'opening_balance'
value       numeric
updated_at  timestamptz
```
`opening_balance` anchors the running cash calculation (see Cash flow
logic below), since the app doesn't track capital injections.

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

**Recording payroll with an advance deduction:** when type = `payroll`
and a staff member is selected, the form shows their base salary and
currently owed advance balance (both read-only, fetched from
`transactions`), plus an editable "Repay amount" field. The total amount
field becomes read-only and auto-computes as
`base_salary - repay_amount` — that's what's actually paid out. Saving
inserts the `payroll` transaction for that net amount, and if repay
amount > 0, also inserts a separate `advance_deduction` transaction
(same date, `related_staff_id` set) for the repay amount — mirroring the
"Advance handling detail" above. Repay amount is validated against both
the owed balance and the base salary before saving.

## Cash flow calculation

There is no running `cash_on_hand` column. It's computed on the fly:

```
cash_on_hand = opening_balance
             + sum(loan_repayment.amount)
             - sum(expense.amount)
             - sum(payroll.amount)
             - sum(loan.amount)
             - sum(advance.amount)
```
`advance_deduction` is excluded entirely — it never affects cash.

This is currently computed client-side in Dart by fetching all
transactions and summing (fine at current scale — a 3-person farm
business). If transaction volume grows significantly, move this
aggregation into a Postgres view or RPC function so the database does the
math instead of the client.

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
`transactions`, `transaction_items`, `expense_categories`, and `settings`
is:

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
├── main.dart                      — Supabase init, MaterialApp, exposes
│                                     the global `supabase` client
├── widgets/
│   └── app_drawer.dart            — side navigation Drawer, opened via
│                                     the dashboard's hamburger icon.
│                                     Always shows Transactions + Reports
│                                     + Log out (read-only, so viewers see
│                                     them too); shows a "MANAGE" section
│                                     (Expense categories, Staff,
│                                     Partners, Settings) for admins only.
├── screens/
│   ├── login_screen.dart          — username/password login (appends
│   │                                 @janatayn.local internally)
│   ├── dashboard_screen.dart      — main screen after login. Fetches
│   │                                 profile (name/role) + all
│   │                                 transactions, computes cash on hand,
│   │                                 outstanding loans/advances, and
│   │                                 this-month totals. FAB to add a
│   │                                 transaction (admin only); drawer for
│   │                                 navigation to everything else.
│   ├── add_transaction_screen.dart — type selector (expense/payroll/loan/
│   │                                 advance), partner/staff dropdown
│   │                                 when relevant, category dropdown
│   │                                 (expense only, sourced from
│   │                                 expense_categories), total amount,
│   │                                 "Multiple invoices" toggle with
│   │                                 per-invoice category dropdowns and
│   │                                 allocation validation, note field.
│   │                                 Loan type has a repayment toggle;
│   │                                 payroll type shows a base
│   │                                 salary/owed-advance breakdown with a
│   │                                 repay-amount field (see "Recording
│   │                                 payroll with an advance deduction"
│   │                                 above). Also used for editing
│   │                                 multi-invoice transactions
│   │                                 (pre-filled).
│   ├── expense_categories_screen.dart — list of expense categories with
│   │                                 an add-new form; reached via the
│   │                                 "Manage categories" link on the Add
│   │                                 Transaction screen or the drawer.
│   ├── staff_screen.dart          — list of staff (name + base salary)
│   │                                 with an add-new form. Reached from
│   │                                 the drawer.
│   ├── partners_screen.dart       — list of partners with an add-new
│   │                                 form. Reached from the drawer.
│   ├── settings_screen.dart       — edits the `settings` table's
│   │                                 `opening_balance` row. Reached from
│   │                                 the drawer.
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
│   └── report_screen.dart         — per-account reporting, reached from
│                                     the drawer. A "Payroll / Advances /
│                                     Loans / Expenses" chip selector
│                                     switches which transaction type(s)
│                                     are shown, with a contextual filter
│                                     (staff for Payroll/Advances, partner
│                                     for Loans, category for Expenses)
│                                     plus a shared date-range filter and
│                                     summary total cards. Payroll/
│                                     Advances/Loans show a filtered
│                                     transaction list; Expenses instead
│                                     shows two bar charts (spend by
│                                     category, capped to top 7 + "Other";
│                                     spend by month, last 6 months) built
│                                     with `fl_chart`, single-hue (the
│                                     app's expense red) since it's a
│                                     magnitude comparison, not identity -
│                                     see the dataviz skill's form-choice
│                                     guidance before changing this.
│                                     Read-only, so visible to viewers too.
```

Dashboard and transaction log both independently fetch and sum
transactions client-side — there's no shared state/provider layer yet. If
more screens need the same aggregated numbers, consider introducing a
shared data layer (e.g. Riverpod/Provider) rather than each screen
re-fetching and re-summing independently.

## Design language

- Background: `Color(0xFFF7F7F5)` (soft off-white), flat AppBars with
  `elevation: 0` matching that background.
- Currency: always formatted via `intl`'s `NumberFormat.currency(symbol:
  '\$', decimalDigits: 2)` — never manual string interpolation like
  `'\$${value.toStringAsFixed(2)}'`, to keep thousands separators
  consistent everywhere.
- Cards: white background, light grey 1px borders (`Colors.grey.shade200`
  or `.shade300`), 10–12px border radius, no shadows.
- Color coding by transaction type (used for icon circles and amount
  text): `expense` = red, `payroll` = orange, `loan` = blue, `advance` =
  purple, `loan_repayment`/cash-in = green, `advance_deduction`/neutral =
  grey (shown without a +/- sign since no cash moves).
- Type selector uses `ChoiceChip` pills, not dropdowns, for fast tapping.

## Conventions to preserve when adding features

1. Any new writable table needs the same RLS pattern: read = all
   authenticated users, write = admin role only.
2. New transaction-adjacent features should go through `transactions` +
   `transaction_items`, not new bespoke tables, unless the data genuinely
   isn't a cash event.
3. Don't reintroduce capital-injection tracking or per-partner financial
   profile fields — this was deliberately removed; partners are a simple
   name lookup only.
4. Keep the opening balance / calculated-balance approach — avoid adding
   stored running-balance columns that could drift out of sync with the
   transaction history.
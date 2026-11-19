# Architecture

## Stack

| Layer | Choice | Why |
|---|---|---|
| App | Flutter (Android, iOS, Web, one codebase) | One team, one UI, tablets and desktop browsers share the phone code |
| State | Riverpod (no code generation) | Simple providers, easy cache invalidation after a sale |
| Navigation | go_router | URL based on web, shell layout, permission redirects |
| Backend | Supabase: Postgres, Auth, Storage, Edge Functions | Row level security, SQL transactions, no server to run |
| Charts, PDF, scan | fl_chart, pdf + printing, mobile_scanner | Cross platform |

SEO is not a concern for a management dashboard, so the web build is a plain Flutter web app.

## Where the rules live

Everything that touches money or stock is a **Postgres function** that runs in one transaction:
`create_sale`, `void_sale`, `create_sales_return`, `record_customer_payment`, `create_purchase`,
`record_supplier_payment`, `adjust_stock`, `create_expense`, `void_expense`, `create_business`.

The app cannot write to financial tables directly (no insert/update/delete policies exist for them). Each function:

1. checks the caller's permission,
2. validates the input (stock, prices, discounts, payment totals),
3. writes the document, lines, ledger entries, account transactions and stock movements,
4. writes an audit entry,
5. is idempotent when a `client_ref` is supplied, so a retry after a network failure cannot double-post.

## Security model

- Every table has `business_id` and row level security scoped to the signed-in member's business.
- Reads of sensitive tables also require the matching permission (`sales.view`, `purchases.view`, ...).
- Permissions are stored per business and role (`role_permissions`); the owner always has all of them.
- Staff accounts are created by the `create-staff` edge function, which verifies the caller is the owner. The service role key never reaches the app.
- Records are voided, never deleted. Voids need a reason and are logged in `activity_log`.

## Ledgers

- `customer_ledger`: debit increases what the customer owes, credit decreases it. Balance = debit - credit. Negative means customer advance.
- `supplier_ledger`: credit increases what we owe, debit decreases it. Balance = credit - debit. Negative means advance paid.
- `account_transactions`: every money movement in or out of a payment account (cash, bKash, bank...). Account balance = opening balance + in - out. This is the base for cash register and day closing in Phase 2.
- `stock_movements`: append-only record of every stock change; `stock_levels` holds the current totals per branch.

## Multi-branch readiness

Every transaction and stock row carries `branch_id`. Phase 1 runs with one default branch; Phase 3 adds branch switching, transfers and branch reports without schema changes.

## Cart maths

The POS computes totals in integer paisa using the same formulas as `create_sale`, so the screen and the saved invoice always agree. The database remains the authority; the app shows the saved totals after checkout.

## Adding a feature

1. Add a table or function in a new migration file (never edit an applied migration).
2. Add a `*_data.dart` file next to the feature with models, a repository and providers.
3. Add pages, then register routes in `lib/core/router/app_router.dart`.
4. If the change affects money, stock or balances, call `refreshAfterTransaction(ref)` after it succeeds.

# EZ POS - Progress

Last updated: 22 Nov 2026. Stack: Flutter (Android, iOS, Web) and Supabase (Postgres, Auth, Storage).

## How to read this file

| Mark | Meaning |
|------|---------|
| DONE | Built and checked as described in "Verification" |
| UI WRITTEN | Screen is written but has not been compiled or run (see "Verification") |
| TODO | Not started |

## Verification (be aware of this)

- Database: all migrations (0001 to 0014) apply on a clean PostgreSQL 16. Three scenario suites pass with no failures:
  `supabase/tests/scenario_phase1.py` (41 checks), `scenario_phase2.py` (145 checks) and
  `scenario_phase2_finish.py` (80 checks, added in this step). They cover permissions, tenant isolation, accounting
  and stock effects. The password check runs against a stand-in for `crypt()` because the scratch database has no
  pgcrypto; the real bcrypt comparison only runs on Supabase.
- Flutter: this build environment has no Flutter SDK, so the app was **not compiled and not run**. All 107 Dart files in
  `lib` and the 3 files in `test` parse without syntax errors. Expect a few analyzer fixes on the first
  `flutter analyze`. Run: `flutter pub get`, `flutter analyze`, `flutter test`, then try each Phase 2 screen on a device.
- Direct thermal printing, file upload to Supabase Storage and the camera or file pickers were **never run on a real
  device or printer**. Treat them as the first things to test (see "Test on a device first" below).

## Phase 1 - Core POS: DONE
Login and setup, roles, dashboard, products, customers, suppliers, POS, split and due sales, purchases, ledgers,
returns, expenses, reports, invoices and PDF. See docs/ROADMAP.md.

## Phase 2 - Installments and advanced inventory: COMPLETE (code written, waiting for the first compile and device test)

### Installments
| Feature | Database | Screen |
|---------|----------|--------|
| Sell on installment from POS (down payment, count, weekly / 2-weekly / monthly) | DONE | UI WRITTEN |
| Custom schedule (own dates and amounts, must add up to the total) | DONE | UI WRITTEN |
| Service charge (fixed or percent), minimum down payment rule | DONE | UI WRITTEN |
| Guarantor, reference and emergency contact per plan | DONE | UI WRITTEN |
| Collect: partial, several at once, pay ahead, advance when overpaid | DONE | UI WRITTEN |
| Receipt per payment (PDF) and agreement and schedule (PDF) | n/a | UI WRITTEN |
| Change a due date (reason required, old date kept) | DONE | UI WRITTEN |
| Due lists: today, 7, 15, 30 days, overdue, all plans | DONE | UI WRITTEN |
| Reminder rules, templates, no repeat to the same customer, send log | DONE | UI WRITTEN |
| Send reminder through WhatsApp, SMS or call (opens the app with the text filled) | n/a | UI WRITTEN |
| Follow-up tasks | DONE | UI WRITTEN |
| Installment report (sales, collections, performance, by customer, by product) | DONE | UI WRITTEN |
| Dashboard cards and quick actions | DONE | UI WRITTEN |
| Installment settings (defaults, reminder schedule, templates, agreement terms) | DONE | UI WRITTEN |
| Void an installment sale (only while nothing is collected) | DONE | existing screen |
| Automatic SMS or WhatsApp sending through a provider | TODO (Phase 3) | TODO |
| Automatic late fee charging (policy text only; needs the owner's rate, grace days and cap, see "Decisions for you") | NOT BUILT | n/a |
| Return on an installment sale (unpaid schedule shrinks from the last installment, excess refunded or kept as credit) | DONE | UI WRITTEN |
| Exchange on an installment sale | DONE | UI WRITTEN |
| Customer profile: installment plans tab and plan cards | n/a | UI WRITTEN |
| Signed agreement and guarantor NID copies on the plan page | DONE | UI WRITTEN |

### Serial, IMEI, batch and expiry
| Feature | Database | Screen |
|---------|----------|--------|
| Tracking type on product (IMEI, serial, batch, expiry) | DONE | UI WRITTEN |
| Capture numbers or batches at purchase | DONE | UI WRITTEN |
| IMEI check (15 digits, check digit), duplicate protection | DONE | UI WRITTEN |
| Choose units at POS, one number per unit sold, warranty date stored | DONE | UI WRITTEN |
| Earliest-expiry-first selling, restore on void and return | DONE | n/a |
| Adjust stock with numbers or batch (damage, loss, expired) | DONE | UI WRITTEN |
| Serial and IMEI lookup with full history | DONE | UI WRITTEN |
| Expiry alerts | DONE | UI WRITTEN |
| Warranty claims and service tickets | TODO (Phase 4) | TODO |

### Stock movement
| Feature | Database | Screen |
|---------|----------|--------|
| Branches and warehouses (basic add and edit) | DONE | UI WRITTEN |
| Transfer: request, send, partial receive, close short, cancel (units and batches follow) | DONE | UI WRITTEN |
| Transfer note (PDF) | n/a | UI WRITTEN |
| Physical stock count (draft, finish, one adjustment per difference) | DONE | UI WRITTEN |
| Purchase return (credit or cash refund, units and batches) | DONE | UI WRITTEN |
| Sales return with chosen serial numbers | DONE | UI WRITTEN |
| Exchange (returned value becomes credit, pay or refund the difference) | DONE | UI WRITTEN |
| Return policy time limit (setting, manager override permission, logged) | DONE | UI WRITTEN |
| Refund and return receipt print (after saving a return, and again from the invoice) | n/a | UI WRITTEN |

### Cash and accounts
| Feature | Database | Screen |
|---------|----------|--------|
| Counters, open and close cashier shift, expected vs counted cash | DONE | UI WRITTEN |
| Cash in and cash out | DONE | UI WRITTEN |
| Deposit, withdrawal, transfer between cash, bank and mobile banking | DONE | UI WRITTEN |
| Account statement with running balance (PDF) | DONE | UI WRITTEN |
| Day closing (blocked while a shift is open), difference posted, report (PDF) | DONE | UI WRITTEN |
| Reopen a closed day (owner permission, reason, history kept) | DONE | UI WRITTEN |

### Finished in this step (were open in Phase 2)
| Item | Database | Screen |
|------|----------|--------|
| Customer form: workplace, emergency contact, reminders on or off (the profile view was missing these columns, fixed in 0014) | DONE | UI WRITTEN |
| Upload and view NID copies and agreements (private bucket, signed links that expire in 2 minutes, 10 MB limit) | DONE | UI WRITTEN |
| Attachments on purchases, suppliers and expenses (same reusable section) | DONE | UI WRITTEN |
| Direct thermal printing over Bluetooth, USB and network, per device, with test print, cut and cash drawer | n/a | UI WRITTEN |
| Keyboard shortcuts on the POS screen (F1, F2, F4, F6, F7, F9, Ctrl+K, Ctrl+Enter, Esc) | n/a | UI WRITTEN |
| Password confirmation before sensitive actions (setting on by default) | DONE | UI WRITTEN |
| SKU and barcode numbering rules (prefix, digits, start number, barcode prefix) | DONE | UI WRITTEN |

### Not part of Phase 2
| Item | Where it goes |
|------|---------------|
| Payment correction with approval | Phase 3 approval workflow |
| Automatic SMS or WhatsApp sending through a provider | Phase 3 |
| Warranty claims and service tickets | Phase 4 |

### Test on a device first
1. Printer: Settings > Printer on this device. Try your real printer, press Print test receipt. Bluetooth needs the
   printer paired in the phone settings first. Web cannot print directly (it uses the browser dialog).
2. Upload: open a customer > Details > Documents > Add. Check the file opens, and that a user without document
   access cannot see it.
3. Installment return: sell on installment, collect one installment, return part of it, read the plan.
4. Password confirmation: void a sale. Turn it off in Settings > Sales and stock rules > Security to compare.

### Decisions for you
- Late fee on overdue installments: say the rate (flat or percent), grace days and an upper limit, and it can be
  automated. Until then it stays a written policy in the agreement.
- Return after the return period: now needs a user with "Approve returns after the return period". Managers have it by
  default; cashiers do not.

## Phase 3 - Intelligence and multi-branch: TODO
Per-branch POS, price and user limits, advanced profit and loss, ageing, analytics, employee activity log, approval
workflow, advanced notifications, bulk import and export, custom reports and widgets, Excel and CSV export.

## Phase 4 - Advanced retail: TODO
Loyalty, membership, gift cards, coupons, combo products, wholesale price lists, purchase orders, warranty and service,
CRM.

## Database migrations added in Phase 2
| File | Content |
|------|---------|
| 0006_phase2_schema.sql | New permissions, tables, views, row level security |
| 0007_phase2_helpers.sql | Serial, IMEI and batch helpers |
| 0008_phase2_core.sql | Phase 1 functions extended (sale, void, return, purchase, adjust, reports) |
| 0009_installments.sql | Installment sale, collection, reschedule, reminders, reports |
| 0010_stock_returns.sql | Branches, transfers, purchase return, exchange, stock count, lookups, documents |
| 0011_cash.sql | Registers, shifts, entries, statements, day closing |
| 0012_phase2_grants.sql | Function privileges |
| 0013_documents_storage.sql | Private documents bucket (Supabase only) |
| 0014_phase2_finish.sql | Customer and plan views rebuilt, installment returns, return period, SKU rules, password check |

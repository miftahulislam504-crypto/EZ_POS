# EZ POS

Retail management software for shops: POS billing, customers and dues, suppliers and purchases, inventory, expenses and reports.
One Flutter codebase for Android, iOS and Web, backed by Supabase (Postgres, Auth, Storage, Edge Functions).

**Current release: Phase 1 - Core POS.** See `docs/ROADMAP.md` for every feature in the plan and the phase it ships in.

## What is in Phase 1

- Sign up, shop setup, sign in, team accounts, roles and editable permissions
- Dashboard: today's sales, profit, collections, dues, stock value, trend chart, top products and categories, alerts
- POS: search, camera or keyboard barcode scanning, categories, quantity and decimal units, line and invoice discounts, VAT, hold and resume carts, split payments (cash, bKash, Nagad, Rocket, bank, card, custom), partial payment, sale on credit, change calculation
- Invoices: unique numbers, 58 mm / 80 mm / A4 PDF, print, share, reprint, QR with the invoice number
- Customers: profiles, ledger with running balance, aging, receive payment (oldest first or chosen invoices), advance, receipts
- Suppliers: profiles, ledger, payables, payments with allocation, vouchers
- Products: images, SKU, barcode (scan or generate), categories, brands, units, three price levels, VAT, warranty, low stock alerts, barcode label printing
- Inventory: stock overview, valuation, movements, adjustments with reasons, damaged stock
- Purchases: items, discounts, VAT and other charges spread into landed cost, partial payment, bills
- Sales returns with item condition, refund or credit; void sale with reason
- Expenses with categories and recurring flag
- Reports: daily sales and profit, stock valuation
- Light and dark theme

## Project layout

```
lib/
  core/        theme, widgets, formatting, providers, router, PDF builder
  features/    auth, shell, dashboard, pos, sales, customers, suppliers, products,
               inventory, purchases, transactions, expenses, reports, settings
supabase/
  migrations/  0001 core, 0002 tables and security, 0003 functions, 0004 reports, 0005 storage
  functions/   create-staff (edge function)
  tests/       SQL scenario tests (Python)
docs/          ARCHITECTURE.md, ACCOUNTING_RULES.md, ROADMAP.md
tool/          bootstrap.sh
```

## Setup

### 1. Supabase

1. Create a project at supabase.com.
2. Run the migrations in order, either with the Supabase CLI (`supabase db push`) or by pasting each file from `supabase/migrations/` into the SQL editor: `0001` to `0005`.
3. Authentication, Providers, Email: for the easiest start turn **off** "Confirm email". If you keep it on, new owners must click the confirmation link before signing in.
4. Deploy the edge function that lets owners create staff accounts:
   ```
   supabase functions deploy create-staff
   ```
   It uses `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`, which Supabase provides to functions automatically.
5. Storage buckets `product-images` and `business-assets` are created by `0005_storage.sql`.

### 2. Flutter

Requires Flutter 3.29 or newer (Dart 3.7+).

```
bash tool/bootstrap.sh                      # creates android/ios/web folders, adds camera and internet permissions, sets iOS 15.5, runs pub get
cp dart_defines.example.json dart_defines.json   # then put your project URL and anon key in it
flutter run --dart-define-from-file=dart_defines.json
```

Web: `flutter run -d chrome --dart-define-from-file=dart_defines.json`
Release web build: `flutter build web --release --dart-define-from-file=dart_defines.json`
Android: `flutter build apk --release --dart-define-from-file=dart_defines.json`

Use the **anon** key only. The service role key must never be placed in the app.

### 3. First run

1. Create an account, then complete "Set up your shop".
2. Add products (Inventory, Add product). Use "Opening stock" for what you already have.
3. Open POS and make a sale. Print or share the invoice from the confirmation.
4. Add team members in Settings, Team members. Adjust what each role can do in Roles and permissions.

## Printing

Invoices are produced as PDF and sent to the system print dialog, so any printer your device can print to works, including 58 mm and 80 mm thermal printers installed on the device. Direct Bluetooth, USB and network ESC/POS printing is planned for Phase 2.
Barcode scanners that type into the keyboard (most USB and Bluetooth scanners) work on the POS search box: scan, and the product is added.

## Tests

- Dart: `flutter test` (cart maths must match the database to the paisa).
- SQL: `supabase/tests/scenario_phase1.py` applies the migrations to a scratch Postgres and runs purchases, sales, returns, payments, voids, permissions and row-level-security checks (`pip install pgserver psycopg2-binary`, then run `apply_migrations.py` followed by `scenario_phase1.py`).

## Notes and known limits of this release

- The SQL layer was executed and tested end to end. The Flutter code was written without access to a Flutter SDK, so run `flutter analyze` once after `pub get`; any package-version or API drift will show up there and is quick to fix.
- Lists load up to a page of rows with a "Load more" button. Very large catalogs will get server-side paging in Phase 3.
- Offline mode and sync queue, installments, serial/IMEI tracking, stock transfer, cash register and day closing are in later phases (see `docs/ROADMAP.md`).
- Backups: enable Point in Time Recovery in your Supabase project settings for production use.


## Phase 2 setup notes
- Run the new migrations `0006` to `0014` in order after the Phase 1 ones (`supabase db push`).
- `0013_documents_storage.sql` creates the private `documents` bucket and needs Supabase Storage.
- Reminders open WhatsApp, SMS or the phone dialer with `url_launcher`. On Android add `<queries>` entries for the
  `https`, `sms` and `tel` schemes in `AndroidManifest.xml`; on iOS add `whatsapp`, `sms` and `tel` to
  `LSApplicationQueriesSchemes` in `Info.plist`.
- `bash tool/bootstrap.sh` also adds the Bluetooth and USB permissions that receipt printers need. Run it once after
  `flutter create`, and again if you recreate the platform folders.
- Receipt printer: Settings > Printer on this device. Network printers use port 9100. Bluetooth printers must be paired
  in the phone settings first. USB printing is Android only; iOS supports Bluetooth Low Energy printers. The web app
  uses the browser print dialog.
- Password confirmation uses the database function `verify_password`, which reads Supabase Auth's stored hash. It needs
  the `pgcrypto` extension (installed by default on Supabase).
- Tests: `python supabase/tests/apply_migrations.py && python supabase/tests/scenario_phase1.py && python supabase/tests/scenario_phase2.py && python supabase/tests/scenario_phase2_finish.py`
  (needs `pip install pgserver psycopg2-binary`), and `flutter test`.
- See `Progress.md` for what is done and what remains.

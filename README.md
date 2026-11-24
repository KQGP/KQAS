# KQAS — Inventory & Warehouse Management System

Offline-first Flutter app for tracking products, stock, warehouses, invoices, and stock movements on Android.

> **Status:** work in progress. Core inventory, scanning, invoices, stocktaking, transfers, and ledger logic are implemented; several UI screens (notifications, stocktaking, transfers, users, settings, backup) are still being wired up.

## Features

- **Products & inventory** — create/edit/archive products, SKUs, barcodes, categories, suppliers, images, weight; list/grid views, search, filters, sorting, bulk actions.
- **Stock tracking** — per-warehouse physical & reserved quantities, available stock, low/out-of-stock filters, negative-stock override with permission.
- **Append-only stock ledger** — every balance change is recorded in `stock_movements`; the table is guarded by SQLite triggers (no UPDATE/DELETE) and supports idempotent posting.
- **Invoices** — incoming/outgoing invoices with receive/dispatch flows; PDF import that matches products by name/SKU/barcode.
- **Scanning** — barcode scan sessions for loading/unloading stock against invoices.
- **Stocktaking** — cycle counts with system vs. counted quantities and automatic adjustments.
- **Transfers** — move stock between warehouses.
- **Reservations** — reserve/release stock for sessions.
- **Bus / Van** — view dispatched invoices and open customer delivery locations in Maps.
- **Dashboard** — totals, inventory value, weight, stock status counts, recent movements/additions.
- **Backup** — copy the SQLite database to a timestamped backup file.
- **Settings & users** — roles (admin/operator), active state, theme mode.

## Tech stack

- Flutter (Dart `>=3.4.0`), Material Design
- State management: `flutter_riverpod`
- Routing: `go_router`
- Database: `drift` (SQLite) with `drift_flutter`, WAL mode, foreign keys
- Barcode scanning: `mobile_scanner`
- PDF text extraction: `pdf_text_extractor` (via `file_picker`)
- Other: `intl`, `uuid`, `path_provider`, `image_picker`, `url_launcher`

## Project structure

```
lib/
  app.dart                  # MaterialApp.router entry widget
  main.dart                # bootstrap
  core/                    # theme, routing, widgets, utilities, errors
  database/                # Drift database, tables, migrations, seeds
  features/                 # feature modules (data/domain/presentation)
  shared/                  # providers, settings
test/                      # unit/widget tests
android/                   # Android platform
```

## Getting started

Prerequisites: Flutter SDK `>=3.22.0`, Dart `>=3.4.0`.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # regenerate Drift code
flutter run
```

## Testing

```bash
flutter test
```

Tests cover the database schema/guards, product repository, quantity/money helpers, stock engine, and end-to-end flows (invoice receive, scan sessions, reservations, stocktaking, transfers, notifications, users).

## Database notes

- Schema version `2` (see `AppDatabase.currentSchemaVersion`).
- On first run the DB is seeded with default units, a "Main Warehouse", and an admin user.
- `stock_movements` is append-only; UPDATE/DELETE are rejected by triggers.
- Quantities are stored as scaled integers (see `kQtyScale` / `Qty`).
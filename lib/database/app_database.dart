import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import 'tables/core_tables.dart';
import 'tables/invoice_tables.dart';
import 'tables/stock_tables.dart';
import 'tables/system_tables.dart';

part 'app_database.g.dart';

const _uuid = Uuid();

@DriftDatabase(tables: [
  Units,
  Categories,
  Suppliers,
  Customers,
  Warehouses,
  StorageLocations,
  Products,
  ProductBarcodes,
  InventoryBalances,
  Invoices,
  InvoiceItems,
  Users,
  StockMovements,
  ScanSessions,
  ScanSessionItems,
  ScanLogs,
  StockReservations,
  StocktakingSessions,
  StocktakingItems,
  Notifications,
  AlertStates,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'kqas'));

  /// Used by tests (e.g. `NativeDatabase.memory()`).
  AppDatabase.forTesting(super.executor);

  static const int currentSchemaVersion = 2;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
          await _createLedgerGuards();
          await _seed();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(products, products.weightGrams);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  Future<void> _createIndexes() async {
    const stmts = [
      'CREATE INDEX idx_products_name ON products(name)',
      'CREATE INDEX idx_products_category ON products(category_id)',
      'CREATE INDEX idx_products_supplier ON products(supplier_id)',
      'CREATE INDEX idx_barcodes_product ON product_barcodes(product_id)',
      'CREATE UNIQUE INDEX idx_balance_key ON inventory_balances('
          'product_id, warehouse_id, IFNULL(location_id, \'\'))',
      'CREATE INDEX idx_invoices_status ON invoices(invoice_type, status)',
      'CREATE INDEX idx_items_invoice ON invoice_items(invoice_id)',
      'CREATE INDEX idx_moves_product_time ON stock_movements(product_id, created_at)',
      'CREATE INDEX idx_moves_warehouse ON stock_movements(warehouse_id)',
      'CREATE INDEX idx_moves_invoice ON stock_movements(invoice_id)',
      'CREATE INDEX idx_scanlogs_session ON scan_logs(session_id, scanned_at)',
      'CREATE INDEX idx_reservations_session ON stock_reservations(session_id, status)',
      'CREATE INDEX idx_notifications_read ON notifications(is_read, created_at)',
    ];
    for (final s in stmts) {
      await customStatement(s);
    }
  }

  /// The ledger is permanent: block UPDATE and DELETE at the SQLite level so
  /// no code path (or future bug) can silently rewrite history.
  Future<void> _createLedgerGuards() async {
    await customStatement('''
      CREATE TRIGGER stock_movements_no_update
      BEFORE UPDATE ON stock_movements
      BEGIN SELECT RAISE(ABORT, 'stock_movements is append-only'); END''');
    await customStatement('''
      CREATE TRIGGER stock_movements_no_delete
      BEFORE DELETE ON stock_movements
      BEGIN SELECT RAISE(ABORT, 'stock_movements is append-only'); END''');
  }

  Future<void> _seed() async {
    const uuid = Uuid();
    final defaults = <(String, String, int)>[
      ('Piece', 'pcs', 0),
      ('Carton', 'ctn', 0),
      ('Box', 'box', 0),
      ('Kilogram', 'kg', 3),
      ('Litre', 'L', 3),
      ('Metre', 'm', 2),
    ];
    for (final u in defaults) {
      await into(units).insert(UnitsCompanion.insert(
          name: u.$1, symbol: u.$2, decimals: Value(u.$3)));
    }
    await into(warehouses).insert(WarehousesCompanion.insert(name: 'Main Warehouse'));
    await into(users).insert(UsersCompanion.insert(
        name: 'Administrator',
        role: const Value('admin'),
        canOverrideNegativeStock: const Value(true)));
    await into(appSettings).insert(AppSettingsCompanion.insert(
        settingKey: 'schema_installation_id', settingValue: uuid.v4()));
  }
}

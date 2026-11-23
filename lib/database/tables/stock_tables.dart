import 'package:drift/drift.dart';
import 'common.dart';
import 'core_tables.dart';
import 'invoice_tables.dart';

class Users extends Table with UuidPk {
  TextColumn get name => text()();
  TextColumn get role => text().withDefault(const Constant('operator'))();
  BoolColumn get canOverrideNegativeStock =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Append-only ledger. UPDATE and DELETE are blocked by SQLite triggers
/// (see AppDatabase._createLedgerGuards). Corrections are new rows.
class StockMovements extends Table with UuidPk {
  /// Idempotency key: the same logical operation can never post twice.
  TextColumn get operationId => text().unique()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get locationId =>
      text().nullable().references(StorageLocations, #id)();
  TextColumn get movementType => text()();
  IntColumn get quantityIn => integer().withDefault(const Constant(0))();
  IntColumn get quantityOut => integer().withDefault(const Constant(0))();
  IntColumn get previousQuantity => integer()();
  IntColumn get newQuantity => integer()();
  TextColumn get invoiceId => text().nullable().references(Invoices, #id)();
  TextColumn get sessionId => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get userId => text().nullable().references(Users, #id)();
  TextColumn get reason => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
        'CHECK (quantity_in >= 0 AND quantity_out >= 0)',
        'FOREIGN KEY (product_id) REFERENCES products(id)',
        'FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)',
        'FOREIGN KEY (location_id) REFERENCES storage_locations(id)',
        'FOREIGN KEY (invoice_id) REFERENCES invoices(id)',
        'FOREIGN KEY (user_id) REFERENCES users(id)',
      ];
}

/// session_type: loading | unloading ; status: active | paused | completed | cancelled
class ScanSessions extends Table with UuidPk {
  TextColumn get invoiceId => text().nullable().references(Invoices, #id)();
  TextColumn get sessionType => text()();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (invoice_id) REFERENCES invoices(id)',
        'FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)',
      ];
}

class ScanSessionItems extends Table with UuidPk {
  TextColumn get sessionId =>
      text().references(ScanSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get expectedQuantity => integer()();
  IntColumn get scannedQuantity => integer().withDefault(const Constant(0))();
  IntColumn get discrepancyQuantity =>
      integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {sessionId, productId}
      ];

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (session_id) REFERENCES scan_sessions(id) ON DELETE CASCADE',
        'FOREIGN KEY (product_id) REFERENCES products(id)',
      ];
}

class ScanLogs extends Table with UuidPk {
  TextColumn get sessionId =>
      text().nullable().references(ScanSessions, #id)();
  TextColumn get productId => text().nullable().references(Products, #id)();
  TextColumn get barcode => text()();
  /// valid | overscan | unknown | duplicate
  TextColumn get scanResult => text()();
  DateTimeColumn get scannedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (session_id) REFERENCES scan_sessions(id)',
        'FOREIGN KEY (product_id) REFERENCES products(id)',
      ];
}

/// status: active | converted | released
class StockReservations extends Table with UuidPk {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get sessionId => text().references(ScanSessions, #id)();
  IntColumn get quantity => integer()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
        'CHECK (quantity > 0)',
        'FOREIGN KEY (product_id) REFERENCES products(id)',
        'FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)',
        'FOREIGN KEY (session_id) REFERENCES scan_sessions(id)',
      ];
}

class StocktakingSessions extends Table with UuidPk {
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get status => text().withDefault(const Constant('counting'))();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)',
      ];
}

class StocktakingItems extends Table with UuidPk {
  TextColumn get sessionId => text()
      .references(StocktakingSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get systemQuantity => integer()();
  IntColumn get countedQuantity => integer().nullable()();
  IntColumn get difference => integer().nullable()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (session_id) REFERENCES stocktaking_sessions(id) ON DELETE CASCADE',
        'FOREIGN KEY (product_id) REFERENCES products(id)',
      ];
}

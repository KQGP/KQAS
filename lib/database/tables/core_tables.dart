import 'package:drift/drift.dart';
import 'common.dart';

class Units extends Table with UuidPk {
  TextColumn get name => text().unique()();
  TextColumn get symbol => text()();
  IntColumn get decimals => integer().withDefault(const Constant(0))();
}

class Categories extends Table with UuidPk {
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable().references(Categories, #id)();
  IntColumn get color => integer().nullable()();
  TextColumn get icon => text().nullable()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (parent_id) REFERENCES categories(id)',
      ];
}

class Suppliers extends Table with UuidPk {
  TextColumn get name => text()();
  TextColumn get contactPerson => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get taxNumber => text().nullable()();
  TextColumn get notes => text().nullable()();
}

class Customers extends Table with UuidPk {
  TextColumn get name => text()();
  TextColumn get contactPerson => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
}

class Warehouses extends Table with UuidPk {
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

class StorageLocations extends Table with UuidPk {
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get parentLocationId =>
      text().nullable().references(StorageLocations, #id)();
  TextColumn get code => text()();
  TextColumn get name => text().nullable()();
  TextColumn get barcode => text().nullable().unique()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {warehouseId, code}
      ];

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)',
        'FOREIGN KEY (parent_location_id) REFERENCES storage_locations(id)',
      ];
}

class Products extends Table with UuidPk {
  TextColumn get sku => text().nullable().unique()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get unitId => text().references(Units, #id)();
  IntColumn get minStock => integer().withDefault(const Constant(0))();
  IntColumn get maxStock => integer().nullable()();
  IntColumn get reorderQuantity => integer().withDefault(const Constant(0))();
  IntColumn get purchasePriceMinor => integer().nullable()();
  IntColumn get sellingPriceMinor => integer().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  TextColumn get notes => text().nullable()();
  IntColumn get weightGrams => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (category_id) REFERENCES categories(id)',
        'FOREIGN KEY (unit_id) REFERENCES units(id)',
        'FOREIGN KEY (supplier_id) REFERENCES suppliers(id)',
      ];
}

class ProductBarcodes extends Table with UuidPk {
  TextColumn get productId => text().references(Products, #id)();
  // Globally unique: one barcode can identify only one product.
  TextColumn get barcode => text().unique()();
  TextColumn get barcodeType => text().nullable()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (product_id) REFERENCES products(id)',
      ];
}

class InventoryBalances extends Table with UuidPk {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get locationId =>
      text().nullable().references(StorageLocations, #id)();
  IntColumn get physicalQuantity => integer().withDefault(const Constant(0))();
  IntColumn get reservedQuantity => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  // Physical may go negative only via an explicit authorised override in the
  // stock engine (Phase 2), so only reserved is constrained here.
  @override
  List<String> get customConstraints => [
        'CHECK (reserved_quantity >= 0)',
        'FOREIGN KEY (product_id) REFERENCES products(id)',
        'FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)',
        'FOREIGN KEY (location_id) REFERENCES storage_locations(id)',
      ];
}

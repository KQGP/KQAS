import 'package:drift/drift.dart';
import 'common.dart';
import 'core_tables.dart';
import 'invoice_tables.dart';

class Notifications extends Table with UuidPk {
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get message => text()();
  TextColumn get relatedProductId =>
      text().nullable().references(Products, #id)();
  TextColumn get relatedInvoiceId =>
      text().nullable().references(Invoices, #id)();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (related_product_id) REFERENCES products(id)',
        'FOREIGN KEY (related_invoice_id) REFERENCES invoices(id)',
      ];
}

/// Per product+warehouse alert state so notifications fire only on threshold
/// CROSSINGS (healthy -> low -> out), not on every refresh. state: healthy|low|out
class AlertStates extends Table {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get warehouseId => text().references(Warehouses, #id)();
  TextColumn get state => text().withDefault(const Constant('healthy'))();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {productId, warehouseId};

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (product_id) REFERENCES products(id)',
        'FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)',
      ];
}

class AppSettings extends Table {
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();

  @override
  Set<Column> get primaryKey => {settingKey};
}

import 'package:drift/drift.dart';
import 'common.dart';
import 'core_tables.dart';

/// invoice_type: incoming | outgoing
/// status: draft | pending | partiallyReceived | received |
///         partiallyDispatched | dispatched | cancelled | reversed
class Invoices extends Table with UuidPk {
  TextColumn get invoiceNumber => text()();
  TextColumn get invoiceType => text()();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  DateTimeColumn get invoiceDate => dateTime()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get subtotalMinor => integer().withDefault(const Constant(0))();
  IntColumn get taxMinor => integer().withDefault(const Constant(0))();
  IntColumn get discountMinor => integer().withDefault(const Constant(0))();
  IntColumn get totalMinor => integer().withDefault(const Constant(0))();
  TextColumn get sourcePdfPath => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get approvedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (supplier_id) REFERENCES suppliers(id)',
        'FOREIGN KEY (customer_id) REFERENCES customers(id)',
      ];
}

class InvoiceItems extends Table with UuidPk {
  TextColumn get invoiceId =>
      text().references(Invoices, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text().nullable().references(Products, #id)();
  TextColumn get description => text().nullable()();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  IntColumn get expectedQuantity => integer()();
  IntColumn get receivedQuantity => integer().withDefault(const Constant(0))();
  IntColumn get dispatchedQuantity =>
      integer().withDefault(const Constant(0))();
  IntColumn get unitPriceMinor => integer().nullable()();
  IntColumn get lineTotalMinor => integer().nullable()();
  RealColumn get matchConfidence => real().nullable()();
  TextColumn get matchStatus => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (expected_quantity >= 0)',
        'CHECK (received_quantity >= 0)',
        'CHECK (dispatched_quantity >= 0)',
        'FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE',
        'FOREIGN KEY (product_id) REFERENCES products(id)',
      ];
}

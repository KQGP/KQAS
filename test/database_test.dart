import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kqas/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<(String, String, String)> seedIds() async {
    final unit = (await db.select(db.units).get()).first;
    final wh = (await db.select(db.warehouses).get()).first;
    final pid = 'p1';
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value('p1'), name: 'Carton A', unitId: unit.id));
    return (pid, wh.id, unit.id);
  }

  Future<void> insertMove(String pid, String wid, String op) =>
      db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
          operationId: op,
          productId: pid,
          warehouseId: wid,
          movementType: 'openingBalance',
          quantityIn: const Value(5),
          previousQuantity: 0,
          newQuantity: 5));

  test('seed creates default warehouse, units and admin', () async {
    expect((await db.select(db.warehouses).get()).length, 1);
    expect((await db.select(db.units).get()).isNotEmpty, true);
    expect((await db.select(db.users).get()).length, 1);
  });

  test('ledger is append-only (UPDATE and DELETE are rejected)', () async {
    final (pid, wid, _) = await seedIds();
    await insertMove(pid, wid, 'op-1');
    expect(
        () => db.customStatement('UPDATE stock_movements SET quantity_in = 99'),
        throwsA(anything));
    expect(() => db.customStatement('DELETE FROM stock_movements'),
        throwsA(anything));
  });

  test('duplicate operationId is rejected (idempotency)', () async {
    final (pid, wid, _) = await seedIds();
    await insertMove(pid, wid, 'op-dup');
    expect(() => insertMove(pid, wid, 'op-dup'), throwsA(anything));
  });

  test('a barcode can belong to only one product', () async {
    final (pid, _, unitId) = await seedIds();
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value('p2'), name: 'Other', unitId: unitId));
    await db.into(db.productBarcodes).insert(
        ProductBarcodesCompanion.insert(productId: pid, barcode: '123'));
    expect(
        () => db.into(db.productBarcodes).insert(
            ProductBarcodesCompanion.insert(productId: 'p2', barcode: '123')),
        throwsA(anything));
  });

  test('foreign keys are enforced', () async {
    expect(
        () => db.into(db.productBarcodes).insert(
            ProductBarcodesCompanion.insert(productId: 'missing', barcode: '9')),
        throwsA(anything));
  });

  test('reserved quantity cannot be negative', () async {
    final (pid, wid, _) = await seedIds();
    expect(
        () => db.into(db.inventoryBalances).insert(
            InventoryBalancesCompanion.insert(
                productId: pid,
                warehouseId: wid,
                reservedQuantity: const Value(-1))),
        throwsA(anything));
  });
}

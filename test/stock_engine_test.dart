import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kqas/core/errors/app_exceptions.dart';
import 'package:kqas/database/app_database.dart';
import 'package:kqas/database/tables/common.dart';
import 'package:kqas/features/stock_movements/data/stock_engine.dart';
import 'package:kqas/features/stock_movements/domain/movement_type.dart';

const k = kQtyScale;

void main() {
  late AppDatabase db;
  late StockEngine engine;
  late String warehouseId, adminId;
  var n = 0;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    engine = StockEngine(db);
    final unit = (await db.select(db.units).get()).firstWhere((u) => u.symbol == 'pcs');
    warehouseId = (await db.select(db.warehouses).get()).first.id;
    adminId = (await db.select(db.users).get()).first.id;
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: const Value('p1'), name: 'Carton A', unitId: unit.id));
  });
  tearDown(() => db.close());

  Future<StockPosting> post(MovementType t, int qty,
          {StockDirection? dir, String? reason, String? op, bool override = false, String? user}) =>
      engine.post(
        operationId: op ?? 'op-${n++}',
        productId: 'p1',
        warehouseId: warehouseId,
        type: t,
        direction: dir,
        quantity: qty * k,
        reason: reason,
        allowNegativeOverride: override,
        userId: user,
      );

  Future<InventoryBalance> balance() async =>
      (db.select(db.inventoryBalances)..where((b) => b.productId.equals('p1'))).getSingle();

  Future<void> reserve(int qty) =>
      (db.update(db.inventoryBalances)..where((b) => b.productId.equals('p1')))
          .write(InventoryBalancesCompanion(reservedQuantity: Value(qty * k)));

  test('inbound posting updates balance and writes a ledger row', () async {
    final r = await post(MovementType.purchase, 50);
    expect(r.movement.previousQuantity, 0);
    expect(r.movement.newQuantity, 50 * k);
    expect(r.movement.quantityIn, 50 * k);
    expect((await balance()).physicalQuantity, 50 * k);
  });

  test('outbound beyond AVAILABLE (physical - reserved) is rejected', () async {
    await post(MovementType.purchase, 50);
    await reserve(10);
    expect(
      () => post(MovementType.sale, 45),
      throwsA(isA<InsufficientStockException>()
          .having((e) => e.message, 'message',
              'Insufficient stock. You need 45 units, but only 40 are available. Shortage: 5 units.')
          .having((e) => e.shortage, 'shortage', 5 * k)),
    );
    expect((await balance()).physicalQuantity, 50 * k); // untouched
    final ledger = await db.select(db.stockMovements).get();
    expect(ledger.length, 1); // only the purchase
  });

  test('outbound within available succeeds', () async {
    await post(MovementType.purchase, 50);
    await reserve(10);
    final r = await post(MovementType.sale, 40);
    expect(r.movement.newQuantity, 10 * k);
  });

  test('same operationId is idempotent', () async {
    final a = await post(MovementType.purchase, 10, op: 'same');
    final b = await post(MovementType.purchase, 10, op: 'same');
    expect(b.alreadyPosted, true);
    expect(b.movement.id, a.movement.id);
    expect((await balance()).physicalQuantity, 10 * k);
    expect((await db.select(db.stockMovements).get()).length, 1);
  });

  test('adjustments need a reason; zero quantity is invalid', () async {
    await post(MovementType.purchase, 10);
    expect(() => post(MovementType.damaged, 1), throwsA(isA<ReasonRequiredException>()));
    expect(() => post(MovementType.damaged, 1, reason: '  '), throwsA(isA<ReasonRequiredException>()));
    expect(() => post(MovementType.purchase, 0), throwsA(isA<InvalidQuantityException>()));
    await post(MovementType.damaged, 1, reason: 'Crushed in transit');
    expect((await balance()).physicalQuantity, 9 * k);
  });

  test('negative override needs the setting AND an authorised user', () async {
    await post(MovementType.purchase, 5);
    // setting off -> refused even for admin
    expect(() => post(MovementType.sale, 8, override: true, user: adminId),
        throwsA(isA<NegativeOverrideNotAllowedException>()));
    await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(
        settingKey: StockEngine.settingAllowNegative, settingValue: 'true'));
    // operator without permission -> refused
    final op = await db.into(db.users).insertReturning(UsersCompanion.insert(name: 'Op'));
    expect(() => post(MovementType.sale, 8, override: true, user: op.id),
        throwsA(isA<NegativeOverrideNotAllowedException>()));
    // no user at all -> refused
    expect(() => post(MovementType.sale, 8, override: true),
        throwsA(isA<NegativeOverrideNotAllowedException>()));
    // admin -> allowed, flagged in the ledger
    final r = await post(MovementType.sale, 8, override: true, user: adminId);
    expect(r.overrideUsed, true);
    expect(r.movement.newQuantity, -3 * k);
    expect(r.movement.notes, contains('NEGATIVE STOCK OVERRIDE'));
  });

  test('correction works in both directions', () async {
    await post(MovementType.purchase, 10);
    await post(MovementType.correction, 3, dir: StockDirection.outbound, reason: 'Count');
    expect((await balance()).physicalQuantity, 7 * k);
    await post(MovementType.correction, 2, dir: StockDirection.inbound, reason: 'Count');
    expect((await balance()).physicalQuantity, 9 * k);
  });

  test('ledger reconciles with balance (sum in - sum out == physical)', () async {
    await post(MovementType.purchase, 100);
    await post(MovementType.sale, 30);
    await post(MovementType.customerReturn, 5);
    await post(MovementType.lost, 2, reason: 'Missing');
    final rows = await db.select(db.stockMovements).get();
    final net = rows.fold<int>(0, (s, m) => s + m.quantityIn - m.quantityOut);
    expect(net, (await balance()).physicalQuantity);
    // chain integrity: each row's previous equals the prior row's new
    var running = 0;
    for (final m in rows) {
      expect(m.previousQuantity, running);
      running = m.newQuantity;
    }
  });
}

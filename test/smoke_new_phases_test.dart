import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kqas/database/app_database.dart';
import 'package:kqas/features/invoices/data/invoice_repository.dart';
import 'package:kqas/features/invoices/domain/invoice_models.dart';
import 'package:kqas/features/notifications/data/notification_repository.dart';
import 'package:kqas/features/scanning/data/scan_session_repository.dart';
import 'package:kqas/features/stock_movements/data/reservation_engine.dart';
import 'package:kqas/features/stock_movements/data/stock_engine.dart';
import 'package:kqas/features/stock_movements/domain/movement_type.dart';
import 'package:kqas/features/stock_movements/data/transfer_service.dart';
import 'package:kqas/features/stocktaking/data/stocktaking_repository.dart';
import 'package:kqas/features/users/data/user_repository.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('invoice receive updates stock', () async {
    final unit = (await db.select(db.units).get()).firstWhere((u) => u.symbol == 'pcs');
    final wh = (await db.select(db.warehouses).get()).first;
    await db.into(db.products).insert(ProductsCompanion.insert(id: const Value('p1'), name: 'P', unitId: unit.id));
    final repo = InvoiceRepository(db, StockEngine(db));
    final id = await repo.createIncoming(invoiceNumber: 'INV-1', items: [InvoiceItemInput(productId: 'p1', expectedQuantity: 10)]);
    await repo.submit(id);
    final item = (await repo.watchItems(id).first).first;
    await repo.receiveItem(invoiceId: id, itemId: item.id, quantity: 10, warehouseId: wh.id);
    final bal = await (db.select(db.inventoryBalances)..where((b) => b.productId.equals('p1'))).getSingle();
    expect(bal.physicalQuantity, 10);
    final inv = await repo.getById(id);
    expect(inv!.status, 'received');
  });

  test('scan session complete loading', () async {
    final unit = (await db.select(db.units).get()).firstWhere((u) => u.symbol == 'pcs');
    final wh = (await db.select(db.warehouses).get()).first;
    await db.into(db.products).insert(ProductsCompanion.insert(id: const Value('p1'), name: 'P', unitId: unit.id));
    final invRepo = InvoiceRepository(db, StockEngine(db));
    final id = await invRepo.createIncoming(invoiceNumber: 'INV-2', items: [InvoiceItemInput(productId: 'p1', expectedQuantity: 5)]);
    await invRepo.submit(id);
    final scanRepo = ScanSessionRepository(db, StockEngine(db), invRepo);
    final sid = await scanRepo.createSession(sessionType: 'loading', warehouseId: wh.id, invoiceId: id);
    await scanRepo.setScannedQuantity(sessionId: sid, productId: 'p1', scannedQuantity: 5);
    await scanRepo.complete(sid);
    final bal = await (db.select(db.inventoryBalances)..where((b) => b.productId.equals('p1'))).getSingle();
    expect(bal.physicalQuantity, 5);
  });

  test('reservation reserve/release', () async {
    final unit = (await db.select(db.units).get()).firstWhere((u) => u.symbol == 'pcs');
    final wh = (await db.select(db.warehouses).get()).first;
    await db.into(db.products).insert(ProductsCompanion.insert(id: const Value('p1'), name: 'P', unitId: unit.id));
    await StockEngine(db).post(operationId: 'o1', productId: 'p1', warehouseId: wh.id, type: MovementType.openingBalance, quantity: 10);
    await db.into(db.scanSessions).insert(ScanSessionsCompanion.insert(sessionType: 'loading', warehouseId: wh.id));
    final sid = (await db.select(db.scanSessions).get()).first.id;
    final re = ReservationEngine(db);
    final rid = await re.reserve(productId: 'p1', warehouseId: wh.id, sessionId: sid, quantity: 4);
    final bal = await (db.select(db.inventoryBalances)..where((b) => b.productId.equals('p1'))).getSingle();
    expect(bal.reservedQuantity, 4);
    await re.release(rid);
    final bal2 = await (db.select(db.inventoryBalances)..where((b) => b.productId.equals('p1'))).getSingle();
    expect(bal2.reservedQuantity, 0);
  });

  test('stocktaking complete', () async {
    final unit = (await db.select(db.units).get()).firstWhere((u) => u.symbol == 'pcs');
    final wh = (await db.select(db.warehouses).get()).first;
    await db.into(db.products).insert(ProductsCompanion.insert(id: const Value('p1'), name: 'P', unitId: unit.id));
    await StockEngine(db).post(operationId: 'o1', productId: 'p1', warehouseId: wh.id, type: MovementType.openingBalance, quantity: 10);
    final repo = StocktakingRepository(db, StockEngine(db));
    final sid = await repo.createSession(warehouseId: wh.id);
    final its = await repo.items(sid);
    await repo.setCounted(itemId: its.first.id, countedQuantity: 8);
    await repo.complete(sid);
    final bal = await (db.select(db.inventoryBalances)..where((b) => b.productId.equals('p1'))).getSingle();
    expect(bal.physicalQuantity, 8);
  });

  test('transfer', () async {
    final unit = (await db.select(db.units).get()).firstWhere((u) => u.symbol == 'pcs');
    final whs = await db.select(db.warehouses).get();
    final w1 = whs.first.id;
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'W2'));
    final w2 = (await db.select(db.warehouses).get()).last.id;
    await db.into(db.products).insert(ProductsCompanion.insert(id: const Value('p1'), name: 'P', unitId: unit.id));
    await StockEngine(db).post(operationId: 'o1', productId: 'p1', warehouseId: w1, type: MovementType.openingBalance, quantity: 10);
    final ts = TransferService(db, StockEngine(db));
    await ts.transfer(productId: 'p1', fromWarehouseId: w1, toWarehouseId: w2, quantity: 4);
    final b1 = await (db.select(db.inventoryBalances)..where((b) => b.warehouseId.equals(w1))).getSingle();
    final b2 = await (db.select(db.inventoryBalances)..where((b) => b.warehouseId.equals(w2))).getSingle();
    expect(b1.physicalQuantity, 6);
    expect(b2.physicalQuantity, 4);
  });

  test('notifications', () async {
    final nr = NotificationRepository(db);
    final id = await nr.create(type: 'info', title: 't', message: 'm');
    expect((await nr.watchAll().first).length, 1);
    await nr.markRead(id);
    expect(await nr.unreadCount(), 0);
  });

  test('users', () async {
    final ur = UserRepository(db);
    final id = await ur.create(name: 'Bob', role: 'operator');
    await ur.update(id, isActive: false);
    final u = (await db.select(db.users).get()).firstWhere((x) => x.id == id);
    expect(u.isActive, false);
  });
}
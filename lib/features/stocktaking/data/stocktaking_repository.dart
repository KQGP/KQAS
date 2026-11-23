import 'package:drift/drift.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../database/app_database.dart';
import '../../stock_movements/data/stock_engine.dart';
import '../../stock_movements/domain/movement_type.dart';

class StocktakingRepository {
  StocktakingRepository(AppDatabase db, [StockEngine? engine])
      : _db = db,
        _engine = engine ?? StockEngine(db);

  final AppDatabase _db;
  final StockEngine _engine;

  Future<String> createSession({required String warehouseId}) async {
    final row = await _db.into(_db.stocktakingSessions).insertReturning(StocktakingSessionsCompanion.insert(
          warehouseId: warehouseId,
        ));
    // seed items with system quantities
    final balances = await (_db.select(_db.inventoryBalances)..where((b) => b.warehouseId.equals(warehouseId))).get();
    for (final b in balances) {
      await _db.into(_db.stocktakingItems).insert(StocktakingItemsCompanion.insert(
            sessionId: row.id,
            productId: b.productId,
            systemQuantity: b.physicalQuantity,
          ));
    }
    return row.id;
  }

  Future<List<StocktakingItem>> items(String sessionId) =>
      (_db.select(_db.stocktakingItems)..where((i) => i.sessionId.equals(sessionId))).get();

  Future<void> setCounted({required String itemId, required int countedQuantity}) async {
    final row = await (_db.select(_db.stocktakingItems)..where((i) => i.id.equals(itemId))).getSingleOrNull();
    if (row == null) return;
    final diff = countedQuantity - row.systemQuantity;
    await (_db.update(_db.stocktakingItems)..where((i) => i.id.equals(itemId))).write(
        StocktakingItemsCompanion(countedQuantity: Value(countedQuantity), difference: Value(diff)));
  }

  Future<void> complete(String sessionId, {String? userId, String? reason}) => _db.transaction(() async {
        final session = await (_db.select(_db.stocktakingSessions)..where((s) => s.id.equals(sessionId))).getSingleOrNull();
        if (session == null) throw const ValidationException('Stocktaking session not found.');
        if (session.status != 'counting') throw const ValidationException('Session is not in counting state.');
        final its = await items(sessionId);
        for (final it in its) {
          final counted = it.countedQuantity;
          if (counted == null) continue;
          final diff = counted - it.systemQuantity;
          if (diff == 0) continue;
          final dir = diff > 0 ? StockDirection.inbound : StockDirection.outbound;
          await _engine.post(
            operationId: 'stocktaking:$sessionId:${it.productId}',
            productId: it.productId,
            warehouseId: session.warehouseId,
            type: diff > 0 ? MovementType.manualIncrease : MovementType.manualDecrease,
            direction: dir,
            quantity: diff.abs(),
            userId: userId,
            reason: reason ?? 'Stocktaking adjustment',
            notes: 'Stocktaking session $sessionId',
          );
        }
        final ss1 = _db.update(_db.stocktakingSessions)..where((s) => s.id.equals(sessionId));
        await ss1.write(StocktakingSessionsCompanion(status: const Value('completed'), completedAt: Value(DateTime.now().toUtc())));
      });

  // ---- aliases for compatibility ----
  Future<String> create({required String warehouseId}) => createSession(warehouseId: warehouseId);
  Future<String> start({required String warehouseId}) => createSession(warehouseId: warehouseId);
  Future<String> startSession({required String warehouseId}) => createSession(warehouseId: warehouseId);
  Future<void> count({required String itemId, required int countedQuantity}) => setCounted(itemId: itemId, countedQuantity: countedQuantity);
  Future<void> setCount({required String itemId, required int countedQuantity}) => setCounted(itemId: itemId, countedQuantity: countedQuantity);
  Future<void> finish(String sessionId, {String? userId, String? reason}) => complete(sessionId, userId: userId, reason: reason);

  Future<void> cancel(String sessionId) => _db.transaction(() async {
        final ss2 = _db.update(_db.stocktakingSessions)..where((s) => s.id.equals(sessionId));
        await ss2.write(StocktakingSessionsCompanion(status: const Value('cancelled'), completedAt: Value(DateTime.now().toUtc())));
      });
}


typedef StocktakingService = StocktakingRepository;

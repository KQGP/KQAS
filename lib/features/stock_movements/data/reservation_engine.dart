import 'package:drift/drift.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../database/app_database.dart';

/// Manages stock_reservations and reserved_quantity on inventory_balances.
class ReservationEngine {
  ReservationEngine(this._db);
  final AppDatabase _db;

  Future<String> reserve({
    required String productId,
    required String warehouseId,
    required String sessionId,
    required int quantity,
  }) => _db.transaction(() async {
        if (quantity <= 0) throw const InvalidQuantityException();
        final bal = await (_db.select(_db.inventoryBalances)
              ..where((b) => b.productId.equals(productId) & b.warehouseId.equals(warehouseId)))
            .getSingleOrNull();
        final avail = (bal?.physicalQuantity ?? 0) - (bal?.reservedQuantity ?? 0);
        if (quantity > avail) {
          throw const ValidationException('Not enough available stock to reserve.');
        }
        final row = await _db.into(_db.stockReservations).insertReturning(StockReservationsCompanion.insert(
              productId: productId,
              warehouseId: warehouseId,
              sessionId: sessionId,
              quantity: quantity,
            ));
        if (bal == null) {
          await _db.into(_db.inventoryBalances).insert(InventoryBalancesCompanion.insert(
                productId: productId,
                warehouseId: warehouseId,
                physicalQuantity: const Value(0),
                reservedQuantity: Value(quantity),
              ));
        } else {
          final rb1 = _db.update(_db.inventoryBalances)..where((b) => b.id.equals(bal.id));
          await rb1.write(InventoryBalancesCompanion(reservedQuantity: Value(bal.reservedQuantity + quantity)));
        }
        return row.id;
      });

  Future<void> release(String reservationId) => _db.transaction(() async {
        final r = await (_db.select(_db.stockReservations)..where((x) => x.id.equals(reservationId))).getSingleOrNull();
        if (r == null) return;
        if (r.status != 'active') return;
        await (_db.update(_db.stockReservations)..where((x) => x.id.equals(reservationId)))
            .write(const StockReservationsCompanion(status: Value('released')));
        final bal = await (_db.select(_db.inventoryBalances)
              ..where((b) => b.productId.equals(r.productId) & b.warehouseId.equals(r.warehouseId)))
            .getSingleOrNull();
        if (bal != null) {
          final newRes = bal.reservedQuantity - r.quantity;
          final rb2 = _db.update(_db.inventoryBalances)..where((b) => b.id.equals(bal.id));
          await rb2.write(InventoryBalancesCompanion(reservedQuantity: Value(newRes < 0 ? 0 : newRes)));
        }
      });

  // ---- aliases for compatibility ----
  Future<String> createReservation({required String productId, required String warehouseId, required String sessionId, required int quantity}) =>
      reserve(productId: productId, warehouseId: warehouseId, sessionId: sessionId, quantity: quantity);
  Future<void> releaseReservation(String reservationId) => release(reservationId);
  Future<void> releaseSessionReservations(String sessionId) => releaseSession(sessionId);

  Future<void> releaseSession(String sessionId) async {
    final rows = await (_db.select(_db.stockReservations)..where((r) => r.sessionId.equals(sessionId) & r.status.equals('active'))).get();
    for (final r in rows) await release(r.id);
  }

  Future<void> convert(String reservationId) => _db.transaction(() async {
        final r = await (_db.select(_db.stockReservations)..where((x) => x.id.equals(reservationId))).getSingleOrNull();
        if (r == null || r.status != 'active') return;
        await (_db.update(_db.stockReservations)..where((x) => x.id.equals(reservationId)))
            .write(const StockReservationsCompanion(status: Value('converted')));
        final bal = await (_db.select(_db.inventoryBalances)
              ..where((b) => b.productId.equals(r.productId) & b.warehouseId.equals(r.warehouseId)))
            .getSingleOrNull();
        if (bal != null) {
          final newRes = bal.reservedQuantity - r.quantity;
          final rc = _db.update(_db.inventoryBalances)..where((b) => b.id.equals(bal.id));
          await rc.write(InventoryBalancesCompanion(reservedQuantity: Value(newRes < 0 ? 0 : newRes)));
        }
      });
}


typedef ReservationService = ReservationEngine;
typedef ReservationsEngine = ReservationEngine;

import 'package:drift/drift.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../database/app_database.dart';
import '../domain/movement_type.dart';

class StockPosting {
  const StockPosting(this.movement, {this.alreadyPosted = false, this.overrideUsed = false});
  final StockMovement movement;

  /// true when the same operationId had already been posted (idempotent no-op).
  final bool alreadyPosted;
  final bool overrideUsed;
}

/// The ONLY place allowed to change inventory_balances.physical_quantity.
/// Every call is one DB transaction: balance update + ledger row together.
class StockEngine {
  StockEngine(this._db, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  static const settingAllowNegative = 'allow_negative_stock';

  Future<StockPosting> post({
    required String operationId,
    required String productId,
    required String warehouseId,
    String? locationId,
    required MovementType type,
    StockDirection? direction,
    required int quantity,
    String? invoiceId,
    String? sessionId,
    String? referenceId,
    String? userId,
    String? reason,
    String? notes,
    bool allowNegativeOverride = false,
  }) {
    return _db.transaction(() async {
      // 1. Idempotency: a repeated operationId never posts twice.
      final existing = await (_db.select(_db.stockMovements)
            ..where((m) => m.operationId.equals(operationId)))
          .getSingleOrNull();
      if (existing != null) return StockPosting(existing, alreadyPosted: true);

      // 2. Validation.
      if (quantity <= 0) throw const InvalidQuantityException();
      final dir = type.fixedDirection ?? direction;
      if (dir == null) {
        throw ArgumentError('${type.name} requires an explicit direction');
      }
      if (type.reasonRequired && (reason == null || reason.trim().isEmpty)) {
        throw ReasonRequiredException(type.label);
      }
      final productRow = await (_db.select(_db.products).join([
        innerJoin(_db.units, _db.units.id.equalsExp(_db.products.unitId))
      ])
            ..where(_db.products.id.equals(productId)))
          .getSingleOrNull();
      if (productRow == null) throw const ValidationException('Product not found.');
      final decimals = productRow.readTable(_db.units).decimals;
      final wh = await (_db.select(_db.warehouses)..where((w) => w.id.equals(warehouseId)))
          .getSingleOrNull();
      if (wh == null) throw const ValidationException('Warehouse not found.');

      // 3. Current balance row (one row per product + warehouse + location).
      final balQuery = _db.select(_db.inventoryBalances)
        ..where((b) =>
            b.productId.equals(productId) &
            b.warehouseId.equals(warehouseId) &
            (locationId == null ? b.locationId.isNull() : b.locationId.equals(locationId)));
      final bal = await balQuery.getSingleOrNull();
      final prev = bal?.physicalQuantity ?? 0;
      final reserved = bal?.reservedQuantity ?? 0;
      final newQty = dir == StockDirection.inbound ? prev + quantity : prev - quantity;

      // 4. Available = physical - reserved. Outbound may not exceed it,
      //    unless an explicit, authorised override is used.
      var overrideUsed = false;
      if (dir == StockDirection.outbound && quantity > prev - reserved) {
        if (!allowNegativeOverride) {
          throw InsufficientStockException(
              requested: quantity, physical: prev, reserved: reserved, decimals: decimals);
        }
        await _assertOverrideAllowed(userId);
        overrideUsed = true;
      }

      // 5. Write balance + ledger atomically.
      final ts = _now().toUtc();
      if (bal == null) {
        await _db.into(_db.inventoryBalances).insert(InventoryBalancesCompanion.insert(
            productId: productId,
            warehouseId: warehouseId,
            locationId: Value(locationId),
            physicalQuantity: Value(newQty),
            updatedAt: Value(ts)));
      } else {
        await (_db.update(_db.inventoryBalances)..where((b) => b.id.equals(bal.id))).write(
            InventoryBalancesCompanion(physicalQuantity: Value(newQty), updatedAt: Value(ts)));
      }
      final movement = await _db.into(_db.stockMovements).insertReturning(
          StockMovementsCompanion.insert(
        operationId: operationId,
        productId: productId,
        warehouseId: warehouseId,
        movementType: type.name,
        previousQuantity: prev,
        newQuantity: newQty,
        locationId: Value(locationId),
        quantityIn: Value(dir == StockDirection.inbound ? quantity : 0),
        quantityOut: Value(dir == StockDirection.outbound ? quantity : 0),
        invoiceId: Value(invoiceId),
        sessionId: Value(sessionId),
        referenceId: Value(referenceId),
        userId: Value(userId),
        reason: Value(reason?.trim()),
        notes: Value(overrideUsed
            ? '[NEGATIVE STOCK OVERRIDE] ${notes ?? ''}'.trim()
            : notes),
        createdAt: Value(ts),
      ));
      return StockPosting(movement, overrideUsed: overrideUsed);
    });
  }

  Future<void> _assertOverrideAllowed(String? userId) async {
    final setting = await (_db.select(_db.appSettings)
          ..where((s) => s.settingKey.equals(settingAllowNegative)))
        .getSingleOrNull();
    if (setting?.settingValue != 'true') {
      throw const NegativeOverrideNotAllowedException(
          'Negative stock is disabled. Enable "Allow negative stock" first.');
    }
    final user = userId == null
        ? null
        : await (_db.select(_db.users)..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null || !user.isActive || !user.canOverrideNegativeStock) {
      throw const NegativeOverrideNotAllowedException(
          'You are not authorised to override negative stock.');
    }
  }
}

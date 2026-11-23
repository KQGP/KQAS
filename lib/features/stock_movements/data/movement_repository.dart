import 'package:drift/drift.dart';

import '../../../database/app_database.dart';
import '../domain/movement_type.dart';

class MovementFilter {
  const MovementFilter({
    this.productId,
    this.warehouseId,
    this.invoiceId,
    this.userId,
    this.type,
    this.from,
    this.to,
    this.limit = 200,
  });
  final String? productId, warehouseId, invoiceId, userId;
  final MovementType? type;
  final DateTime? from, to;
  final int limit;

  MovementFilter copyWith({
    Object? type = _unset,
    Object? from = _unset,
    Object? to = _unset,
    int? limit,
  }) =>
      MovementFilter(
        productId: productId,
        warehouseId: warehouseId,
        invoiceId: invoiceId,
        userId: userId,
        type: identical(type, _unset) ? this.type : type as MovementType?,
        from: identical(from, _unset) ? this.from : from as DateTime?,
        to: identical(to, _unset) ? this.to : to as DateTime?,
        limit: limit ?? this.limit,
      );

  @override
  bool operator ==(Object o) =>
      o is MovementFilter &&
      o.productId == productId &&
      o.warehouseId == warehouseId &&
      o.invoiceId == invoiceId &&
      o.userId == userId &&
      o.type == type &&
      o.from == from &&
      o.to == to &&
      o.limit == limit;

  @override
  int get hashCode =>
      Object.hash(productId, warehouseId, invoiceId, userId, type, from, to, limit);
}

const _unset = Object();

class MovementEntry {
  const MovementEntry(this.movement, this.productName, this.warehouseName,
      this.unitSymbol, this.unitDecimals);
  final StockMovement movement;
  final String productName, warehouseName, unitSymbol;
  final int unitDecimals;
  MovementType get type => MovementType.fromName(movement.movementType);
}

class MovementRepository {
  MovementRepository(this._db);
  final AppDatabase _db;

  Stream<List<MovementEntry>> watch(MovementFilter f) {
    final m = _db.stockMovements;
    final q = _db.select(m).join([
      innerJoin(_db.products, _db.products.id.equalsExp(m.productId)),
      innerJoin(_db.units, _db.units.id.equalsExp(_db.products.unitId)),
      innerJoin(_db.warehouses, _db.warehouses.id.equalsExp(m.warehouseId)),
    ]);
    Expression<bool> cond = const Constant(true);
    final productId = f.productId;
    if (productId != null) cond = cond & m.productId.equals(productId);
    final warehouseId = f.warehouseId;
    if (warehouseId != null) cond = cond & m.warehouseId.equals(warehouseId);
    final invoiceId = f.invoiceId;
    if (invoiceId != null) cond = cond & m.invoiceId.equals(invoiceId);
    final userId = f.userId;
    if (userId != null) cond = cond & m.userId.equals(userId);
    final type = f.type;
    if (type != null) cond = cond & m.movementType.equals(type.name);
    final from = f.from;
    if (from != null) cond = cond & m.createdAt.isBiggerOrEqualValue(from);
    final to = f.to;
    if (to != null) cond = cond & m.createdAt.isSmallerOrEqualValue(to);
    q
      ..where(cond)
      ..orderBy([OrderingTerm.desc(m.createdAt), OrderingTerm.desc(m.rowId)])
      ..limit(f.limit);
    return q.watch().map((rows) => [
          for (final r in rows)
            MovementEntry(
              r.readTable(m),
              r.readTable(_db.products).name,
              r.readTable(_db.warehouses).name,
              r.readTable(_db.units).symbol,
              r.readTable(_db.units).decimals,
            )
        ]);
  }
}

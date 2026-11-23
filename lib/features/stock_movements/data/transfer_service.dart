import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../database/app_database.dart';
import 'stock_engine.dart';
import '../domain/movement_type.dart';

const _uuid = Uuid();

class TransferService {
  TransferService(this._db, [StockEngine? engine])
      : _engine = engine ?? StockEngine(_db);

  final AppDatabase _db;
  final StockEngine _engine;

  Future<void> transfer({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    String? fromLocationId,
    String? toLocationId,
    required int quantity,
    String? userId,
    String? reason,
    String? notes,
  }) => _db.transaction(() async {
        if (quantity <= 0) throw const InvalidQuantityException();
        if (fromWarehouseId == toWarehouseId && fromLocationId == toLocationId) {
          throw const ValidationException('Source and destination must differ.');
        }
        final op = 'transfer:${_uuid.v4()}';
        await _engine.post(
          operationId: '$op:out',
          productId: productId,
          warehouseId: fromWarehouseId,
          locationId: fromLocationId,
          type: MovementType.transferOut,
          quantity: quantity,
          userId: userId,
          reason: reason,
          notes: notes,
        );
        await _engine.post(
          operationId: '$op:in',
          productId: productId,
          warehouseId: toWarehouseId,
          locationId: toLocationId,
          type: MovementType.transferIn,
          quantity: quantity,
          userId: userId,
          reason: reason,
          notes: notes,
          referenceId: op,
        );
      });
  // ---- aliases for compatibility ----
  Future<void> transferStock({required String productId, required String fromWarehouseId, required String toWarehouseId, String? fromLocationId, String? toLocationId, required int quantity, String? userId, String? reason, String? notes}) =>
      transfer(productId: productId, fromWarehouseId: fromWarehouseId, toWarehouseId: toWarehouseId, fromLocationId: fromLocationId, toLocationId: toLocationId, quantity: quantity, userId: userId, reason: reason, notes: notes);

}


typedef TransferRepository = TransferService;

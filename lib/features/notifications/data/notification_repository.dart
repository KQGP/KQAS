import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../database/app_database.dart';

class NotificationRepository {
  NotificationRepository(this._db);
  final AppDatabase _db;

  Stream<List<Notification>> watchAll({bool unreadOnly = false}) {
    final q = _db.select(_db.notifications)
      ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]);
    return q.watch().map((rows) {
      if (unreadOnly) return rows.where((n) => !n.isRead).toList();
      return rows;
    });
  }

  Future<int> unreadCount() async {
    final rows = await (_db.select(_db.notifications)..where((n) => n.isRead.equals(false))).get();
    return rows.length;
  }

  Future<String> create({
    required String type,
    required String title,
    required String message,
    String? relatedProductId,
    String? relatedInvoiceId,
  }) async {
    final row = await _db.into(_db.notifications).insertReturning(NotificationsCompanion.insert(
          type: type,
          title: title,
          message: message,
          relatedProductId: Value(relatedProductId),
          relatedInvoiceId: Value(relatedInvoiceId),
        ));
    return row.id;
  }

  Future<void> markRead(String id) => (_db.update(_db.notifications)..where((n) => n.id.equals(id)))
      .write(const NotificationsCompanion(isRead: Value(true)));

  Future<void> markAllRead() => (_db.update(_db.notifications)..where((n) => n.isRead.equals(false)))
      .write(const NotificationsCompanion(isRead: Value(true)));

  Future<void> delete(String id) => (_db.delete(_db.notifications)..where((n) => n.id.equals(id))).go();
}

// Alert state helpers
class AlertService {
  AlertService(this._db, this._notifications);
  final AppDatabase _db;
  final NotificationRepository _notifications;

  /// Evaluate alert state for a product in a warehouse and fire notifications on crossings.
  Future<void> evaluate(String productId, String warehouseId) async {
    final product = await (_db.select(_db.products)..where((p) => p.id.equals(productId))).getSingleOrNull();
    if (product == null || !product.isActive) return;
    final bal = await (_db.select(_db.inventoryBalances)
          ..where((b) => b.productId.equals(productId) & b.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    final phys = bal?.physicalQuantity ?? 0;
    String newState;
    if (phys <= 0) newState = 'out';
    else if (product.minStock > 0 && phys <= product.minStock) newState = 'low';
    else newState = 'healthy';

    final existing = await (_db.select(_db.alertStates)
          ..where((a) => a.productId.equals(productId) & a.warehouseId.equals(warehouseId)))
        .getSingleOrNull();
    final oldState = existing?.state ?? 'healthy';
    if (existing == null) {
      await _db.into(_db.alertStates).insert(AlertStatesCompanion.insert(
            productId: productId,
            warehouseId: warehouseId,
            state: Value(newState),
          ));
    } else {
      await (_db.update(_db.alertStates)
            ..where((a) => a.productId.equals(productId) & a.warehouseId.equals(warehouseId)))
          .write(AlertStatesCompanion(state: Value(newState), updatedAt: Value(DateTime.now().toUtc())));
    }
    if (oldState == newState) return;
    if (newState == 'low') {
      await _notifications.create(
        type: 'low_stock',
        title: 'Low stock: ${product.name}',
        message: 'Stock has fallen to or below the minimum level.',
        relatedProductId: productId,
      );
    } else if (newState == 'out') {
      await _notifications.create(
        type: 'out_of_stock',
        title: 'Out of stock: ${product.name}',
        message: 'Stock is depleted.',
        relatedProductId: productId,
      );
    }
  }
}


typedef NotificationsRepository = NotificationRepository;
typedef AlertRepository = NotificationRepository;

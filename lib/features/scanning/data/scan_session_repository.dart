import 'package:drift/drift.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../database/app_database.dart';
import '../../invoices/data/invoice_repository.dart';
import '../../stock_movements/data/stock_engine.dart';
import '../../stock_movements/domain/movement_type.dart';

class ScanSessionRepository {
  ScanSessionRepository(AppDatabase db, [StockEngine? engine, InvoiceRepository? invoices])
      : _db = db,
        _engine = engine ?? StockEngine(db),
        _invoices = invoices ?? InvoiceRepository(db, engine ?? StockEngine(db));

  final AppDatabase _db;
  final StockEngine _engine;
  final InvoiceRepository _invoices;

  Future<String> createSession({
    required String sessionType, // loading | unloading
    required String warehouseId,
    String? invoiceId,
  }) async {
    if (sessionType != 'loading' && sessionType != 'unloading') {
      throw const ValidationException('Invalid session type.');
    }
    final row = await _db.into(_db.scanSessions).insertReturning(ScanSessionsCompanion.insert(
          sessionType: sessionType,
          warehouseId: warehouseId,
          invoiceId: Value(invoiceId),
        ));
    // If linked to an invoice, seed expected items.
    if (invoiceId != null) {
      final items = await (_db.select(_db.invoiceItems)..where((i) => i.invoiceId.equals(invoiceId))).get();
      for (final it in items) {
        if (it.productId == null) continue;
        await _db.into(_db.scanSessionItems).insert(ScanSessionItemsCompanion.insert(
              sessionId: row.id,
              productId: it.productId!,
              expectedQuantity: it.expectedQuantity,
            ));
      }
    }
    return row.id;
  }

  Future<void> logScan({
    required String sessionId,
    required String barcode,
    String? productId,
    String result = 'valid',
  }) async {
    await _db.into(_db.scanLogs).insert(ScanLogsCompanion.insert(
          sessionId: Value(sessionId),
          productId: Value(productId),
          barcode: barcode,
          scanResult: result,
        ));
  }

  Future<void> setScannedQuantity({
    required String sessionId,
    required String productId,
    required int scannedQuantity,
  }) async {
    final row = await (_db.select(_db.scanSessionItems)
          ..where((i) => i.sessionId.equals(sessionId) & i.productId.equals(productId)))
        .getSingleOrNull();
    if (row == null) {
      await _db.into(_db.scanSessionItems).insert(ScanSessionItemsCompanion.insert(
            sessionId: sessionId,
            productId: productId,
            expectedQuantity: 0,
            scannedQuantity: Value(scannedQuantity),
          ));
    } else {
      await (_db.update(_db.scanSessionItems)
            ..where((i) => i.id.equals(row.id)))
          .write(ScanSessionItemsCompanion(scannedQuantity: Value(scannedQuantity)));
    }
  }

  Future<void> incrementScanned({
    required String sessionId,
    required String productId,
    int by = 1,
  }) async {
    final row = await (_db.select(_db.scanSessionItems)
          ..where((i) => i.sessionId.equals(sessionId) & i.productId.equals(productId)))
        .getSingleOrNull();
    final current = row?.scannedQuantity ?? 0;
    await setScannedQuantity(sessionId: sessionId, productId: productId, scannedQuantity: current + by);
  }

  Future<List<ScanSessionItem>> items(String sessionId) =>
      (_db.select(_db.scanSessionItems)..where((i) => i.sessionId.equals(sessionId))).get();

  Future<void> completeLoading(String sessionId, {String? userId}) =>
      complete(sessionId, userId: userId);

  Future<void> completeUnloading(String sessionId, {String? userId}) =>
      complete(sessionId, userId: userId);

  Future<void> complete(String sessionId, {String? userId}) => _db.transaction(() async {
        final session = await (_db.select(_db.scanSessions)..where((s) => s.id.equals(sessionId))).getSingleOrNull();
        if (session == null) throw const ValidationException('Scan session not found.');
        if (session.status != 'active' && session.status != 'paused') {
          throw const ValidationException('Session is not completable.');
        }
        final its = await items(sessionId);
        final invId = session.invoiceId;
        if (session.sessionType == 'loading') {
          for (final it in its) {
            if (it.scannedQuantity <= 0) continue;
            await _engine.post(
              operationId: 'scan:load:$sessionId:${it.productId}',
              productId: it.productId,
              warehouseId: session.warehouseId,
              type: MovementType.purchase,
              quantity: it.scannedQuantity,
              invoiceId: invId,
              sessionId: sessionId,
              userId: userId,
              notes: 'Loading scan session',
            );
            if (invId != null) {
              // update invoice item received quantity by matching product
              final invItems = await (_db.select(_db.invoiceItems)
                    ..where((i) => i.invoiceId.equals(invId) & i.productId.equals(it.productId)))
                  .get();
              for (final ii in invItems) {
                final newReceived = ii.receivedQuantity + it.scannedQuantity;
                final capped = newReceived > ii.expectedQuantity ? ii.expectedQuantity : newReceived;
                await (_db.update(_db.invoiceItems)..where((i) => i.id.equals(ii.id))).write(
                    InvoiceItemsCompanion(receivedQuantity: Value(capped)));
              }
            }
          }
        } else {
          for (final it in its) {
            if (it.scannedQuantity <= 0) continue;
            await _engine.post(
              operationId: 'scan:unload:$sessionId:${it.productId}',
              productId: it.productId,
              warehouseId: session.warehouseId,
              type: MovementType.sale,
              quantity: it.scannedQuantity,
              invoiceId: invId,
              sessionId: sessionId,
              userId: userId,
              notes: 'Unloading scan session',
            );
            if (invId != null) {
              final invItems = await (_db.select(_db.invoiceItems)
                    ..where((i) => i.invoiceId.equals(invId) & i.productId.equals(it.productId)))
                  .get();
              for (final ii in invItems) {
                final newDisp = ii.dispatchedQuantity + it.scannedQuantity;
                final capped = newDisp > ii.expectedQuantity ? ii.expectedQuantity : newDisp;
                await (_db.update(_db.invoiceItems)..where((i) => i.id.equals(ii.id))).write(
                    InvoiceItemsCompanion(dispatchedQuantity: Value(capped)));
              }
            }
          }
        }
        // update invoice status if linked
        if (invId != null) {
          final inv = await _invoices.getById(invId);
          if (inv != null) {
            final items = await (_db.select(_db.invoiceItems)..where((i) => i.invoiceId.equals(invId))).get();
            if (inv.invoiceType == 'incoming') {
              final done = items.every((i) => i.receivedQuantity >= i.expectedQuantity);
              final sc1 = _db.update(_db.invoices)..where((i) => i.id.equals(invId));
              await sc1.write(InvoicesCompanion(status: Value(done ? 'received' : 'partiallyReceived')));
            } else {
              final done = items.every((i) => i.dispatchedQuantity >= i.expectedQuantity);
              final sc2 = _db.update(_db.invoices)..where((i) => i.id.equals(invId));
              await sc2.write(InvoicesCompanion(status: Value(done ? 'dispatched' : 'partiallyDispatched')));
            }
          }
        }
        final sc3 = _db.update(_db.scanSessions)..where((s) => s.id.equals(sessionId));
        await sc3.write(ScanSessionsCompanion(status: const Value('completed'), completedAt: Value(DateTime.now().toUtc())));
      });

  // ---- aliases for compatibility ----
  Future<String> create({required String sessionType, required String warehouseId, String? invoiceId}) =>
      createSession(sessionType: sessionType, warehouseId: warehouseId, invoiceId: invoiceId);
  Future<String> startSession({required String sessionType, required String warehouseId, String? invoiceId}) =>
      createSession(sessionType: sessionType, warehouseId: warehouseId, invoiceId: invoiceId);
  Future<void> log({required String sessionId, required String barcode, String? productId, String result = 'valid'}) =>
      logScan(sessionId: sessionId, barcode: barcode, productId: productId, result: result);
  Future<void> scan({required String sessionId, required String productId, int by = 1}) =>
      incrementScanned(sessionId: sessionId, productId: productId, by: by);
  Future<void> completeLoadingSession(String sessionId, {String? userId}) => completeLoading(sessionId, userId: userId);
  Future<void> completeUnloadingSession(String sessionId, {String? userId}) => completeUnloading(sessionId, userId: userId);

  Future<void> cancel(String sessionId) => _db.transaction(() async {
        final session = await (_db.select(_db.scanSessions)..where((s) => s.id.equals(sessionId))).getSingleOrNull();
        if (session == null) return;
        // release reservations if any (handled by reservation service separately)
        final sc4 = _db.update(_db.scanSessions)..where((s) => s.id.equals(sessionId));
        await sc4.write(ScanSessionsCompanion(status: const Value('cancelled'), completedAt: Value(DateTime.now().toUtc())));
      });

  Future<void> pause(String sessionId) => (_db.update(_db.scanSessions)..where((s) => s.id.equals(sessionId)))
      .write(const ScanSessionsCompanion(status: Value('paused')));

  Future<void> resume(String sessionId) => (_db.update(_db.scanSessions)..where((s) => s.id.equals(sessionId)))
      .write(const ScanSessionsCompanion(status: Value('active')));
}


typedef ScanRepository = ScanSessionRepository;
typedef ScanningRepository = ScanSessionRepository;
typedef ScannerRepository = ScanSessionRepository;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../database/app_database.dart';
import '../../../database/tables/common.dart';
import '../../../features/stock_movements/data/stock_engine.dart';
import '../../../features/stock_movements/domain/movement_type.dart';
import '../domain/invoice_models.dart';

const _uuid = Uuid();

class InvoiceRepository {
  InvoiceRepository(AppDatabase db, [StockEngine? engine])
      : _db = db,
        _engine = engine ?? StockEngine(db);

  final AppDatabase _db;
  final StockEngine _engine;

  // ---------------------------------------------------------------- queries

  Stream<List<Invoice>> watchAll({String? type, String? status}) {
    final q = _db.select(_db.invoices);
    // Apply filters via where if needed (drift where supports).
    return q.watch().map((rows) {
      var out = rows;
      if (type != null) out = out.where((i) => i.invoiceType == type).toList();
      if (status != null) out = out.where((i) => i.status == status).toList();
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    });
  }

  Future<Invoice?> getById(String id) => (_db.select(_db.invoices)..where((i) => i.id.equals(id))).getSingleOrNull();

  Stream<List<InvoiceItem>> watchItems(String invoiceId) =>
      (_db.select(_db.invoiceItems)..where((i) => i.invoiceId.equals(invoiceId))).watch();

  // ---------------------------------------------------------------- mutations

  Future<String> create(InvoiceInput input) => _db.transaction(() async {
        _validate(input);
        final id = input.id ?? _uuid.v4();
        final ts = DateTime.now().toUtc();
        final invDate = (input.invoiceDate ?? DateTime.now()).toUtc();
        await _db.into(_db.invoices).insert(InvoicesCompanion.insert(
              id: Value(id),
              invoiceNumber: input.invoiceNumber.trim(),
              invoiceType: input.type.wire,
              supplierId: Value(input.supplierId),
              customerId: Value(input.customerId),
              invoiceDate: invDate,
              status: const Value('draft'),
              notes: Value(input.notes),
              sourcePdfPath: Value(input.sourcePdfPath),
              createdAt: Value(ts),
            ));
        for (final it in input.items) {
          await _addItem(id, it);
        }
        await _recalcTotals(id);
        return id;
      });

  Future<String> createIncoming({
    required String invoiceNumber,
    String? supplierId,
    DateTime? invoiceDate,
    String? notes,
    List<InvoiceItemInput> items = const [],
  }) =>
      create(InvoiceInput(
        invoiceNumber: invoiceNumber,
        type: InvoiceType.incoming,
        supplierId: supplierId,
        invoiceDate: invoiceDate,
        notes: notes,
        items: items,
      ));

  Future<String> createOutgoing({
    required String invoiceNumber,
    String? customerId,
    DateTime? invoiceDate,
    String? notes,
    List<InvoiceItemInput> items = const [],
  }) =>
      create(InvoiceInput(
        invoiceNumber: invoiceNumber,
        type: InvoiceType.outgoing,
        customerId: customerId,
        invoiceDate: invoiceDate,
        notes: notes,
        items: items,
      ));

  Future<void> addItem(String invoiceId, InvoiceItemInput item) => _db.transaction(() async {
        final inv = await getById(invoiceId);
        if (inv == null) throw const ValidationException('Invoice not found.');
        if (inv.status != 'draft') throw const ValidationException('Items can only be changed on a draft invoice.');
        await _addItem(invoiceId, item);
        await _recalcTotals(invoiceId);
      });

  Future<void> removeItem(String itemId) => _db.transaction(() async {
        final item = await (_db.select(_db.invoiceItems)..where((i) => i.id.equals(itemId))).getSingleOrNull();
        if (item == null) return;
        final inv = await getById(item.invoiceId);
        if (inv != null && inv.status != 'draft') throw const ValidationException('Items can only be changed on a draft invoice.');
        await (_db.delete(_db.invoiceItems)..where((i) => i.id.equals(itemId))).go();
        if (item.invoiceId.isNotEmpty) await _recalcTotals(item.invoiceId);
      });

  Future<void> submit(String invoiceId) => _db.transaction(() async {
        final inv = await getById(invoiceId);
        if (inv == null) throw const ValidationException('Invoice not found.');
        if (inv.status != 'draft') throw const ValidationException('Only draft invoices can be submitted.');
        final items = await (_db.select(_db.invoiceItems)..where((i) => i.invoiceId.equals(invoiceId))).get();
        if (items.isEmpty) throw const ValidationException('Invoice has no items.');
        final stmt = _db.update(_db.invoices)..where((i) => i.id.equals(invoiceId));
        await stmt.write(InvoicesCompanion(status: const Value('pending'), approvedAt: Value(DateTime.now().toUtc())));
      });

  Future<void> cancel(String invoiceId, {String? reason, String? userId, String? warehouseId}) => _db.transaction(() async {
        final inv = await getById(invoiceId);
        if (inv == null) throw const ValidationException('Invoice not found.');
        if (inv.status == 'cancelled' || inv.status == 'reversed') return;
        // Reverse posted stock if any.
        final items = await (_db.select(_db.invoiceItems)..where((i) => i.invoiceId.equals(invoiceId))).get();
        if (warehouseId != null) {
          if (inv.invoiceType == 'incoming') {
            for (final it in items) {
              if (it.receivedQuantity <= 0 || it.productId == null) continue;
              await _engine.post(
                operationId: 'invoice:cancel:recv:${inv.id}:${it.id}',
                productId: it.productId!,
                warehouseId: warehouseId,
                type: MovementType.reversal,
                direction: StockDirection.outbound,
                quantity: it.receivedQuantity,
                invoiceId: inv.id,
                userId: userId,
                reason: reason ?? 'Invoice cancelled',
                notes: 'Reverse received goods',
              );
            }
          } else {
            for (final it in items) {
              if (it.dispatchedQuantity <= 0 || it.productId == null) continue;
              await _engine.post(
                operationId: 'invoice:cancel:disp:${inv.id}:${it.id}',
                productId: it.productId!,
                warehouseId: warehouseId,
                type: MovementType.reversal,
                direction: StockDirection.inbound,
                quantity: it.dispatchedQuantity,
                invoiceId: inv.id,
                userId: userId,
                reason: reason ?? 'Invoice cancelled',
                notes: 'Reverse dispatched goods',
              );
            }
          }
        }
        final st1 = _db.update(_db.invoices)..where((i) => i.id.equals(invoiceId));
        await st1.write(InvoicesCompanion(status: const Value('cancelled'), notes: Value(reason ?? inv.notes)));
      });

  Future<void> receive({
    required String invoiceId,
    required String itemId,
    required int quantity,
    required String warehouseId,
    String? locationId,
    String? userId,
    String? notes,
  }) =>
      receiveItem(invoiceId: invoiceId, itemId: itemId, quantity: quantity, warehouseId: warehouseId, locationId: locationId, userId: userId, notes: notes);

  Future<void> receiveItem({
    required String invoiceId,
    required String itemId,
    required int quantity,
    required String warehouseId,
    String? locationId,
    String? userId,
    String? notes,
  }) => _db.transaction(() async {
        if (quantity <= 0) throw const InvalidQuantityException();
        final inv = await getById(invoiceId);
        if (inv == null) throw const ValidationException('Invoice not found.');
        if (inv.invoiceType != 'incoming') throw const ValidationException('Only incoming invoices can be received.');
        if (inv.status != 'pending' && inv.status != 'partiallyReceived') {
          throw const ValidationException('Invoice is not in a receivable state.');
        }
        final item = await (_db.select(_db.invoiceItems)..where((i) => i.id.equals(itemId))).getSingleOrNull();
        if (item == null || item.invoiceId != invoiceId) throw const ValidationException('Invoice item not found.');
        if (item.productId == null) throw const ValidationException('Item has no linked product.');
        final remaining = item.expectedQuantity - item.receivedQuantity;
        if (quantity > remaining) {
          throw const ValidationException('Receive quantity exceeds remaining expected quantity.');
        }
        await _engine.post(
          operationId: 'invoice:recv:$itemId:${item.receivedQuantity + quantity}',
          productId: item.productId!,
          warehouseId: warehouseId,
          locationId: locationId,
          type: MovementType.purchase,
          quantity: quantity,
          invoiceId: inv.id,
          userId: userId,
          notes: notes ?? 'Received against invoice ${inv.invoiceNumber}',
        );
        final st2 = _db.update(_db.invoiceItems)..where((i) => i.id.equals(itemId));
        await st2.write(InvoiceItemsCompanion(receivedQuantity: Value(item.receivedQuantity + quantity)));
        // status
        final items = await (_db.select(_db.invoiceItems)..where((i) => i.invoiceId.equals(invoiceId))).get();
        final done = items.every((i) => i.receivedQuantity >= i.expectedQuantity);
        final st3 = _db.update(_db.invoices)..where((i) => i.id.equals(invoiceId));
        await st3.write(InvoicesCompanion(status: Value(done ? 'received' : 'partiallyReceived')));
      });

  Future<void> dispatch({
    required String invoiceId,
    required String itemId,
    required int quantity,
    required String warehouseId,
    String? locationId,
    String? userId,
    String? notes,
  }) =>
      dispatchItem(invoiceId: invoiceId, itemId: itemId, quantity: quantity, warehouseId: warehouseId, locationId: locationId, userId: userId, notes: notes);

  Future<void> dispatchItem({
    required String invoiceId,
    required String itemId,
    required int quantity,
    required String warehouseId,
    String? locationId,
    String? userId,
    String? notes,
  }) => _db.transaction(() async {
        if (quantity <= 0) throw const InvalidQuantityException();
        final inv = await getById(invoiceId);
        if (inv == null) throw const ValidationException('Invoice not found.');
        if (inv.invoiceType != 'outgoing') throw const ValidationException('Only outgoing invoices can be dispatched.');
        if (inv.status != 'pending' && inv.status != 'partiallyDispatched') {
          throw const ValidationException('Invoice is not in a dispatchable state.');
        }
        final item = await (_db.select(_db.invoiceItems)..where((i) => i.id.equals(itemId))).getSingleOrNull();
        if (item == null || item.invoiceId != invoiceId) throw const ValidationException('Invoice item not found.');
        if (item.productId == null) throw const ValidationException('Item has no linked product.');
        final remaining = item.expectedQuantity - item.dispatchedQuantity;
        if (quantity > remaining) {
          throw const ValidationException('Dispatch quantity exceeds remaining expected quantity.');
        }
        await _engine.post(
          operationId: 'invoice:disp:$itemId:${item.dispatchedQuantity + quantity}',
          productId: item.productId!,
          warehouseId: warehouseId,
          locationId: locationId,
          type: MovementType.sale,
          quantity: quantity,
          invoiceId: inv.id,
          userId: userId,
          notes: notes ?? 'Dispatched against invoice ${inv.invoiceNumber}',
        );
        final st4 = _db.update(_db.invoiceItems)..where((i) => i.id.equals(itemId));
        await st4.write(InvoiceItemsCompanion(dispatchedQuantity: Value(item.dispatchedQuantity + quantity)));
        final items = await (_db.select(_db.invoiceItems)..where((i) => i.invoiceId.equals(invoiceId))).get();
        final done = items.every((i) => i.dispatchedQuantity >= i.expectedQuantity);
        final st5 = _db.update(_db.invoices)..where((i) => i.id.equals(invoiceId));
        await st5.write(InvoicesCompanion(status: Value(done ? 'dispatched' : 'partiallyDispatched')));
      });

  Future<void> receiveAll(String invoiceId, {required String warehouseId, String? userId}) async {
    final items = await (_db.select(_db.invoiceItems)..where((i) => i.invoiceId.equals(invoiceId))).get();
    for (final it in items) {
      final rem = it.expectedQuantity - it.receivedQuantity;
      if (rem > 0 && it.productId != null) {
        await receiveItem(invoiceId: invoiceId, itemId: it.id, quantity: rem, warehouseId: warehouseId, userId: userId);
      }
    }
  }

  Future<void> dispatchAll(String invoiceId, {required String warehouseId, String? userId}) async {
    final items = await (_db.select(_db.invoiceItems)..where((i) => i.invoiceId.equals(invoiceId))).get();
    for (final it in items) {
      final rem = it.expectedQuantity - it.dispatchedQuantity;
      if (rem > 0 && it.productId != null) {
        await dispatchItem(invoiceId: invoiceId, itemId: it.id, quantity: rem, warehouseId: warehouseId, userId: userId);
      }
    }
  }

  // ---- aliases for compatibility ----
  Future<String> createInvoice(InvoiceInput input) => create(input);
  Future<String> createIncomingInvoice({required String invoiceNumber, String? supplierId, DateTime? invoiceDate, String? notes, List<InvoiceItemInput> items = const []}) =>
      createIncoming(invoiceNumber: invoiceNumber, supplierId: supplierId, invoiceDate: invoiceDate, notes: notes, items: items);
  Future<String> createOutgoingInvoice({required String invoiceNumber, String? customerId, DateTime? invoiceDate, String? notes, List<InvoiceItemInput> items = const []}) =>
      createOutgoing(invoiceNumber: invoiceNumber, customerId: customerId, invoiceDate: invoiceDate, notes: notes, items: items);
  Future<void> receiveGoods({required String invoiceId, required String itemId, required int quantity, required String warehouseId, String? locationId, String? userId, String? notes}) =>
      receiveItem(invoiceId: invoiceId, itemId: itemId, quantity: quantity, warehouseId: warehouseId, locationId: locationId, userId: userId, notes: notes);
  Future<void> receiveInvoice({required String invoiceId, required String itemId, required int quantity, required String warehouseId, String? locationId, String? userId, String? notes}) =>
      receiveItem(invoiceId: invoiceId, itemId: itemId, quantity: quantity, warehouseId: warehouseId, locationId: locationId, userId: userId, notes: notes);
  Future<void> dispatchGoods({required String invoiceId, required String itemId, required int quantity, required String warehouseId, String? locationId, String? userId, String? notes}) =>
      dispatchItem(invoiceId: invoiceId, itemId: itemId, quantity: quantity, warehouseId: warehouseId, locationId: locationId, userId: userId, notes: notes);
  Future<void> dispatchInvoice({required String invoiceId, required String itemId, required int quantity, required String warehouseId, String? locationId, String? userId, String? notes}) =>
      dispatchItem(invoiceId: invoiceId, itemId: itemId, quantity: quantity, warehouseId: warehouseId, locationId: locationId, userId: userId, notes: notes);
  Future<void> cancelInvoice(String invoiceId, {String? reason, String? userId, String? warehouseId}) =>
      cancel(invoiceId, reason: reason, userId: userId, warehouseId: warehouseId);

  // ---------------------------------------------------------------- internal

  Future<void> _addItem(String invoiceId, InvoiceItemInput it) async {
    await _db.into(_db.invoiceItems).insert(InvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: Value(it.productId),
          description: Value(it.description),
          sku: Value(it.sku),
          barcode: Value(it.barcode),
          expectedQuantity: it.expectedQuantity,
          unitPriceMinor: Value(it.unitPriceMinor),
          lineTotalMinor: Value(it.unitPriceMinor == null ? null : (it.expectedQuantity * it.unitPriceMinor!) ~/ kQtyScale),
        ));
  }

  Future<void> _recalcTotals(String invoiceId) async {
    final items = await (_db.select(_db.invoiceItems)..where((i) => i.invoiceId.equals(invoiceId))).get();
    final subtotal = items.fold<int>(0, (s, i) => s + (i.lineTotalMinor ?? 0));
    final inv = await getById(invoiceId);
    if (inv == null) return;
    final st = _db.update(_db.invoices)..where((i) => i.id.equals(invoiceId));
    await st.write(InvoicesCompanion(
          subtotalMinor: Value(subtotal),
          totalMinor: Value(subtotal + inv.taxMinor - inv.discountMinor),
        ));
  }

  void _validate(InvoiceInput input) {
    if (input.invoiceNumber.trim().isEmpty) throw const ValidationException('Invoice number is required.');
    if (input.type == InvoiceType.incoming && input.supplierId == null && input.items.isEmpty) {
      // allow
    }
    for (final it in input.items) {
      if (it.expectedQuantity < 0) throw const ValidationException('Expected quantity cannot be negative.');
    }
  }

}


typedef InvoicesRepository = InvoiceRepository;
typedef InvoiceService = InvoiceRepository;

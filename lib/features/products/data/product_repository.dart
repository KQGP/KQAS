import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/utilities/qty_money.dart';
import '../../../database/app_database.dart';
import '../../stock_movements/data/stock_engine.dart';
import '../../stock_movements/domain/movement_type.dart';
import '../domain/product_models.dart';

const _uuid = Uuid();

class ProductRepository {
  ProductRepository(this._db, this._engine, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final StockEngine _engine;
  final DateTime Function() _now;

  // ------------------------------------------------------------------ queries

  static const _selectCols = '''
    SELECT p.id, p.sku, p.name, p.description, p.notes, p.image_path, p.min_stock, p.max_stock,
           p.reorder_quantity, p.weight_grams, p.purchase_price_minor, p.selling_price_minor, p.is_active,
           c.name AS category_name, s.name AS supplier_name,
           u.symbol AS unit_symbol, u.decimals AS unit_decimals,
           COALESCE(b.phys, 0) AS physical, COALESCE(b.resv, 0) AS reserved,
           (SELECT pb.barcode FROM product_barcodes pb WHERE pb.product_id = p.id
              ORDER BY pb.is_primary DESC LIMIT 1) AS primary_barcode
    FROM products p
    JOIN units u ON u.id = p.unit_id
    LEFT JOIN categories c ON c.id = p.category_id
    LEFT JOIN suppliers s ON s.id = p.supplier_id
  ''';

  Stream<List<ProductListItem>> watchList(ProductQuery q) => _run(q: q);

  Stream<ProductListItem?> watchItem(String id) =>
      _run(onlyId: id).map((l) => l.isEmpty ? null : l.first);

  Stream<List<ProductListItem>> _run({ProductQuery? q, String? onlyId}) {
    final vars = <Variable>[];
    final where = <String>[];
    final warehouse = q?.warehouseId;

    final balSub = StringBuffer(
        'SELECT product_id, SUM(physical_quantity) AS phys, SUM(reserved_quantity) AS resv '
        'FROM inventory_balances ');
    if (warehouse != null) {
      balSub.write('WHERE warehouse_id = ? ');
      vars.add(Variable<String>(warehouse));
    }
    balSub.write('GROUP BY product_id');

    const phys = 'COALESCE(b.phys, 0)';
    if (onlyId != null) {
      where.add('p.id = ?');
      vars.add(Variable<String>(onlyId));
    } else {
      final query = q ?? const ProductQuery();
      where.add(query.filter == StockFilter.archived ? 'p.is_active = 0' : 'p.is_active = 1');
      switch (query.filter) {
        case StockFilter.inStock:
          where.add('$phys > 0');
        case StockFilter.low:
          where.add('$phys > 0 AND p.min_stock > 0 AND $phys <= p.min_stock');
        case StockFilter.out:
          where.add('$phys <= 0');
        case StockFilter.overstocked:
          where.add('p.max_stock IS NOT NULL AND $phys > p.max_stock');
        case StockFilter.all:
        case StockFilter.archived:
          break;
      }
      final text = query.search.trim();
      if (text.isNotEmpty) {
        final like = Variable<String>('%$text%');
        where.add('(p.name LIKE ? OR p.sku LIKE ? OR p.description LIKE ? OR c.name LIKE ? '
            'OR s.name LIKE ? OR EXISTS (SELECT 1 FROM product_barcodes x '
            'WHERE x.product_id = p.id AND x.barcode LIKE ?))');
        vars.addAll(List.filled(6, like));
      }
      final catId = query.categoryId;
      if (catId != null) {
        where.add('p.category_id IN (WITH RECURSIVE t(id) AS (SELECT ? UNION ALL '
            'SELECT c2.id FROM categories c2 JOIN t ON c2.parent_id = t.id) SELECT id FROM t)');
        vars.add(Variable<String>(catId));
      }
      final supId = query.supplierId;
      if (supId != null) {
        where.add('p.supplier_id = ?');
        vars.add(Variable<String>(supId));
      }
      if (warehouse != null) where.add('b.product_id IS NOT NULL');
      final minQ = query.minQty;
      if (minQ != null) {
        where.add('$phys >= ?');
        vars.add(Variable<int>(minQ));
      }
      final maxQ = query.maxQty;
      if (maxQ != null) {
        where.add('$phys <= ?');
        vars.add(Variable<int>(maxQ));
      }
      final addedAfter = query.addedAfter;
      if (addedAfter != null) {
        where.add('p.created_at >= ?');
        vars.add(Variable<DateTime>(addedAfter));
      }
    }

    final order = q == null ? '' : 'ORDER BY ${q.sort.sql}, p.id LIMIT ${q.limit}';
    final sql = '$_selectCols LEFT JOIN ($balSub) b ON b.product_id = p.id '
        'WHERE ${where.join(' AND ')} $order';

    return _db
        .customSelect(sql, variables: vars, readsFrom: {
          _db.products,
          _db.productBarcodes,
          _db.inventoryBalances,
          _db.categories,
          _db.suppliers,
          _db.units,
        })
        .watch()
        .map((rows) => rows.map(_mapItem).toList());
  }

  ProductListItem _mapItem(QueryRow r) => ProductListItem(
        id: r.read<String>('id'),
        name: r.read<String>('name'),
        sku: r.readNullable<String>('sku'),
        description: r.readNullable<String>('description'),
        notes: r.readNullable<String>('notes'),
        imagePath: r.readNullable<String>('image_path'),
        primaryBarcode: r.readNullable<String>('primary_barcode'),
        categoryName: r.readNullable<String>('category_name'),
        supplierName: r.readNullable<String>('supplier_name'),
        unitSymbol: r.read<String>('unit_symbol'),
        unitDecimals: r.read<int>('unit_decimals'),
        physical: r.read<int>('physical'),
        reserved: r.read<int>('reserved'),
        minStock: r.read<int>('min_stock'),
        maxStock: r.readNullable<int>('max_stock'),
        reorderQuantity: r.read<int>('reorder_quantity'),
        weightGrams: r.read<int>('weight_grams'),
        purchasePriceMinor: r.readNullable<int>('purchase_price_minor'),
        sellingPriceMinor: r.readNullable<int>('selling_price_minor'),
        isActive: r.read<int>('is_active') == 1,
      );

  Stream<List<ProductBarcode>> watchBarcodes(String productId) => (_db.select(_db.productBarcodes)
        ..where((b) => b.productId.equals(productId))
        ..orderBy([(b) => OrderingTerm.desc(b.isPrimary), (b) => OrderingTerm.asc(b.barcode)]))
      .watch();

  Stream<List<WarehouseBalance>> watchBalances(String productId) {
    final b = _db.inventoryBalances;
    final q = _db.select(b).join([
      innerJoin(_db.warehouses, _db.warehouses.id.equalsExp(b.warehouseId)),
    ])
      ..where(b.productId.equals(productId))
      ..orderBy([OrderingTerm.asc(_db.warehouses.name)]);
    return q.watch().map((rows) => [
          for (final r in rows)
            WarehouseBalance(r.readTable(_db.warehouses).id, r.readTable(_db.warehouses).name,
                r.readTable(b).physicalQuantity, r.readTable(b).reservedQuantity)
        ]);
  }

  /// Returns the product id owning [barcode], or null. Used by the scanner later.
  Future<String?> findIdByBarcode(String barcode) async {
    final row = await (_db.select(_db.productBarcodes)
          ..where((b) => b.barcode.equals(barcode.trim())))
        .getSingleOrNull();
    return row?.productId;
  }

  /// Name of the product that already owns [barcode] (other than [exceptProductId]).
  Future<String?> barcodeOwnerName(String barcode, {String? exceptProductId}) async {
    final j = _db.select(_db.productBarcodes).join([
      innerJoin(_db.products, _db.products.id.equalsExp(_db.productBarcodes.productId)),
    ])
      ..where(_db.productBarcodes.barcode.equals(barcode.trim()));
    final row = await j.getSingleOrNull();
    if (row == null) return null;
    final owner = row.readTable(_db.products);
    return owner.id == exceptProductId ? null : owner.name;
  }

  Future<ProductInput> loadForEdit(String id) async {
    final p = await (_db.select(_db.products)..where((t) => t.id.equals(id))).getSingle();
    final codes = await (_db.select(_db.productBarcodes)
          ..where((b) => b.productId.equals(id)))
        .get();
    return ProductInput(
      id: p.id,
      name: p.name,
      unitId: p.unitId,
      sku: p.sku,
      description: p.description,
      categoryId: p.categoryId,
      supplierId: p.supplierId,
      minStock: p.minStock,
      maxStock: p.maxStock,
      reorderQuantity: p.reorderQuantity,
      weightGrams: p.weightGrams,
      purchasePriceMinor: p.purchasePriceMinor,
      sellingPriceMinor: p.sellingPriceMinor,
      imagePath: p.imagePath,
      notes: p.notes,
      barcodes: [
        for (final c in codes) BarcodeInput(c.barcode, type: c.barcodeType, isPrimary: c.isPrimary)
      ],
    );
  }

  // ---------------------------------------------------------------- mutations

  Future<String> create(ProductInput i) => _db.transaction(() async {
        _validate(i);
        await _assertSkuFree(i.sku, null);
        final codes = _cleanBarcodes(i.barcodes);
        for (final c in codes) {
          await _assertBarcodeFree(c.value, null);
        }
        final id = _uuid.v4();
        final ts = _now().toUtc();
        await _db.into(_db.products).insert(ProductsCompanion.insert(
              id: Value(id),
              name: i.name.trim(),
              unitId: i.unitId,
              sku: Value(_blank(i.sku)),
              description: Value(_blank(i.description)),
              categoryId: Value(i.categoryId),
              supplierId: Value(i.supplierId),
              minStock: Value(i.minStock),
              maxStock: Value(i.maxStock),
              reorderQuantity: Value(i.reorderQuantity),
              weightGrams: Value(i.weightGrams),
              purchasePriceMinor: Value(i.purchasePriceMinor),
              sellingPriceMinor: Value(i.sellingPriceMinor),
              imagePath: Value(i.imagePath),
              notes: Value(_blank(i.notes)),
              createdAt: Value(ts),
              updatedAt: Value(ts),
            ));
        await _syncBarcodes(id, codes);
        if (i.openingQuantity > 0) {
          final wh = i.openingWarehouseId;
          if (wh == null) throw const ValidationException('Choose a warehouse for opening stock.');
          await _engine.post(
            operationId: 'opening:$id',
            productId: id,
            warehouseId: wh,
            type: MovementType.openingBalance,
            quantity: i.openingQuantity,
            notes: 'Opening stock at product creation',
          );
        }
        return id;
      });

  Future<void> update(ProductInput i) => _db.transaction(() async {
        final id = i.id;
        if (id == null) throw const ValidationException('Missing product id.');
        _validate(i);
        await _assertSkuFree(i.sku, id);
        final codes = _cleanBarcodes(i.barcodes);
        await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(ProductsCompanion(
          name: Value(i.name.trim()),
          unitId: Value(i.unitId),
          sku: Value(_blank(i.sku)),
          description: Value(_blank(i.description)),
          categoryId: Value(i.categoryId),
          supplierId: Value(i.supplierId),
          minStock: Value(i.minStock),
          maxStock: Value(i.maxStock),
          reorderQuantity: Value(i.reorderQuantity),
          weightGrams: Value(i.weightGrams),
          purchasePriceMinor: Value(i.purchasePriceMinor),
          sellingPriceMinor: Value(i.sellingPriceMinor),
          imagePath: Value(i.imagePath),
          notes: Value(_blank(i.notes)),
          updatedAt: Value(_now().toUtc()),
        ));
        await _syncBarcodes(id, codes);
      });

  /// Copies product data only: no SKU, no barcodes, no stock.
  Future<String> duplicate(String id) async {
    final src = await loadForEdit(id);
    return create(ProductInput(
      name: '${src.name} (copy)',
      unitId: src.unitId,
      description: src.description,
      categoryId: src.categoryId,
      supplierId: src.supplierId,
      minStock: src.minStock,
      maxStock: src.maxStock,
      reorderQuantity: src.reorderQuantity,
      purchasePriceMinor: src.purchasePriceMinor,
      sellingPriceMinor: src.sellingPriceMinor,
      imagePath: src.imagePath,
      notes: src.notes,
    ));
  }

  /// Archive instead of delete: history keeps referencing the product.
  Future<void> setArchived(String id, bool archived) => bulkArchive([id], archived);

  /// Delete a product when possible; otherwise archive it.
  Future<void> deleteProduct(String id) async {
    try {
      await _db.transaction(() async {
        await (_db.delete(_db.productBarcodes)..where((b) => b.productId.equals(id))).go();
        await (_db.delete(_db.inventoryBalances)..where((b) => b.productId.equals(id))).go();
        await (_db.delete(_db.products)..where((p) => p.id.equals(id))).go();
      });
    } catch (_) {
      await setArchived(id, true);
    }
  }

  Future<void> bulkArchive(List<String> ids, bool archived) =>
      (_db.update(_db.products)..where((p) => p.id.isIn(ids))).write(
          ProductsCompanion(isActive: Value(!archived), updatedAt: Value(_now().toUtc())));

  Future<void> bulkSetCategory(List<String> ids, String? categoryId) =>
      (_db.update(_db.products)..where((p) => p.id.isIn(ids))).write(
          ProductsCompanion(categoryId: Value(categoryId), updatedAt: Value(_now().toUtc())));

  Future<void> bulkSetMinStock(List<String> ids, int minScaled) {
    if (minScaled < 0) throw const ValidationException('Minimum stock cannot be negative.');
    return (_db.update(_db.products)..where((p) => p.id.isIn(ids))).write(
        ProductsCompanion(minStock: Value(minScaled), updatedAt: Value(_now().toUtc())));
  }

  Future<void> addBarcode(String productId, String value,
      {String? type, bool makePrimary = false}) async {
    final code = value.trim();
    if (code.isEmpty) throw const ValidationException('Barcode is empty.');
    await _db.transaction(() async {
      await _assertBarcodeFree(code, productId);
      final hasAny = await (_db.select(_db.productBarcodes)
                ..where((b) => b.productId.equals(productId))
                ..limit(1))
              .get();
      await _db.into(_db.productBarcodes).insert(ProductBarcodesCompanion.insert(
            productId: productId,
            barcode: code,
            barcodeType: Value(type ?? BarcodeUtil.inferType(code)),
            isPrimary: Value(hasAny.isEmpty),
          ));
      if (makePrimary) await setPrimaryBarcodeByValue(productId, code);
    });
  }

  Future<void> removeBarcode(String barcodeId) => _db.transaction(() async {
        final row = await (_db.select(_db.productBarcodes)..where((b) => b.id.equals(barcodeId)))
            .getSingleOrNull();
        if (row == null) return;
        await (_db.delete(_db.productBarcodes)..where((b) => b.id.equals(barcodeId))).go();
        if (row.isPrimary) {
          final next = await (_db.select(_db.productBarcodes)
                ..where((b) => b.productId.equals(row.productId))
                ..limit(1))
              .getSingleOrNull();
          if (next != null) await setPrimaryBarcodeByValue(row.productId, next.barcode);
        }
      });

  Future<void> setPrimaryBarcodeByValue(String productId, String barcode) async {
    await (_db.update(_db.productBarcodes)..where((b) => b.productId.equals(productId)))
        .write(const ProductBarcodesCompanion(isPrimary: Value(false)));
    await (_db.update(_db.productBarcodes)
          ..where((b) => b.productId.equals(productId) & b.barcode.equals(barcode)))
        .write(const ProductBarcodesCompanion(isPrimary: Value(true)));
  }

  /// Minimal supplier creation used by the product form; full CRUD comes later.
  Future<String> createSupplier(String name) async {
    if (name.trim().isEmpty) throw const ValidationException('Supplier name is required.');
    final row = await _db
        .into(_db.suppliers)
        .insertReturning(SuppliersCompanion.insert(name: name.trim()));
    return row.id;
  }

  // ----------------------------------------------------------------- internal

  String? _blank(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  void _validate(ProductInput i) {
    if (i.name.trim().isEmpty) throw const ValidationException('Product name is required.');
    if (i.minStock < 0 || i.reorderQuantity < 0 || i.openingQuantity < 0) {
      throw const ValidationException('Quantities cannot be negative.');
    }
    final maxStock = i.maxStock;
    if (maxStock != null && maxStock < i.minStock) {
      throw const ValidationException('Maximum stock cannot be below minimum stock.');
    }
    if ((i.purchasePriceMinor ?? 0) < 0 || (i.sellingPriceMinor ?? 0) < 0) {
      throw const ValidationException('Prices cannot be negative.');
    }
  }

  List<BarcodeInput> _cleanBarcodes(List<BarcodeInput> input) {
    final seen = <String>{};
    final out = <BarcodeInput>[];
    for (final b in input) {
      final v = b.value.trim();
      if (v.isEmpty) continue;
      if (!seen.add(v)) throw ValidationException('Barcode $v is listed twice.');
      out.add(BarcodeInput(v, type: b.type ?? BarcodeUtil.inferType(v), isPrimary: b.isPrimary));
    }
    return out;
  }

  Future<void> _assertSkuFree(String? sku, String? exceptId) async {
    final s = _blank(sku);
    if (s == null) return;
    final row = await (_db.select(_db.products)..where((p) => p.sku.equals(s))).getSingleOrNull();
    if (row != null && row.id != exceptId) throw DuplicateSkuException(s);
  }

  Future<void> _assertBarcodeFree(String barcode, String? exceptProductId) async {
    final owner = await barcodeOwnerName(barcode, exceptProductId: exceptProductId);
    if (owner != null) throw DuplicateBarcodeException(barcode, owner);
  }

  Future<void> _syncBarcodes(String productId, List<BarcodeInput> desired) async {
    final existing = await (_db.select(_db.productBarcodes)
          ..where((b) => b.productId.equals(productId)))
        .get();
    final wanted = desired.map((d) => d.value).toSet();
    for (final e in existing) {
      if (!wanted.contains(e.barcode)) {
        await (_db.delete(_db.productBarcodes)..where((b) => b.id.equals(e.id))).go();
      }
    }
    final have = existing.map((e) => e.barcode).toSet();
    for (final d in desired) {
      if (have.contains(d.value)) continue;
      await _assertBarcodeFree(d.value, productId);
      await _db.into(_db.productBarcodes).insert(ProductBarcodesCompanion.insert(
          productId: productId, barcode: d.value, barcodeType: Value(d.type)));
    }
    if (desired.isNotEmpty) {
      final primary = desired.firstWhere((d) => d.isPrimary, orElse: () => desired.first);
      await setPrimaryBarcodeByValue(productId, primary.value);
    }
  }
}

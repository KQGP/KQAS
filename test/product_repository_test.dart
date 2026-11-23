import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kqas/core/errors/app_exceptions.dart';
import 'package:kqas/database/app_database.dart';
import 'package:kqas/database/tables/common.dart';
import 'package:kqas/features/products/data/product_repository.dart';
import 'package:kqas/features/products/domain/product_models.dart';
import 'package:kqas/features/stock_movements/data/stock_engine.dart';

const k = kQtyScale;

void main() {
  late AppDatabase db;
  late ProductRepository repo;
  late String unitId, warehouseId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ProductRepository(db, StockEngine(db));
    unitId = (await db.select(db.units).get()).firstWhere((u) => u.symbol == 'pcs').id;
    warehouseId = (await db.select(db.warehouses).get()).first.id;
  });
  tearDown(() => db.close());

  Future<String> make(String name,
          {String? sku, List<String> codes = const [], int opening = 0, int min = 0, int? max}) =>
      repo.create(ProductInput(
        name: name,
        unitId: unitId,
        sku: sku,
        minStock: min * k,
        maxStock: max == null ? null : max * k,
        barcodes: [for (final c in codes) BarcodeInput(c)],
        openingQuantity: opening * k,
        openingWarehouseId: warehouseId,
      ));

  Future<List<ProductListItem>> list([ProductQuery q = const ProductQuery()]) =>
      repo.watchList(q).first;

  test('opening stock creates balance and an opening-balance ledger entry', () async {
    final id = await make('Carton A', opening: 20);
    final items = await list();
    expect(items.single.physical, 20 * k);
    final ledger = await db.select(db.stockMovements).get();
    expect(ledger.single.movementType, 'openingBalance');
    expect(ledger.single.productId, id);
  });

  test('duplicate SKU and duplicate barcode are rejected', () async {
    await make('A', sku: 'SKU-1', codes: ['111']);
    expect(() => make('B', sku: 'SKU-1'), throwsA(isA<DuplicateSkuException>()));
    expect(() => make('C', codes: ['111']), throwsA(isA<DuplicateBarcodeException>()));
    expect((await list()).length, 1); // failed creates rolled back
  });

  test('search matches name, sku and barcode', () async {
    await make('Blue Widget', sku: 'BW-1', codes: ['6291041500213']);
    await make('Red Gadget', sku: 'RG-1');
    expect((await list(const ProductQuery(search: 'widget'))).length, 1);
    expect((await list(const ProductQuery(search: 'RG-1'))).single.name, 'Red Gadget');
    expect((await list(const ProductQuery(search: '6291041'))).single.name, 'Blue Widget');
  });

  test('stock status filters: low, out, overstocked, in stock', () async {
    await make('Low', opening: 15, min: 20);
    await make('Out', opening: 0, min: 10);
    await make('Over', opening: 120, min: 10, max: 100);
    await make('Fine', opening: 50, min: 10, max: 100);
    Future<List<String>> names(StockFilter f) async =>
        (await list(ProductQuery(filter: f))).map((e) => e.name).toList()..sort();
    expect(await names(StockFilter.low), ['Low']);
    expect(await names(StockFilter.out), ['Out']);
    expect(await names(StockFilter.overstocked), ['Over']);
    expect(await names(StockFilter.inStock), ['Fine', 'Low', 'Over']);
  });

  test('sorting by highest stock and pagination limit', () async {
    await make('A', opening: 5);
    await make('B', opening: 50);
    await make('C', opening: 20);
    final sorted = await list(const ProductQuery(sort: ProductSort.stockDesc));
    expect(sorted.map((e) => e.name).toList(), ['B', 'C', 'A']);
    expect((await list(const ProductQuery(limit: 2))).length, 2);
  });

  test('archive hides from default list, keeps product, restore brings it back', () async {
    final id = await make('Old');
    await repo.setArchived(id, true);
    expect(await list(), isEmpty);
    expect((await list(const ProductQuery(filter: StockFilter.archived))).length, 1);
    await repo.setArchived(id, false);
    expect((await list()).length, 1);
  });

  test('duplicate copies data but not sku, barcodes or stock', () async {
    final id = await make('Source', sku: 'S-1', codes: ['999'], opening: 10);
    final copyId = await repo.duplicate(id);
    final copy = (await list()).firstWhere((e) => e.id == copyId);
    expect(copy.name, 'Source (copy)');
    expect(copy.sku, isNull);
    expect(copy.primaryBarcode, isNull);
    expect(copy.physical, 0);
  });

  test('barcode management: add, primary switch, remove', () async {
    final id = await make('A', codes: ['111']);
    await repo.addBarcode(id, '222', makePrimary: true);
    var codes = await repo.watchBarcodes(id).first;
    expect(codes.firstWhere((c) => c.isPrimary).barcode, '222');
    await repo.removeBarcode(codes.firstWhere((c) => c.barcode == '222').id);
    codes = await repo.watchBarcodes(id).first;
    expect(codes.single.barcode, '111');
    expect(codes.single.isPrimary, true); // primary re-assigned automatically
    expect(await repo.findIdByBarcode('111'), id);
  });

  test('bulk category, min stock and archive', () async {
    final a = await make('A');
    final b = await make('B');
    final cat = await db.into(db.categories).insertReturning(CategoriesCompanion.insert(name: 'Cartons'));
    await repo.bulkSetCategory([a, b], cat.id);
    await repo.bulkSetMinStock([a, b], 7 * k);
    final items = await list(ProductQuery(categoryId: cat.id));
    expect(items.length, 2);
    expect(items.every((e) => e.minStock == 7 * k && e.categoryName == 'Cartons'), true);
    await repo.bulkArchive([a], true);
    expect((await list()).length, 1);
  });
}

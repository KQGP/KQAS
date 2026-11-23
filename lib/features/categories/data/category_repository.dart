import 'package:drift/drift.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../database/app_database.dart';

class CategoryRow {
  const CategoryRow(this.id, this.name, this.parentId, this.color, this.depth,
      this.productCount, this.units);
  final String id, name;
  final String? parentId;
  final int? color;
  final int depth, productCount;

  /// Total physical units (scaled) across all warehouses.
  final int units;
}

class CategoryRepository {
  CategoryRepository(this._db);
  final AppDatabase _db;

  /// Flattened depth-first tree with per-category stock summary.
  Stream<List<CategoryRow>> watchTree() {
    return _db.customSelect('''
      SELECT c.id, c.name, c.parent_id, c.color,
        (SELECT COUNT(*) FROM products p WHERE p.category_id = c.id AND p.is_active = 1) AS n,
        (SELECT COALESCE(SUM(b.physical_quantity), 0) FROM inventory_balances b
           JOIN products p ON p.id = b.product_id WHERE p.category_id = c.id) AS units
      FROM categories c ORDER BY c.name COLLATE NOCASE
    ''', readsFrom: {_db.categories, _db.products, _db.inventoryBalances}).watch().map((rows) {
      final byParent = <String?, List<QueryRow>>{};
      for (final r in rows) {
        byParent.putIfAbsent(r.readNullable<String>('parent_id'), () => []).add(r);
      }
      final out = <CategoryRow>[];
      void walk(String? parent, int depth) {
        for (final r in byParent[parent] ?? const <QueryRow>[]) {
          final id = r.read<String>('id');
          out.add(CategoryRow(id, r.read<String>('name'), parent, r.readNullable<int>('color'),
              depth, r.read<int>('n'), r.read<int>('units')));
          walk(id, depth + 1);
        }
      }

      walk(null, 0);
      return out;
    });
  }

  Future<String> create(String name, {String? parentId, int? color}) async {
    if (name.trim().isEmpty) throw const ValidationException('Category name is required.');
    final row = await _db.into(_db.categories).insertReturning(CategoriesCompanion.insert(
        name: name.trim(), parentId: Value(parentId), color: Value(color)));
    return row.id;
  }

  Future<void> update(String id, String name, {String? parentId, int? color}) async {
    if (name.trim().isEmpty) throw const ValidationException('Category name is required.');
    // Prevent cycles: the new parent may not be the category itself or a descendant.
    var cursor = parentId;
    while (cursor != null) {
      final currentCursor = cursor;
      if (currentCursor == id) {
        throw const ValidationException('A category cannot be moved under itself.');
      }
      cursor = (await (_db.select(_db.categories)..where((c) => c.id.equals(currentCursor)))
              .getSingleOrNull())
          ?.parentId;
    }
    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(CategoriesCompanion(
        name: Value(name.trim()), parentId: Value(parentId), color: Value(color)));
  }

  Future<void> delete(String id) async {
    final kids = await (_db.select(_db.categories)..where((c) => c.parentId.equals(id))).get();
    if (kids.isNotEmpty) {
      throw const CategoryInUseException('Remove or move its subcategories first.');
    }
    final used = await (_db.select(_db.products)..where((p) => p.categoryId.equals(id))).get();
    if (used.isNotEmpty) {
      throw CategoryInUseException('${used.length} product(s) use this category. Reassign them first.');
    }
    await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
  }
}

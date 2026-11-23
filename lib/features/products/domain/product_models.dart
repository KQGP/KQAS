import '../../../database/tables/common.dart';

enum StockStatus { out, low, ok, over }

StockStatus stockStatusOf(int physical, int minStock, int? maxStock) {
  if (physical <= 0) return StockStatus.out;
  if (minStock > 0 && physical <= minStock) return StockStatus.low;
  if (maxStock != null && physical > maxStock) return StockStatus.over;
  return StockStatus.ok;
}

enum StockFilter {
  all('All'),
  inStock('In stock'),
  low('Low stock'),
  out('Out of stock'),
  overstocked('Overstocked'),
  archived('Archived');

  const StockFilter(this.label);
  final String label;
}

enum ProductSort {
  nameAsc('Name A–Z', 'p.name COLLATE NOCASE ASC'),
  nameDesc('Name Z–A', 'p.name COLLATE NOCASE DESC'),
  stockDesc('Highest stock', 'physical DESC'),
  stockAsc('Lowest stock', 'physical ASC'),
  newest('Recently added', 'p.created_at DESC'),
  oldest('Oldest added', 'p.created_at ASC'),
  updated('Recently updated', 'p.updated_at DESC'),
  valueDesc('Highest inventory value',
      '(physical * COALESCE(p.purchase_price_minor, 0)) DESC'),
  valueAsc('Lowest inventory value',
      '(physical * COALESCE(p.purchase_price_minor, 0)) ASC');

  const ProductSort(this.label, this.sql);
  final String label;
  final String sql;
}

const _unset = Object();

class ProductQuery {
  const ProductQuery({
    this.search = '',
    this.sort = ProductSort.nameAsc,
    this.filter = StockFilter.all,
    this.categoryId,
    this.supplierId,
    this.warehouseId,
    this.minQty,
    this.maxQty,
    this.addedAfter,
    this.limit = pageSize,
  });

  static const pageSize = 50;

  final String search;
  final ProductSort sort;
  final StockFilter filter;
  final String? categoryId, supplierId, warehouseId;
  final int? minQty, maxQty; // scaled quantities
  final DateTime? addedAfter;
  final int limit;

  bool get hasAdvancedFilters =>
      categoryId != null ||
      supplierId != null ||
      warehouseId != null ||
      minQty != null ||
      maxQty != null ||
      addedAfter != null;

  /// Changing anything except [limit] resets pagination to the first page.
  ProductQuery copyWith({
    String? search,
    ProductSort? sort,
    StockFilter? filter,
    Object? categoryId = _unset,
    Object? supplierId = _unset,
    Object? warehouseId = _unset,
    Object? minQty = _unset,
    Object? maxQty = _unset,
    Object? addedAfter = _unset,
    int? limit,
  }) =>
      ProductQuery(
        search: search ?? this.search,
        sort: sort ?? this.sort,
        filter: filter ?? this.filter,
        categoryId: identical(categoryId, _unset) ? this.categoryId : categoryId as String?,
        supplierId: identical(supplierId, _unset) ? this.supplierId : supplierId as String?,
        warehouseId: identical(warehouseId, _unset) ? this.warehouseId : warehouseId as String?,
        minQty: identical(minQty, _unset) ? this.minQty : minQty as int?,
        maxQty: identical(maxQty, _unset) ? this.maxQty : maxQty as int?,
        addedAfter: identical(addedAfter, _unset) ? this.addedAfter : addedAfter as DateTime?,
        limit: limit ?? pageSize,
      );
}

class ProductListItem {
  const ProductListItem({
    required this.id,
    required this.name,
    this.sku,
    this.description,
    this.notes,
    this.imagePath,
    this.primaryBarcode,
    this.categoryName,
    this.supplierName,
    required this.unitSymbol,
    required this.unitDecimals,
    required this.physical,
    required this.reserved,
    required this.minStock,
    this.maxStock,
    required this.reorderQuantity,
    this.weightGrams = 0,
    this.purchasePriceMinor,
    this.sellingPriceMinor,
    required this.isActive,
  });

  final String id, name, unitSymbol;
  final String? sku, description, notes, imagePath, primaryBarcode, categoryName, supplierName;
  final int unitDecimals, physical, reserved, minStock, reorderQuantity, weightGrams;
  final int? maxStock, purchasePriceMinor, sellingPriceMinor;
  final bool isActive;

  int get available => physical - reserved;
  StockStatus get status => stockStatusOf(physical, minStock, maxStock);
  int get valueMinor => (physical * (purchasePriceMinor ?? 0)) ~/ kQtyScale;
}

class BarcodeInput {
  const BarcodeInput(this.value, {this.type, this.isPrimary = false});
  final String value;
  final String? type;
  final bool isPrimary;
}

class ProductInput {
  const ProductInput({
    this.id,
    required this.name,
    required this.unitId,
    this.sku,
    this.description,
    this.categoryId,
    this.supplierId,
    this.minStock = 0,
    this.maxStock,
    this.reorderQuantity = 0,
    this.weightGrams = 0,
    this.purchasePriceMinor,
    this.sellingPriceMinor,
    this.imagePath,
    this.notes,
    this.barcodes = const [],
    this.openingQuantity = 0,
    this.openingWarehouseId,
  });

  final String? id;
  final String name, unitId;
  final String? sku, description, categoryId, supplierId, imagePath, notes, openingWarehouseId;
  final int minStock, reorderQuantity, openingQuantity, weightGrams;
  final int? maxStock, purchasePriceMinor, sellingPriceMinor;
  final List<BarcodeInput> barcodes;
}

class WarehouseBalance {
  const WarehouseBalance(this.warehouseId, this.warehouseName, this.physical, this.reserved);
  final String warehouseId, warehouseName;
  final int physical, reserved;
}

import 'package:drift/drift.dart';
import '../../../database/app_database.dart';

class DashboardStats {
  const DashboardStats({
    required this.total,
    required this.unitsScaled,
    required this.valueMinor,
    required this.low,
    required this.out,
    required this.pendingIncoming,
    required this.pendingOutgoing,
    required this.weightGrams,
  });
  final int total, unitsScaled, valueMinor, low, out, pendingIncoming, pendingOutgoing, weightGrams;
  int get sufficient => total - low - out;
}

class DashboardRepository {
  DashboardRepository(this._db);
  final AppDatabase _db;

  static const _pending = "('draft','pending','partiallyReceived','partiallyDispatched')";

  Stream<DashboardStats> watchStats() => _db.customSelect('''
      WITH pb AS (
        SELECT p.min_stock AS mn, p.purchase_price_minor AS pp, p.weight_grams AS wg,
          COALESCE((SELECT SUM(b.physical_quantity) FROM inventory_balances b
                    WHERE b.product_id = p.id), 0) AS phys
        FROM products p WHERE p.is_active = 1)
      SELECT
        (SELECT COUNT(*) FROM pb) AS total,
        (SELECT COALESCE(SUM(phys), 0) FROM pb) AS units,
        (SELECT COALESCE(SUM(CASE WHEN pp IS NOT NULL AND phys > 0 THEN phys * pp END), 0) / 1000
           FROM pb) AS val,
        (SELECT COUNT(*) FROM pb WHERE phys <= 0) AS out_c,
        (SELECT COUNT(*) FROM pb WHERE phys > 0 AND mn > 0 AND phys <= mn) AS low_c,
        (SELECT COUNT(*) FROM invoices WHERE invoice_type = 'incoming'
           AND status IN $_pending) AS inc_p,
        (SELECT COUNT(*) FROM invoices WHERE invoice_type = 'outgoing'
           AND status IN $_pending) AS out_p,
        (SELECT COALESCE(SUM(phys * wg), 0) / 1000 FROM pb) AS wgt
    ''', readsFrom: {_db.products, _db.inventoryBalances, _db.invoices}).watchSingle().map((r) =>
      DashboardStats(
        total: r.read<int>('total'),
        unitsScaled: r.read<int>('units'),
        valueMinor: r.read<int>('val'),
        low: r.read<int>('low_c'),
        out: r.read<int>('out_c'),
        pendingIncoming: r.read<int>('inc_p'),
        pendingOutgoing: r.read<int>('out_p'),
        weightGrams: r.read<int>('wgt'),
      ));

  Stream<List<Product>> watchRecentlyAdded() => (_db.select(_db.products)
        ..where((p) => p.isActive.equals(true))
        ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
        ..limit(5))
      .watch();

  Stream<List<Product>> watchRecentlyModified() => (_db.select(_db.products)
        ..where((p) => p.isActive.equals(true))
        ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)])
        ..limit(5))
      .watch();
}

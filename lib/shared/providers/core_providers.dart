import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../features/categories/data/category_repository.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/invoices/data/invoice_repository.dart';
import '../../features/notifications/data/notification_repository.dart';
import '../../features/products/data/product_repository.dart';
import '../../features/scanning/data/scan_session_repository.dart';
import '../../features/stock_movements/data/reservation_engine.dart';
import '../../features/stock_movements/data/transfer_service.dart';
import '../../features/stocktaking/data/stocktaking_repository.dart';
import '../../features/users/data/user_repository.dart';
import '../../features/products/domain/product_models.dart';
import '../../features/stock_movements/data/movement_repository.dart';
import '../../features/stock_movements/data/stock_engine.dart';
import '../data/settings_repository.dart';
import 'database_providers.dart';

final stockEngineProvider = Provider((ref) => StockEngine(ref.watch(databaseProvider)));
final productRepositoryProvider = Provider((ref) =>
    ProductRepository(ref.watch(databaseProvider), ref.watch(stockEngineProvider)));
final categoryRepositoryProvider =
    Provider((ref) => CategoryRepository(ref.watch(databaseProvider)));
final movementRepositoryProvider =
    Provider((ref) => MovementRepository(ref.watch(databaseProvider)));
final invoiceRepositoryProvider = Provider((ref) => InvoiceRepository(
    ref.watch(databaseProvider), ref.watch(stockEngineProvider)));
final notificationRepositoryProvider =
    Provider((ref) => NotificationRepository(ref.watch(databaseProvider)));
final alertServiceProvider = Provider((ref) => AlertService(
    ref.watch(databaseProvider), ref.watch(notificationRepositoryProvider)));
final scanSessionRepositoryProvider = Provider((ref) => ScanSessionRepository(
    ref.watch(databaseProvider), ref.watch(stockEngineProvider), ref.watch(invoiceRepositoryProvider)));
final reservationEngineProvider = Provider((ref) => ReservationEngine(ref.watch(databaseProvider)));
final stocktakingRepositoryProvider = Provider((ref) => StocktakingRepository(
    ref.watch(databaseProvider), ref.watch(stockEngineProvider)));
final transferServiceProvider = Provider((ref) => TransferService(
    ref.watch(databaseProvider), ref.watch(stockEngineProvider)));
final userRepositoryProvider = Provider((ref) => UserRepository(ref.watch(databaseProvider)));
final dashboardRepositoryProvider =
    Provider((ref) => DashboardRepository(ref.watch(databaseProvider)));
final settingsRepositoryProvider =
    Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));

// ---- reference data -------------------------------------------------------
final unitsProvider = StreamProvider<List<Unit>>(
    (ref) => ref.watch(databaseProvider).select(ref.watch(databaseProvider).units).watch());

final warehousesProvider = StreamProvider<List<Warehouse>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.warehouses)..where((w) => w.isActive.equals(true))).watch();
});

final suppliersProvider = StreamProvider<List<Supplier>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.suppliers).watch();
});

final categoryTreeProvider = StreamProvider<List<CategoryRow>>(
    (ref) => ref.watch(categoryRepositoryProvider).watchTree());

/// Placeholder identity until the Users module: the seeded administrator.
final currentUserProvider = FutureProvider<User>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.users)
        ..where((u) => u.isActive.equals(true))
        ..limit(1))
      .getSingle();
});

final allowNegativeStockProvider = StreamProvider<bool>((ref) => ref
    .watch(settingsRepositoryProvider)
    .watch(StockEngine.settingAllowNegative)
    .map((v) => v == 'true'));

// ---- products -------------------------------------------------------------
final productQueryProvider = StateProvider<ProductQuery>((_) => const ProductQuery());

final productListProvider = StreamProvider.autoDispose<List<ProductListItem>>((ref) =>
    ref.watch(productRepositoryProvider).watchList(ref.watch(productQueryProvider)));

final productItemProvider = StreamProvider.autoDispose.family<ProductListItem?, String>(
    (ref, id) => ref.watch(productRepositoryProvider).watchItem(id));

final productBarcodesProvider = StreamProvider.autoDispose.family<List<ProductBarcode>, String>(
    (ref, id) => ref.watch(productRepositoryProvider).watchBarcodes(id));

final productBalancesProvider = StreamProvider.autoDispose.family<List<WarehouseBalance>, String>(
    (ref, id) => ref.watch(productRepositoryProvider).watchBalances(id));

final movementsProvider =
    StreamProvider.autoDispose.family<List<MovementEntry>, MovementFilter>(
        (ref, f) => ref.watch(movementRepositoryProvider).watch(f));

// ---- dashboard ------------------------------------------------------------
final dashboardStatsProvider = StreamProvider.autoDispose<DashboardStats>(
    (ref) => ref.watch(dashboardRepositoryProvider).watchStats());
final recentlyAddedProvider = StreamProvider.autoDispose<List<Product>>(
    (ref) => ref.watch(dashboardRepositoryProvider).watchRecentlyAdded());
final recentlyModifiedProvider = StreamProvider.autoDispose<List<Product>>(
    (ref) => ref.watch(dashboardRepositoryProvider).watchRecentlyModified());
final recentMovementsProvider = StreamProvider.autoDispose<List<MovementEntry>>((ref) => ref
    .watch(movementRepositoryProvider)
    .watch(const MovementFilter(limit: 8)));

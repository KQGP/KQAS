import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/categories/presentation/categories_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/invoices/presentation/invoices_screen.dart';
import '../../features/more/presentation/more_screen.dart';
import '../../features/scanning/presentation/scanner_screen.dart';
import '../../features/products/presentation/product_detail_screen.dart';
import '../../features/products/presentation/product_form_screen.dart';
import '../../features/products/presentation/product_history_screen.dart';
import '../../features/products/presentation/product_list_screen.dart';
import '../widgets/adaptive_shell.dart';
import '../widgets/phase_pending_screen.dart';

abstract class Routes {
  static const dashboard = '/';
  static const inventory = '/inventory';
  static const invoices = '/invoices';
  static const scanner = '/scanner';
  static const more = '/more';
}

StatefulShellBranch _pending(String path, String title, String phase, IconData icon) =>
    StatefulShellBranch(routes: [
      GoRoute(
          path: path,
          builder: (_, __) => PhasePendingScreen(title: title, phase: phase, icon: icon)),
    ]);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.dashboard,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AdaptiveShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.dashboard, builder: (_, __) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.inventory,
              builder: (_, __) => const ProductListScreen(),
              routes: [
                GoRoute(path: 'new', builder: (_, __) => const ProductFormScreen()),
                GoRoute(path: 'categories', builder: (_, __) => const CategoriesScreen()),
                GoRoute(
                  path: ':id',
                  builder: (_, s) => ProductDetailScreen(productId: s.pathParameters['id'] ?? ''),
                  routes: [
                    GoRoute(
                        path: 'edit',
                        builder: (_, s) =>
                            ProductFormScreen(productId: s.pathParameters['id'])),
                    GoRoute(
                        path: 'history',
                        builder: (_, s) =>
                            ProductHistoryScreen(productId: s.pathParameters['id'] ?? '')),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.invoices, builder: (_, __) => const InvoicesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.scanner, builder: (_, __) => const ScannerScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.more, builder: (_, __) => const MoreScreen()),
          ]),
        ],
      ),
    ],
  );
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utilities/qty_money.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../shared/providers/core_providers.dart';
import '../../products/domain/product_models.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _openFiltered(WidgetRef ref, BuildContext context, StockFilter f) {
    ref.read(productQueryProvider.notifier).state = ProductQuery(filter: f);
    context.go('/inventory');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final added = ref.watch(recentlyAddedProvider).valueOrNull ?? const [];
    final modified = ref.watch(recentlyModifiedProvider).valueOrNull ?? const [];
    final moves = ref.watch(recentMovementsProvider).valueOrNull ?? const [];
    final fmt = DateFormat('MMM d, HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('KQAS')),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load dashboard: $e')),
        data: (s) => ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Stat(Icons.inventory_2, 'Products', '${s.total}', StatusColors.info,
                onTap: () => _openFiltered(ref, context, StockFilter.all)),
            _Stat(Icons.stacked_bar_chart, 'Total units', Qty.format(s.unitsScaled),
                StatusColors.info),
            _Stat(Icons.payments, 'Inventory value', Money.format(s.valueMinor),
                StatusColors.info),
            _Stat(Icons.scale, 'Total weight', '${(s.weightGrams / 1000).toStringAsFixed(2)} kg',
                StatusColors.info),
            _Stat(Icons.check_circle, 'Sufficient', '${s.sufficient}', StatusColors.success),
            _Stat(Icons.warning_amber_rounded, 'Low stock', '${s.low}', StatusColors.warning,
                onTap: () => _openFiltered(ref, context, StockFilter.low)),
            _Stat(Icons.remove_circle, 'Out of stock', '${s.out}', StatusColors.danger,
                onTap: () => _openFiltered(ref, context, StockFilter.out)),
            _Stat(Icons.move_to_inbox, 'Pending incoming', '${s.pendingIncoming}',
                StatusColors.warning),
            _Stat(Icons.outbox, 'Pending outgoing', '${s.pendingOutgoing}',
                StatusColors.warning),
          ]),
          const SizedBox(height: 20),
          _Section('Recent stock movements', [
            for (final m in moves)
              ListTile(
                dense: true,
                leading: Icon(m.movement.quantityIn > 0 ? Icons.add_circle : Icons.remove_circle,
                    color: m.movement.quantityIn > 0 ? StatusColors.success : StatusColors.danger),
                title: Text(m.productName),
                subtitle: Text('${m.type.label} · ${fmt.format(m.movement.createdAt.toLocal())}'),
                trailing: Text(
                    '${m.movement.quantityIn > 0 ? '+' : '-'}'
                    '${Qty.format(m.movement.quantityIn > 0 ? m.movement.quantityIn : m.movement.quantityOut, decimals: m.unitDecimals)} ${m.unitSymbol}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => context.go('/inventory/${m.movement.productId}'),
              ),
          ]),
          _Section('Recently added', [
            for (final p in added)
              ListTile(
                  dense: true,
                  title: Text(p.name),
                  subtitle: Text(fmt.format(p.createdAt.toLocal())),
                  onTap: () => context.go('/inventory/${p.id}')),
          ]),
          _Section('Recently modified', [
            for (final p in modified)
              ListTile(
                  dense: true,
                  title: Text(p.name),
                  subtitle: Text(fmt.format(p.updatedAt.toLocal())),
                  onTap: () => context.go('/inventory/${p.id}')),
          ]),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: children.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('Nothing yet.'))
              : Column(children: children),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.label, this.value, this.color, {this.onTap});
  final IconData icon;
  final String label, value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      width: 168,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color),
              const SizedBox(height: 10),
              Text(value, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(label, style: t.textTheme.bodyMedium),
            ]),
          ),
        ),
      ),
    );
  }
}

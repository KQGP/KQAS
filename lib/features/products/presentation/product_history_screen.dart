import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utilities/qty_money.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../shared/providers/core_providers.dart';
import '../../stock_movements/data/movement_repository.dart';
import '../../stock_movements/domain/movement_type.dart';

class ProductHistoryScreen extends ConsumerStatefulWidget {
  const ProductHistoryScreen({super.key, required this.productId});
  final String productId;
  @override
  ConsumerState<ProductHistoryScreen> createState() => _State();
}

class _State extends ConsumerState<ProductHistoryScreen> {
  late MovementFilter _filter = MovementFilter(productId: widget.productId);
  final _fmt = DateFormat('yyyy-MM-dd HH:mm');

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
        context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (r == null) return;
    setState(() => _filter = _filter.copyWith(
        from: r.start, to: r.end.add(const Duration(hours: 23, minutes: 59, seconds: 59))));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(movementsProvider(_filter));
    return Scaffold(
      appBar: AppBar(title: const Text('Stock history')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<MovementType?>(
                value: _filter.type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Movement type'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All types')),
                  for (final t in MovementType.values) DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() => _filter = _filter.copyWith(type: v)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Date range',
              icon: Icon(_filter.from == null ? Icons.date_range : Icons.event_available),
              onPressed: _pickRange,
            ),
            if (_filter.from != null)
              IconButton(
                  tooltip: 'Clear dates',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _filter = _filter.copyWith(from: null, to: null))),
          ]),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load history: $e')),
            data: (rows) => rows.isEmpty
                ? const EmptyState(icon: Icons.history, title: 'No movements', message: 'Stock changes will appear here.')
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = rows[i];
                      final m = e.movement;
                      final inbound = m.quantityIn > 0;
                      final qty = inbound ? m.quantityIn : m.quantityOut;
                      String f(int v) => Qty.format(v, decimals: e.unitDecimals);
                      final reason = m.reason;
                      final notes = m.notes;
                      return ListTile(
                        leading: Icon(inbound ? Icons.arrow_circle_down : Icons.arrow_circle_up,
                            color: inbound ? StatusColors.success : StatusColors.danger),
                        title: Text(e.type.label),
                        subtitle: Text([
                          '${_fmt.format(m.createdAt.toLocal())} · ${e.warehouseName}',
                          '${f(m.previousQuantity)} → ${f(m.newQuantity)}',
                          if (reason != null) 'Reason: $reason',
                          if (notes != null) notes,
                        ].join('\n')),
                        isThreeLine: true,
                        trailing: Text('${inbound ? '+' : '-'}${f(qty)} ${e.unitSymbol}',
                            style: TextStyle(fontWeight: FontWeight.w700, color: inbound ? StatusColors.success : StatusColors.danger)),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

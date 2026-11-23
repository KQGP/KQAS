import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utilities/qty_money.dart';
import '../../../shared/providers/core_providers.dart';
import '../../stock_movements/domain/movement_type.dart';
import '../domain/product_models.dart';

enum _Action {
  increase('Increase stock', MovementType.manualIncrease, StockDirection.inbound),
  decrease('Decrease stock', MovementType.manualDecrease, StockDirection.outbound),
  damaged('Damaged goods', MovementType.damaged, StockDirection.outbound),
  expired('Expired goods', MovementType.expired, StockDirection.outbound),
  lost('Lost goods', MovementType.lost, StockDirection.outbound),
  count('Correct to counted quantity', MovementType.correction, null);

  const _Action(this.label, this.type, this.direction);
  final String label;
  final MovementType type;
  final StockDirection? direction;
}

/// Manual adjustments. All stock changes go through StockEngine.
class AdjustStockDialog extends ConsumerStatefulWidget {
  const AdjustStockDialog({super.key, required this.product});
  final ProductListItem product;
  @override
  ConsumerState<AdjustStockDialog> createState() => _State();
}

class _State extends ConsumerState<AdjustStockDialog> {
  // One id per dialog instance: a double tap can never post twice.
  final _operationId = 'adj:${const Uuid().v4()}';
  _Action _action = _Action.increase;
  String? _warehouseId;
  final _qty = TextEditingController();
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  String? _error;
  bool _canOverride = false, _busy = false;

  Future<void> _submit({bool override = false}) async {
    final p = widget.product;
    final entered = Qty.parse(_qty.text, decimals: p.unitDecimals);
    if (entered == null) {
      return setState(() => _error = 'Enter a valid quantity (${p.unitDecimals == 0 ? 'whole number' : 'up to ${p.unitDecimals} decimals'}).');
    }
    if (_warehouseId == null) return setState(() => _error = 'Choose a warehouse.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var quantity = entered;
      StockDirection? dir = _action.direction;
      if (_action == _Action.count) {
        final balances = ref.read(productBalancesProvider(p.id)).valueOrNull ?? const [];
        final current = balances.where((b) => b.warehouseId == _warehouseId).map((b) => b.physical).firstOrNull ?? 0;
        if (entered == current) throw const ValidationException('Counted quantity equals the system quantity: nothing to correct.');
        dir = entered > current ? StockDirection.inbound : StockDirection.outbound;
        quantity = (entered - current).abs();
      } else if (entered <= 0) {
        throw const InvalidQuantityException();
      }
      final user = await ref.read(currentUserProvider.future);
      await ref.read(stockEngineProvider).post(
            operationId: _operationId,
            productId: p.id,
            warehouseId: _warehouseId!,
            type: _action.type,
            direction: dir,
            quantity: quantity,
            userId: user.id,
            reason: _reason.text,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            allowNegativeOverride: override,
          );
      if (mounted) Navigator.pop(context, true);
    } on InsufficientStockException catch (e) {
      final allowed = ref.read(allowNegativeStockProvider).valueOrNull ?? false;
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
          _canOverride = allowed;
        });
      }
    } on AppException catch (e) {
      if (mounted) setState(() {
            _busy = false;
            _error = e.message;
          });
    } catch (e) {
      if (mounted) setState(() {
            _busy = false;
            _error = 'Unexpected error: $e';
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final whs = ref.watch(warehousesProvider).valueOrNull ?? const [];
    _warehouseId ??= whs.isEmpty ? null : whs.first.id;
    final balances = ref.watch(productBalancesProvider(widget.product.id)).valueOrNull ?? const [];
    final cur = balances.where((b) => b.warehouseId == _warehouseId).map((b) => b.physical).firstOrNull ?? 0;
    return AlertDialog(
      title: const Text('Adjust stock'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<_Action>(
            value: _action,
            decoration: const InputDecoration(labelText: 'Action'),
            items: [for (final a in _Action.values) DropdownMenuItem(value: a, child: Text(a.label))],
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _action = v;
                  _canOverride = false;
                  _error = null;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _warehouseId,
            decoration: const InputDecoration(labelText: 'Warehouse'),
            items: [for (final w in whs) DropdownMenuItem(value: w.id, child: Text(w.name))],
            onChanged: (v) => setState(() => _warehouseId = v),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Current: ${Qty.format(cur, decimals: widget.product.unitDecimals)} ${widget.product.unitSymbol}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: _action == _Action.count ? 'Counted quantity' : 'Quantity'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Reason *')),
          const SizedBox(height: 12),
          TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error, color: StatusColors.danger, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: StatusColors.danger))),
              ]),
            ),
          if (_canOverride)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.admin_panel_settings),
                label: const Text('Authorised override (allow negative)'),
                onPressed: _busy ? null : () => _submit(override: true),
              ),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Post')),
      ],
    );
  }
}

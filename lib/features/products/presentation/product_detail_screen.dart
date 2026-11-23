import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utilities/qty_money.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../shared/providers/core_providers.dart';
import '../../scanning/presentation/barcode_scan_page.dart';
import '../domain/product_models.dart';
import 'adjust_stock_dialog.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(productItemProvider(productId));
    final repo = ref.read(productRepositoryProvider);
    final p = async.valueOrNull;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading ? const Center(child: CircularProgressIndicator()) : const EmptyState(icon: Icons.search_off, title: 'Product not found'),
      );
    }
    String q(int v) => '${Qty.format(v, decimals: p.unitDecimals)} ${p.unitSymbol}';
    final balances = ref.watch(productBalancesProvider(productId)).valueOrNull ?? const [];
    final codes = ref.watch(productBarcodesProvider(productId)).valueOrNull ?? const [];
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(p.name, overflow: TextOverflow.ellipsis), actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            try {
              if (v == 'edit') context.push('/inventory/$productId/edit');
              if (v == 'dup') {
                final id = await repo.duplicate(productId);
                if (context.mounted) context.push('/inventory/$id/edit');
              }
              if (v == 'arch') {
                final archiving = p.isActive;
                if (await confirm(context, archiving ? 'Archive product?' : 'Restore product?',
                    archiving ? 'It will be hidden from lists but stay in history and invoices.' : 'It will appear in inventory again.',
                    action: archiving ? 'Archive' : 'Restore')) {
                  await repo.setArchived(productId, archiving);
                }
              }
            } catch (e) {
              if (context.mounted) showError(context, e);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'dup', child: Text('Duplicate')),
            PopupMenuItem(value: 'arch', child: Text(p.isActive ? 'Archive' : 'Restore')),
          ],
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              ProductAvatar(name: p.name, imagePath: p.imagePath, size: 84),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: t.textTheme.titleLarge),
                  if (p.sku != null) Text('SKU ${p.sku}'),
                  if (p.categoryName != null) Text('Category: ${p.categoryName}'),
                  if (p.supplierName != null) Text('Supplier: ${p.supplierName}'),
                  const SizedBox(height: 6),
                  if (p.isActive) StockStatusChip(p.status) else const Chip(avatar: Icon(Icons.archive, size: 16), label: Text('Archived')),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Stock', style: t.textTheme.titleMedium),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final maxStock = p.maxStock;
                  final purchasePrice = p.purchasePriceMinor;
                  final sellingPrice = p.sellingPriceMinor;
                  return Wrap(spacing: 24, runSpacing: 8, children: [
                    _Fact('Physical', q(p.physical)),
                    _Fact('Reserved', q(p.reserved)),
                    _Fact('Available', q(p.available)),
                    _Fact('Minimum', q(p.minStock)),
                    _Fact('Maximum', maxStock == null ? '—' : q(maxStock)),
                    _Fact('Reorder qty', q(p.reorderQuantity)),
                    if (purchasePrice != null) _Fact('Purchase price', Money.format(purchasePrice)),
                    if (sellingPrice != null) _Fact('Selling price', Money.format(sellingPrice)),
                    if (purchasePrice != null) _Fact('Stock value', Money.format(p.valueMinor)),
                  ]);
                },
              ),
              if (balances.isNotEmpty) ...[
                const Divider(height: 24),
                for (final b in balances)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warehouse_outlined),
                    title: Text(b.warehouseName),
                    trailing: Text('${q(b.physical)}  (reserved ${q(b.reserved)})'),
                  ),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Barcodes', style: t.textTheme.titleMedium)),
                TextButton.icon(onPressed: () => _addBarcode(context, ref), icon: const Icon(Icons.add), label: const Text('Add')),
              ]),
              if (codes.isEmpty) const Text('No barcodes assigned.'),
              for (final c in codes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: IconButton(
                    tooltip: c.isPrimary ? 'Primary barcode' : 'Make primary',
                    icon: Icon(c.isPrimary ? Icons.star : Icons.star_border),
                    onPressed: c.isPrimary ? null : () => repo.setPrimaryBarcodeByValue(productId, c.barcode),
                  ),
                  title: Text(c.barcode),
                  subtitle: Text(c.barcodeType ?? ''),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(context, 'Remove barcode?', c.barcode, action: 'Remove')) {
                        await repo.removeBarcode(c.id);
                      }
                    },
                  ),
                ),
            ]),
          ),
        ),
        if (p.description != null || p.notes != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Builder(
                builder: (context) {
                  final desc = p.description;
                  final notes = p.notes;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (desc != null) ...[Text('Description', style: t.textTheme.titleMedium), Text(desc)],
                    if (notes != null) ...[const SizedBox(height: 8), Text('Notes', style: t.textTheme.titleMedium), Text(notes)],
                  ]);
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(context: context, builder: (_) => AdjustStockDialog(product: p));
                if (ok == true && context.mounted) showInfo(context, 'Stock adjustment recorded.');
              },
              icon: const Icon(Icons.tune),
              label: const Text('Adjust stock'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
              onPressed: () => context.push('/inventory/$productId/history'),
              icon: const Icon(Icons.history),
              label: const Text('History'),
            ),
          ),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }

  Future<void> _addBarcode(BuildContext context, WidgetRef ref) async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add barcode'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Type, paste or scan a barcode',
            suffixIcon: IconButton(
              tooltip: 'Scan with camera',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final code = await scanBarcode(context);
                if (code != null) ctl.text = code;
              },
            ),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    try {
      await ref.read(productRepositoryProvider).addBarcode(productId, v);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]);
}

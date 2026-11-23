import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utilities/pdf_text_extractor.dart';
import '../../../core/utilities/qty_money.dart';
import '../../../database/tables/common.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../shared/providers/core_providers.dart';
import '../data/invoice_repository.dart';
import '../domain/invoice_models.dart';

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});
  @override
  ConsumerState<InvoicesScreen> createState() => _State();
}

class _State extends ConsumerState<InvoicesScreen> {
  Future<void> _uploadPdf() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (res == null || res.isEmpty || res.first.path == null) return;
    final path = res.first.path!;
    final text = await PdfTextExtractor.extract(path);
    final products = ref.read(productListProvider).valueOrNull ?? const [];
    final items = <InvoiceItemInput>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (t.isEmpty) continue;
      dynamic matched;
      for (final p in products) {
        if (t.toLowerCase().contains(p.name.toLowerCase()) ||
            (p.sku != null && t.toLowerCase().contains(p.sku!.toLowerCase())) ||
            (p.primaryBarcode != null && t.contains(p.primaryBarcode!))) {
          matched = p;
          break;
        }
      }
      if (matched == null) continue;
      final m = RegExp(r'(\d+)\s*$').firstMatch(t) ?? RegExp(r'(\d+)').allMatches(t).lastOrNull;
      int qty = 1;
      if (m != null) qty = int.tryParse(m.group(1)!) ?? 1;
      items.add(InvoiceItemInput(productId: matched.id, expectedQuantity: qty * kQtyScale));
    }
    if (items.isEmpty) {
      if (mounted) showError(context, 'No matching products found in PDF.');
      return;
    }
    final numberCtl = TextEditingController(text: res.first.name.replaceAll('.pdf', ''));
    final type = await showDialog<InvoiceType>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Invoice type'),
        content: TextField(controller: numberCtl, decoration: const InputDecoration(labelText: 'Invoice number')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, InvoiceType.incoming), child: const Text('Incoming')),
          FilledButton(onPressed: () => Navigator.pop(context, InvoiceType.outgoing), child: const Text('Outgoing')),
        ],
      ),
    );
    if (type == null) return;
    final repo = ref.read(invoiceRepositoryProvider);
    final id = await repo.create(InvoiceInput(
      invoiceNumber: numberCtl.text.trim().isEmpty ? 'PDF-${DateTime.now().millisecondsSinceEpoch}' : numberCtl.text.trim(),
      type: type,
      items: items,
      sourcePdfPath: path,
    ));
    await repo.submit(id);
    final whs = ref.read(warehousesProvider).valueOrNull ?? const [];
    if (whs.isNotEmpty) {
      if (type == InvoiceType.outgoing) {
        final invItems = await repo.watchItems(id).first;
        bool ok = true;
        for (final it in invItems) {
          if (it.productId == null) continue;
          final p = products.firstWhere((x) => x.id == it.productId, orElse: () => products.first);
          if (p.available < it.expectedQuantity) {
            ok = false;
            if (mounted) showError(context, 'Insufficient stock for ${p.name}.');
          }
        }
        if (ok) await repo.dispatchAll(id, warehouseId: whs.first.id);
      } else {
        await repo.receiveAll(id, warehouseId: whs.first.id);
      }
    }
    if (mounted) showInfo(context, 'PDF invoice processed: ${items.length} item(s).');
  }

  Future<void> _createInvoice() async {
    final numberCtl = TextEditingController();
    InvoiceType type = InvoiceType.outgoing;
    String? pdfPath;
    final selectedItems = <InvoiceItemInput>[];
    final productCtl = ValueNotifier<String?>(null);
    final qtyCtl = TextEditingController(text: '1');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final products = ref.read(productListProvider).valueOrNull ?? const [];
          final whs = ref.read(warehousesProvider).valueOrNull ?? const [];
          return AlertDialog(
            title: const Text('New invoice'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: numberCtl, decoration: const InputDecoration(labelText: 'Invoice number')),
                const SizedBox(height: 8),
                DropdownButtonFormField<InvoiceType>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: InvoiceType.incoming, child: Text('Incoming')),
                    DropdownMenuItem(value: InvoiceType.outgoing, child: Text('Outgoing')),
                  ],
                  onChanged: (v) {
                    if (v != null) set(() => type = v);
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file),
                  label: Text(pdfPath == null ? 'Attach PDF (optional)' : 'PDF attached'),
                  onPressed: () async {
                    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
                    if (res != null && res.isNotEmpty && res.first.path != null) {
                      set(() => pdfPath = res.first.path);
                    }
                  },
                ),
                const Divider(),
                Text('Items', style: Theme.of(ctx).textTheme.titleSmall),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: productCtl.value,
                      decoration: const InputDecoration(labelText: 'Product'),
                      items: [for (final p in products) DropdownMenuItem(value: p.id, child: Text(p.name))],
                      onChanged: (v) => set(() => productCtl.value = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(controller: qtyCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty')),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      final pid = productCtl.value;
                      if (pid == null) return;
                      final q = int.tryParse(qtyCtl.text) ?? 1;
                      selectedItems.add(InvoiceItemInput(productId: pid, expectedQuantity: q * kQtyScale));
                      set(() {});
                    },
                  ),
                ]),
                for (final it in selectedItems)
                  ListTile(
                    dense: true,
                    title: Text(products.isEmpty ? 'Unknown' : products.firstWhere((p) => p.id == it.productId, orElse: () => products.first).name),
                    trailing: Text('${it.expectedQuantity ~/ kQtyScale}'),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  if (numberCtl.text.trim().isEmpty) return;
                  if (selectedItems.isEmpty) return;
                  final repo = ref.read(invoiceRepositoryProvider);
                  final id = await repo.create(InvoiceInput(
                    invoiceNumber: numberCtl.text.trim(),
                    type: type,
                    items: List.of(selectedItems),
                    sourcePdfPath: pdfPath,
                  ));
                  await repo.submit(id);
                  // stock handling
                  final whs = ref.read(warehousesProvider).valueOrNull ?? const [];
                  if (whs.isNotEmpty) {
                    if (type == InvoiceType.outgoing) {
                      // check stock
                      final invItems = await repo.watchItems(id).first;
                      bool ok = true;
                      for (final it in invItems) {
                        if (it.productId == null) continue;
                        if (products.isEmpty) return;
                      final p = products.firstWhere((x) => x.id == it.productId, orElse: () => products.first);
                        if (p.available < it.expectedQuantity) {
                          ok = false;
                          if (mounted) showError(context, 'Insufficient stock for ${p.name}.');
                        }
                      }
                      if (ok) await repo.dispatchAll(id, warehouseId: whs.first.id);
                    } else {
                      await repo.receiveAll(id, warehouseId: whs.first.id);
                    }
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) showInfo(context, 'Invoice created.');
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_invoicesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          IconButton(tooltip: 'New invoice', icon: const Icon(Icons.add), onPressed: _createInvoice),
          IconButton(tooltip: 'Upload PDF', icon: const Icon(Icons.upload_file), onPressed: _uploadPdf),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load invoices: $e')),
        data: (rows) => rows.isEmpty
            ? const EmptyState(icon: Icons.receipt_long, title: 'No invoices yet')
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final inv = rows[i];
                  return ListTile(
                    title: Text(inv.invoiceNumber),
                    subtitle: Text('${inv.invoiceType} - ${inv.status}'),
                    trailing: Text('${inv.totalMinor}'),
                  );
                },
              ),
      ),
    );
  }
}

final _invoicesProvider = StreamProvider((ref) =>
    ref.watch(invoiceRepositoryProvider).watchAll());
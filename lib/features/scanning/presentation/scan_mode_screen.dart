import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/utilities/qty_money.dart';
import '../../../database/tables/common.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../shared/providers/core_providers.dart';
import '../../invoices/data/invoice_repository.dart';
import '../../stock_movements/data/stock_engine.dart';
import '../../stock_movements/domain/movement_type.dart';

class ScanModeScreen extends ConsumerStatefulWidget {
  const ScanModeScreen({super.key, this.initialLoadMode = true});
  final bool initialLoadMode;
  @override
  ConsumerState<ScanModeScreen> createState() => _State();
}

class _State extends ConsumerState<ScanModeScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _loadMode = true;

  @override
  void initState() {
    super.initState();
    _loadMode = widget.initialLoadMode;
  }
  String? _warehouseId;
  final Set<String> _selectedInvoices = {};
  final Map<String, int> _expected = {};
  final Map<String, int> _scanned = {};
  String? _lastCode;
  DateTime? _lastTime;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleInvoice(String id, bool selected) async {
    setState(() {
      if (selected) _selectedInvoices.add(id); else _selectedInvoices.remove(id);
    });
    await _rebuildExpected();
  }

  Future<void> _rebuildExpected() async {
    _expected.clear();
    for (final id in _selectedInvoices) {
      final items = await ref.read(invoiceRepositoryProvider).watchItems(id).first;
      for (final it in items) {
        final pid = it.productId;
        if (pid == null) continue;
        _expected[pid] = (_expected[pid] ?? 0) + (it.expectedQuantity - (it.dispatchedQuantity + it.receivedQuantity).clamp(0, it.expectedQuantity));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    for (final b in capture.barcodes) {
      final code = b.rawValue?.trim();
      if (code == null || code.isEmpty) continue;
      final now = DateTime.now();
      final lastTime = _lastTime;
      if (_lastCode == code && lastTime != null && now.difference(lastTime) < const Duration(seconds: 2)) return;
      _lastCode = code;
      _lastTime = now;

      final productId = await ref.read(productRepositoryProvider).findIdByBarcode(code);
      if (productId == null) {
        await SystemSound.play(SystemSoundType.alert);
        if (mounted) showInfo(context, 'Unknown barcode: $code');
        return;
      }
      final productName = (await ref.read(productRepositoryProvider).watchItem(productId).first)?.name ?? productId;

      if (_selectedInvoices.isNotEmpty) {
        final remaining = (_expected[productId] ?? 0) - (_scanned[productId] ?? 0);
        if (remaining <= 0) {
          await SystemSound.play(SystemSoundType.alert);
          if (mounted) showInfo(context, 'Over quantity or not in invoice: $productName');
          return;
        }
      }
      setState(() {
        _scanned[productId] = (_scanned[productId] ?? 0) + 1;
      });
      await SystemSound.play(SystemSoundType.click);
      if (mounted) showInfo(context, 'Scanned: $productName (${_scanned[productId]})');
    }
  }

  Future<void> _done() async {
    final whId = _warehouseId;
    if (whId == null) return showError(context, 'Choose a warehouse.');
    final ok = await confirm(context, 'Confirm scan?', 'Post ${_scanned.length} scanned product(s) to inventory?');
    if (!ok) return;
    final engine = ref.read(stockEngineProvider);
    final user = await ref.read(currentUserProvider.future);
    for (final entry in _scanned.entries) {
      final qty = entry.value * kQtyScale;
      if (qty <= 0) continue;
      await engine.post(
        operationId: 'scanmode:${DateTime.now().millisecondsSinceEpoch}:${entry.key}',
        productId: entry.key,
        warehouseId: whId,
        type: _loadMode ? MovementType.manualIncrease : MovementType.manualDecrease,
        direction: _loadMode ? StockDirection.inbound : StockDirection.outbound,
        quantity: qty,
        userId: user.id,
        reason: _loadMode ? 'Loaded to inventory' : 'Unloaded from inventory',
      );
    }
    await ref.read(notificationRepositoryProvider).create(
      type: 'scan_complete',
      title: 'Scan session complete',
      message: '${_scanned.length} product(s) processed.',
    );
    if (mounted) {
      showInfo(context, 'Done. ${_scanned.length} product(s) processed.');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final whs = ref.watch(warehousesProvider).valueOrNull ?? const [];
    _warehouseId ??= whs.isEmpty ? null : whs.first.id;
    final invoices = ref.watch(invoiceRepositoryProvider).watchAll(status: 'pending');

    return Scaffold(
      appBar: AppBar(title: const Text('Scan mode'), actions: [
        IconButton(
          tooltip: 'Flashlight',
          icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          onPressed: () async {
            await _controller.toggleTorch();
            if (mounted) setState(() => _torchOn = !_torchOn);
          },
        ),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Load'), icon: Icon(Icons.add)),
                  ButtonSegment(value: false, label: Text('Unload'), icon: Icon(Icons.remove)),
                ],
                selected: {_loadMode},
                onSelectionChanged: (s) => setState(() => _loadMode = s.first),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonFormField<String>(
            value: _warehouseId,
            decoration: const InputDecoration(labelText: 'Warehouse'),
            items: [for (final w in whs) DropdownMenuItem(value: w.id, child: Text(w.name))],
            onChanged: (v) => setState(() => _warehouseId = v),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: StreamBuilder(
            stream: invoices,
            builder: (_, snap) {
              final rows = snap.data ?? const [];
              return ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final inv in rows)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(inv.invoiceNumber),
                        selected: _selectedInvoices.contains(inv.id),
                        onSelected: (s) => _toggleInvoice(inv.id, s),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: MobileScanner(controller: _controller, onDetect: _onDetect),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Scanned: ${_scanned.length} product(s)', style: Theme.of(context).textTheme.titleSmall),
            for (final e in _scanned.entries)
              Text('${e.key}: ${e.value}'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: FilledButton(onPressed: _done, child: const Text('Done'))),
            ]),
          ]),
        ),
      ]),
    );
  }
}

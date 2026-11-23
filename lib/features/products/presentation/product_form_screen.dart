import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utilities/qty_money.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../shared/providers/core_providers.dart';
import '../../scanning/presentation/barcode_scan_page.dart';
import '../domain/product_models.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});
  final String? productId;
  @override
  ConsumerState<ProductFormScreen> createState() => _FormState();
}

class _FormState extends ConsumerState<ProductFormScreen> {
  final _key = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _detail = TextEditingController();
  final _weight = TextEditingController(text: '0');
  final _qty = TextEditingController(text: '0');
  final _comment = TextEditingController();
  final _barcodeCtl = TextEditingController();

  String? _unitId;
  final List<BarcodeInput> _barcodes = [];
  bool _loading = false, _saving = false;
  bool get _editing => widget.productId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.productId;
    if (id == null) return;
    final i = await ref.read(productRepositoryProvider).loadForEdit(id);
    if (!mounted) return;
    final units = ref.read(unitsProvider).valueOrNull ?? const [];
    setState(() {
      _number.text = i.sku ?? '';
      _detail.text = i.name;
      _weight.text = i.weightGrams.toString();
      _comment.text = i.notes ?? '';
      // show current total stock
      try {
        final bals = await ref.read(productRepositoryProvider).watchBalances(widget.productId!).first;
        final total = bals.fold<int>(0, (s, b) => s + b.physical);
        final units = ref.read(unitsProvider).valueOrNull ?? const [];
        final dec = units.where((u) => u.id == i.unitId).map((u) => u.decimals).firstOrNull ?? 0;
        _qty.text = Qty.format(total, decimals: dec);
      } catch (_) {
        _qty.text = '0';
      }
      _unitId = i.unitId;
      _barcodes.addAll(i.barcodes);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitsProvider).valueOrNull ?? const [];
    if (!_editing && units.isNotEmpty) _unitId ??= units.first.id;

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit product' : 'New product'), actions: [
        TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _key,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                TextFormField(
                  controller: _number,
                  decoration: const InputDecoration(labelText: 'Number (SKU)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _detail,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Detail *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _weight,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Weight (grams)'),
                ),
                const SizedBox(height: 12),
                Text('Barcodes', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _barcodeCtl,
                      decoration: InputDecoration(
                        labelText: 'Type, paste or scan',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () async {
                            final code = await scanBarcode(context);
                            if (code != null) {
                              _barcodeCtl.text = code;
                              await _addBarcode();
                            }
                          },
                        ),
                      ),
                      onSubmitted: (_) => _addBarcode(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _addBarcode, child: const Text('Add')),
                ]),
                Wrap(spacing: 8, children: [
                  for (var i = 0; i < _barcodes.length; i++)
                    InputChip(
                      label: Text(_barcodes[i].value),
                      onDeleted: () => setState(() => _barcodes.removeAt(i)),
                    ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _unitId,
                  decoration: const InputDecoration(labelText: 'Unit *'),
                  items: [for (final u in units) DropdownMenuItem(value: u.id, child: Text('${u.name} (${u.symbol})'))],
                  onChanged: (v) => setState(() => _unitId = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                if (!_editing)
                  TextFormField(
                    controller: _qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _comment,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Comment (optional)'),
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save product')),
              ]),
            ),
    );
  }

  Future<void> _addBarcode() async {
    final v = _barcodeCtl.text.trim();
    if (v.isEmpty) return;
    if (_barcodes.any((b) => b.value == v)) return showError(context, 'Barcode already added.');
    setState(() {
      _barcodes.add(BarcodeInput(v, type: BarcodeUtil.inferType(v), isPrimary: _barcodes.isEmpty));
      _barcodeCtl.clear();
    });
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    if (_unitId == null) return showError(context, 'Choose a unit.');
    final units = ref.read(unitsProvider).valueOrNull ?? const [];
    final dec = units.where((u) => u.id == _unitId).map((u) => u.decimals).firstOrNull ?? 0;
    final opening = _editing ? 0 : (Qty.parse(_qty.text, decimals: dec) ?? 0);
    final whs = ref.read(warehousesProvider).valueOrNull ?? const [];
    final input = ProductInput(
      id: widget.productId,
      name: _detail.text,
      unitId: _unitId!,
      sku: _number.text,
      description: _detail.text,
      weightGrams: int.tryParse(_weight.text) ?? 0,
      notes: _comment.text,
      barcodes: _barcodes,
      openingQuantity: opening,
      openingWarehouseId: whs.isEmpty ? null : whs.first.id,
    );
    setState(() => _saving = true);
    try {
      final repo = ref.read(productRepositoryProvider);
      if (_editing) {
        await repo.update(input);
        if (mounted) context.pop();
      } else {
        final id = await repo.create(input);
        if (mounted) context.pushReplacement('/inventory/$id');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utilities/qty_money.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../shared/providers/core_providers.dart';
import '../../scanning/presentation/barcode_scan_page.dart';
import '../domain/product_models.dart';
import '../../stock_movements/data/stock_engine.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});
  @override
  ConsumerState<ProductListScreen> createState() => _State();
}

class _State extends ConsumerState<ProductListScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  bool _grid = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(productQueryProvider).search;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final q = ref.read(productQueryProvider);
    final items = ref.read(productListProvider).valueOrNull;
    if (items == null || items.length < q.limit) return; // everything loaded, or loading
    if (_scroll.position.extentAfter < 400) {
      ref.read(productQueryProvider.notifier).state =
          q.copyWith(limit: q.limit + ProductQuery.pageSize);
    }
  }

  void _setQuery(ProductQuery Function(ProductQuery) f) {
    final n = ref.read(productQueryProvider.notifier);
    n.state = f(n.state);
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _setQuery((q) => q.copyWith(search: v)));
  }

  void _toggle(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(productQueryProvider);
    final async = ref.watch(productListProvider);
    final selecting = _selected.isNotEmpty;

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: selecting ? _selectionBar() : _normalBar(q),
        floatingActionButton: selecting
            ? null
            : FloatingActionButton.extended(
                onPressed: () => context.push('/inventory/new'),
                icon: const Icon(Icons.add),
                label: const Text('Product')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search name, SKU, barcode, category, supplier…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_search.text.isNotEmpty)
                    IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          _setQuery((q) => q.copyWith(search: ''));
                          setState(() {});
                        }),
                  IconButton(
                      tooltip: 'Scan barcode',
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () async {
                        final code = await scanBarcode(context);
                        if (code == null || !mounted) return;
                        _search.text = code;
                        _setQuery((q) => q.copyWith(search: code));
                        setState(() {});
                      }),
                ]),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in StockFilter.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: q.filter == f,
                      onSelected: (_) => _setQuery((q) => q.copyWith(filter: f)),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _content(async, q)),
        ]),
      ),
    );
  }

  PreferredSizeWidget _normalBar(ProductQuery q) => AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            tooltip: _grid ? 'List view' : 'Grid view',
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _grid = !_grid),
          ),
          PopupMenuButton<ProductSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: q.sort,
            onSelected: (s) => _setQuery((q) => q.copyWith(sort: s)),
            itemBuilder: (_) => [
              for (final s in ProductSort.values)
                CheckedPopupMenuItem(value: s, checked: s == q.sort, child: Text(s.label)),
            ],
          ),
          IconButton(
            tooltip: 'Filters',
            icon: Badge(isLabelVisible: q.hasAdvancedFilters, child: const Icon(Icons.filter_alt_outlined)),
            onPressed: () async {
              final r = await showModalBottomSheet<ProductQuery>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _FilterSheet(initial: ref.read(productQueryProvider)),
              );
              if (r != null) ref.read(productQueryProvider.notifier).state = r;
            },
          ),
          Consumer(builder: (context, ref, _) {
            final allow = ref.watch(allowNegativeStockProvider).valueOrNull ?? false;
            return PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'cat') context.push('/inventory/categories');
                if (v == 'neg') {
                  ref.read(settingsRepositoryProvider)
                      .set(StockEngine.settingAllowNegative, allow ? 'false' : 'true');
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'cat', child: Text('Categories')),
                CheckedPopupMenuItem(
                    value: 'neg', checked: allow, child: const Text('Allow negative stock')),
              ],
            );
          }),
        ],
      );

  PreferredSizeWidget _selectionBar() => AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
        title: Text('${_selected.length} selected'),
        actions: [
          IconButton(tooltip: 'Set category', icon: const Icon(Icons.category_outlined), onPressed: _bulkCategory),
          IconButton(tooltip: 'Set minimum stock', icon: const Icon(Icons.low_priority), onPressed: _bulkMin),
          IconButton(tooltip: 'Archive', icon: const Icon(Icons.archive_outlined), onPressed: _bulkArchive),
        ],
      );

  Future<void> _bulkArchive() async {
    final archiving = ref.read(productQueryProvider).filter != StockFilter.archived;
    final ok = await confirm(context, archiving ? 'Archive products?' : 'Restore products?',
        '${_selected.length} product(s) will be ${archiving ? 'archived. History is kept.' : 'restored.'}',
        action: archiving ? 'Archive' : 'Restore');
    if (!ok) return;
    await ref.read(productRepositoryProvider).bulkArchive(_selected.toList(), archiving);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _bulkCategory() async {
    final cats = ref.read(categoryTreeProvider).valueOrNull ?? const [];
    String? chosen;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Set category'),
          content: DropdownButtonFormField<String?>(
            value: chosen,
            items: [
              const DropdownMenuItem(value: null, child: Text('No category')),
              for (final c in cats)
                DropdownMenuItem(value: c.id, child: Text('${'  ' * c.depth}${c.name}')),
            ],
            onChanged: (v) => set(() => chosen = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await ref.read(productRepositoryProvider).bulkSetCategory(_selected.toList(), chosen);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _bulkMin() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Minimum stock'),
        content: TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Minimum stock level')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true) return;
    final v = Qty.parse(ctl.text, decimals: 3);
    if (v == null) {
      if (mounted) showError(context, 'Enter a valid number.');
      return;
    }
    await ref.read(productRepositoryProvider).bulkSetMinStock(_selected.toList(), v);
    if (mounted) setState(_selected.clear);
  }

  Widget _content(AsyncValue<List<ProductListItem>> async, ProductQuery q) {
    final items = async.valueOrNull;
    if (items == null) {
      return async.hasError
          ? Center(child: Text('Could not load products: ${async.error}'))
          : const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      final filtered = q.search.isNotEmpty || q.filter != StockFilter.all || q.hasAdvancedFilters;
      return EmptyState(
        icon: filtered ? Icons.search_off : Icons.inventory_2_outlined,
        title: filtered ? 'No products match' : 'No products yet',
        message: filtered ? 'Try clearing the search or filters.' : 'Add your first product to start tracking stock.',
        action: filtered
            ? OutlinedButton(
                onPressed: () {
                  _search.clear();
                  ref.read(productQueryProvider.notifier).state = const ProductQuery();
                },
                child: const Text('Clear filters'))
            : FilledButton.icon(
                onPressed: () => context.push('/inventory/new'),
                icon: const Icon(Icons.add),
                label: const Text('Add product')),
      );
    }
    if (_grid) {
      return GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220, mainAxisExtent: 230, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: items.length,
        itemBuilder: (_, i) => _GridTile(items[i], _selected.contains(items[i].id), _tap, _toggle),
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ListTile(items[i], _selected.contains(items[i].id), _tap, _toggle),
    );
  }

  void _tap(ProductListItem p) {
    if (_selected.isNotEmpty) {
      _toggle(p.id);
    } else {
      context.push('/inventory/${p.id}');
    }
  }
}

String _qtyText(ProductListItem p) =>
    '${Qty.format(p.physical, decimals: p.unitDecimals)} ${p.unitSymbol}';

class _ListTile extends StatelessWidget {
  const _ListTile(this.p, this.selected, this.onTap, this.onLongPress);
  final ProductListItem p;
  final bool selected;
  final void Function(ProductListItem) onTap;
  final void Function(String) onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final barcode = p.primaryBarcode;
    final catName = p.categoryName;
    final sub = [
      if (p.sku != null) 'SKU ${p.sku}',
      if (barcode != null) barcode,
      if (catName != null) catName,
    ].join(' · ');
    return Card(
      color: selected ? t.colorScheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(p),
        onLongPress: () => onLongPress(p.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            selected
                ? SizedBox(width: 56, height: 56, child: Icon(Icons.check_circle, color: t.colorScheme.primary, size: 36))
                : ProductAvatar(name: p.name, imagePath: p.imagePath),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty)
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
                const SizedBox(height: 6),
                StockStatusChip(p.status),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_qtyText(p), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Avail ${Qty.format(p.available, decimals: p.unitDecimals)}', style: t.textTheme.bodySmall),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile(this.p, this.selected, this.onTap, this.onLongPress);
  final ProductListItem p;
  final bool selected;
  final void Function(ProductListItem) onTap;
  final void Function(String) onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      color: selected ? t.colorScheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(p),
        onLongPress: () => onLongPress(p.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: LayoutBuilder(builder: (_, c) => ProductAvatar(name: p.name, imagePath: p.imagePath, size: c.maxHeight.clamp(40, 120)))),
                if (selected) Positioned(right: 0, top: 0, child: Icon(Icons.check_circle, color: t.colorScheme.primary)),
              ]),
            ),
            const SizedBox(height: 8),
            Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
            Text(_qtyText(p), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            StockStatusChip(p.status),
          ]),
        ),
      ),
    );
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});
  final ProductQuery initial;
  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late String? _cat = widget.initial.categoryId;
  late String? _sup = widget.initial.supplierId;
  late String? _wh = widget.initial.warehouseId;
  late DateTime? _added = widget.initial.addedAfter;
  late final _min = TextEditingController(text: widget.initial.minQty == null ? '' : Qty.format(widget.initial.minQty!, decimals: 3));
  late final _max = TextEditingController(text: widget.initial.maxQty == null ? '' : Qty.format(widget.initial.maxQty!, decimals: 3));
  String? _err;

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoryTreeProvider).valueOrNull ?? const [];
    final sups = ref.watch(suppliersProvider).valueOrNull ?? const [];
    final whs = ref.watch(warehousesProvider).valueOrNull ?? const [];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Filters', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _cat,
            decoration: const InputDecoration(labelText: 'Category (includes subcategories)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Any')),
              for (final c in cats) DropdownMenuItem(value: c.id, child: Text('${'  ' * c.depth}${c.name}')),
            ],
            onChanged: (v) => setState(() => _cat = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _sup,
            decoration: const InputDecoration(labelText: 'Supplier'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Any')),
              for (final s in sups) DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _sup = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _wh,
            decoration: const InputDecoration(labelText: 'Warehouse'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Any')),
              for (final w in whs) DropdownMenuItem(value: w.id, child: Text(w.name)),
            ],
            onChanged: (v) => setState(() => _wh = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _min, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Min quantity'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _max, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Max quantity'))),
          ]),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final addedDate = _added;
              return OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(addedDate == null ? 'Added since: any date' : 'Added since ${DateFormat.yMMMd().format(addedDate)}'),
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _added ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (d != null) setState(() => _added = d);
                },
              );
            },
          ),
          if (_err != null)
            Builder(
              builder: (context) {
                final err = _err;
                if (err == null) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: TextStyle(color: Theme.of(context).colorScheme.error)));
              },
            ),
          const SizedBox(height: 16),
          Row(children: [
            TextButton(
              onPressed: () => Navigator.pop(context, widget.initial.copyWith(categoryId: null, supplierId: null, warehouseId: null, minQty: null, maxQty: null, addedAfter: null)),
              child: const Text('Reset'),
            ),
            const Spacer(),
            FilledButton(onPressed: _apply, child: const Text('Apply')),
          ]),
        ]),
      ),
    );
  }

  void _apply() {
    int? minQ, maxQ;
    if (_min.text.trim().isNotEmpty) {
      minQ = Qty.parse(_min.text, decimals: 3);
      if (minQ == null) return setState(() => _err = 'Min quantity is not a valid number.');
    }
    if (_max.text.trim().isNotEmpty) {
      maxQ = Qty.parse(_max.text, decimals: 3);
      if (maxQ == null) return setState(() => _err = 'Max quantity is not a valid number.');
    }
    if (minQ != null && maxQ != null && minQ > maxQ) {
      return setState(() => _err = 'Min quantity is above max quantity.');
    }
    Navigator.pop(context, widget.initial.copyWith(categoryId: _cat, supplierId: _sup, warehouseId: _wh, minQty: minQ, maxQty: maxQ, addedAfter: _added));
  }
}

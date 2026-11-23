import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/common_widgets.dart';
import '../../../database/app_database.dart';
import '../../../shared/providers/core_providers.dart';
import '../../../shared/providers/database_providers.dart';

class BusScreen extends ConsumerStatefulWidget {
  const BusScreen({super.key});
  @override
  ConsumerState<BusScreen> createState() => _State();
}

class _State extends ConsumerState<BusScreen> {
  String? _selectedInvoiceId;

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(invoiceRepositoryProvider).watchAll(type: 'outgoing');
    return Scaffold(
      appBar: AppBar(title: const Text('Bus / Van')),
      body: StreamBuilder(
        stream: invoices,
        builder: (_, snap) {
          final rows = (snap.data ?? const []).where((i) => i.status == 'dispatched' || i.status == 'partiallyDispatched').toList();
          if (rows.isEmpty) return const EmptyState(icon: Icons.directions_bus, title: 'No invoices on the bus');
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final inv = rows[i];
              return Card(
                child: ListTile(
                  title: Text(inv.invoiceNumber),
                  subtitle: Text(inv.status),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() => _selectedInvoiceId = inv.id),
                ),
              );
            },
          );
        },
      ),
      bottomSheet: _selectedInvoiceId == null
          ? null
          : _InvoiceLocationPanel(invoiceId: _selectedInvoiceId!),
    );
  }
}

class _InvoiceLocationPanel extends ConsumerStatefulWidget {
  const _InvoiceLocationPanel({required this.invoiceId});
  final String invoiceId;
  @override
  ConsumerState<_InvoiceLocationPanel> createState() => _PanelState();
}

class _PanelState extends ConsumerState<_InvoiceLocationPanel> {
  final _addr = TextEditingController();
  Customer? _customer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inv = await ref.read(invoiceRepositoryProvider).getById(widget.invoiceId);
    final customerId = inv?.customerId;
    if (customerId == null) return;
    final c = await (ref.read(databaseProvider).select(ref.read(databaseProvider).customers)..where((x) => x.id.equals(customerId))).getSingleOrNull();
    if (c != null) {
      setState(() {
        _customer = c;
        _addr.text = c.address ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customer;
    if (customer == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(customer.name, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(controller: _addr, decoration: const InputDecoration(labelText: 'Location / address')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.map),
              label: const Text('Open in Maps'),
              onPressed: () {
                final a = _addr.text.trim();
                if (a.isEmpty) return;
                launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(a)}'));
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: () async {
                await (ref.read(databaseProvider).update(ref.read(databaseProvider).customers)..where((c) => c.id.equals(customer.id)))
                    .write(CustomersCompanion(address: Value(_addr.text.trim())));
                if (mounted) showInfo(context, 'Location saved.');
              },
              child: const Text('Save'),
            ),
          ),
        ]),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utilities/qty_money.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../shared/providers/core_providers.dart';
import '../data/category_repository.dart';

const _palette = <int>[
  0xFF2F6FDE, 0xFF2E9E5B, 0xFFF2A100, 0xFFD64545,
  0xFF8E44AD, 0xFF16A085, 0xFFE67E22, 0xFF7F8C8D,
];

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoryTreeProvider);
    final rows = async.valueOrNull ?? const <CategoryRow>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null, rows),
        icon: const Icon(Icons.add),
        label: const Text('Category'),
      ),
      body: rows.isEmpty
          ? const EmptyState(icon: Icons.category_outlined, title: 'No categories yet', message: 'Create categories (and subcategories) to organise products.')
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final c = rows[i];
                return ListTile(
                  contentPadding: EdgeInsets.only(left: 16.0 + 24 * c.depth, right: 16),
                  leading: CircleAvatar(radius: 10, backgroundColor: Color(c.color ?? 0xFF7F8C8D)),
                  title: Text(c.name),
                  subtitle: Text('${c.productCount} product(s) · ${Qty.format(c.units)} units'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _edit(context, ref, c, rows),
                );
              },
            ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, CategoryRow? existing, List<CategoryRow> all) async {
    final name = TextEditingController(text: existing?.name ?? '');
    String? parent = existing?.parentId;
    int color = existing?.color ?? _palette.first;
    // A category can't be its own parent: hide itself and its descendants.
    final blocked = <String>{};
    if (existing != null) {
      blocked.add(existing.id);
      var changed = true;
      while (changed) {
        changed = false;
        for (final c in all) {
          if (c.parentId != null && blocked.contains(c.parentId) && blocked.add(c.id)) changed = true;
        }
      }
    }
    final repo = ref.read(categoryRepositoryProvider);
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(existing == null ? 'New category' : 'Edit category'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: parent,
                decoration: const InputDecoration(labelText: 'Parent category'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None (top level)')),
                  for (final c in all.where((c) => !blocked.contains(c.id)))
                    DropdownMenuItem(value: c.id, child: Text('${'  ' * c.depth}${c.name}')),
                ],
                onChanged: (v) => set(() => parent = v),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () => set(() => color = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(c),
                      child: color == c ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                    ),
                  ),
              ]),
            ]),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  try {
                    await repo.delete(existing.id);
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('Delete'),
              ),
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  if (existing == null) {
                    await repo.create(name.text, parentId: parent, color: color);
                  } else {
                    await repo.update(existing.id, name.text, parentId: parent, color: color);
                  }
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

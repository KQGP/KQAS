import 'dart:io';

import 'package:flutter/material.dart';

import '../errors/app_exceptions.dart';
import '../theme/app_theme.dart';
import '../../features/products/domain/product_models.dart';

void showError(BuildContext context, Object e) {
  final msg = e is AppException ? e.message : 'Something went wrong: $e';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: StatusColors.danger));
}

void showInfo(BuildContext context, String msg) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(msg)));

Future<bool> confirm(BuildContext context, String title, String body,
    {String action = 'Confirm'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return r ?? false;
}

/// Colour + icon + label: never colour alone.
class StockStatusChip extends StatelessWidget {
  const StockStatusChip(this.status, {super.key});
  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      StockStatus.out => ('Out of stock', Icons.remove_circle, StatusColors.danger),
      StockStatus.low => ('Low stock', Icons.warning_amber_rounded, StatusColors.warning),
      StockStatus.over => ('Overstocked', Icons.trending_up, StatusColors.info),
      StockStatus.ok => ('In stock', Icons.check_circle, StatusColors.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class ProductAvatar extends StatelessWidget {
  const ProductAvatar({super.key, required this.name, this.imagePath, this.size = 56});
  final String name;
  final String? imagePath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = imagePath;
    final file = path == null ? null : File(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: file != null && file.existsSync()
            ? Image.file(file, fit: BoxFit.cover, cacheWidth: (size * 3).round())
            : Container(
                color: scheme.secondaryContainer,
                alignment: Alignment.center,
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: TextStyle(
                        fontSize: size * 0.42,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSecondaryContainer)),
              ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: t.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          Builder(
            builder: (context) {
              final msg = message;
              final act = action;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (msg != null) ...[
                    const SizedBox(height: 6),
                    Text(msg,
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline)),
                  ],
                  if (act != null) ...[const SizedBox(height: 16), act],
                ],
              );
            },
          ),
        ]),
      ),
    );
  }
}

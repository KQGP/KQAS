import 'package:flutter/material.dart';

/// Honest stand-in for modules scheduled in later phases: no fake actions.
class PhasePendingScreen extends StatelessWidget {
  const PhasePendingScreen({
    super.key,
    required this.title,
    required this.phase,
    required this.icon,
  });
  final String title;
  final String phase;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: t.colorScheme.outline),
            const SizedBox(height: 16),
            Text('$title is not built yet', style: t.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Scheduled for $phase.',
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: t.colorScheme.outline)),
          ]),
        ),
      ),
    );
  }
}

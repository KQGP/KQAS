import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/common_widgets.dart';
import 'scan_mode_screen.dart';

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner')),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanModeScreen(initialLoadMode: true))),
            icon: const Icon(Icons.add_box),
            label: const Text('Load to inventory'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanModeScreen(initialLoadMode: false))),
            icon: const Icon(Icons.outbox),
            label: const Text('Unload from inventory'),
          ),
        ]),
      ),
    );
  }
}

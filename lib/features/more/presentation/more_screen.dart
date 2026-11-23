import 'package:flutter/material.dart';

import '../../../core/widgets/common_widgets.dart';
import '../../bus/presentation/bus_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.directions_bus), title: const Text('Bus / Van'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BusScreen()))),
        const ListTile(leading: Icon(Icons.notifications), title: Text('Notifications')),
        const ListTile(leading: Icon(Icons.fact_check), title: Text('Stocktaking')),
        const ListTile(leading: Icon(Icons.swap_horiz), title: Text('Transfers')),
        const ListTile(leading: Icon(Icons.people), title: Text('Users')),
        const ListTile(leading: Icon(Icons.settings), title: Text('Settings')),
        const ListTile(leading: Icon(Icons.backup), title: Text('Backup')),
      ]),
    );
  }
}

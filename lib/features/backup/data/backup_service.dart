import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BackupService {
  /// Copies the database file to the app documents directory with a timestamp.
  Future<String> backup() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dir.path, 'kqas.sqlite'));
    // Drift default location may differ; attempt common path.
    if (!await dbFile.exists()) {
      // try databases folder
      final alt = File(p.join(dir.path, 'databases', 'kqas.sqlite'));
      if (await alt.exists()) {
        final dest = File(p.join(dir.path, 'backups', 'kqas_${DateTime.now().millisecondsSinceEpoch}.sqlite'));
        await dest.parent.create(recursive: true);
        await alt.copy(dest.path);
        return dest.path;
      }
      throw StateError('Database file not found.');
    }
    final dest = File(p.join(dir.path, 'backups', 'kqas_${DateTime.now().millisecondsSinceEpoch}.sqlite'));
    await dest.parent.create(recursive: true);
    await dbFile.copy(dest.path);
    return dest.path;
  }
}

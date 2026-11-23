import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';

/// Single database instance for the whole app. Tests override this provider
/// with an in-memory database.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

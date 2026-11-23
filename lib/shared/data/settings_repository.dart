import 'package:drift/drift.dart';

import '../../database/app_database.dart';

class SettingsRepository {
  SettingsRepository(this._db);
  final AppDatabase _db;

  Stream<String?> watch(String key) =>
      (_db.select(_db.appSettings)..where((s) => s.settingKey.equals(key)))
          .watchSingleOrNull()
          .map((r) => r?.settingValue);

  Future<void> set(String key, String value) => _db.into(_db.appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(settingKey: key, settingValue: value));
}

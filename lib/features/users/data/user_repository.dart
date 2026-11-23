import 'package:drift/drift.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../database/app_database.dart';

class UserRepository {
  UserRepository(this._db);
  final AppDatabase _db;

  Stream<List<User>> watchAll() => _db.select(_db.users).watch();

  Future<String> create({required String name, String role = 'operator', bool canOverrideNegativeStock = false}) async {
    if (name.trim().isEmpty) throw const ValidationException('User name is required.');
    final row = await _db.into(_db.users).insertReturning(UsersCompanion.insert(
          name: name.trim(),
          role: Value(role),
          canOverrideNegativeStock: Value(canOverrideNegativeStock),
        ));
    return row.id;
  }

  Future<void> update(String id, {String? name, String? role, bool? canOverrideNegativeStock, bool? isActive}) async {
    await (_db.update(_db.users)..where((u) => u.id.equals(id))).write(UsersCompanion(
          name: name == null ? const Value.absent() : Value(name.trim()),
          role: role == null ? const Value.absent() : Value(role),
          canOverrideNegativeStock: canOverrideNegativeStock == null ? const Value.absent() : Value(canOverrideNegativeStock),
          isActive: isActive == null ? const Value.absent() : Value(isActive),
        ));
  }

  Future<void> setOverridePermission(String id, bool allowed) => update(id, canOverrideNegativeStock: allowed);
}


typedef UsersRepository = UserRepository;

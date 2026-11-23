import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUID v4 text primary key shared by all entity tables.
mixin UuidPk on Table {
  TextColumn get id => text().clientDefault(() => _uuid.v4())();
  @override
  Set<Column> get primaryKey => {id};
}

/// Schema conventions
/// - Timestamps: stored as UTC; convert with `.toLocal()` only in the UI.
/// - Money: integer MINOR units (cents) in columns suffixed `_minor`. No doubles.
/// - Quantities: integers. For fractional units, store qty * kQtyScale; the
///   `units.decimals` column says how many fractional digits are meaningful.
const int kQtyScale = 1000;

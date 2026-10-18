import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'gemini_service.dart';

/// A verdict that was recorded in the history.
class VerdictRecord {
  const VerdictRecord({
    required this.id,
    required this.judgedAt,
    required this.loserIsWife,
    required this.dishDifficulty,
    required this.reason,
  });

  /// A UUID, so records made on different devices never clash.
  final String id;

  final DateTime judgedAt;

  /// true if the wife did the dishes, false if the husband did.
  final bool loserIsWife;

  final int dishDifficulty;
  final String reason;
}

/// The names of the couple, kept once for the whole history.
class CoupleNames {
  const CoupleNames({this.wife = '', this.husband = ''});

  /// The names as entered, empty when none was entered.
  final String wife;
  final String husband;

  // Fall back to "Wife" and "Husband" when no name is entered.
  String get wifeLabel => wife.isEmpty ? 'Wife' : wife;
  String get husbandLabel => husband.isEmpty ? 'Husband' : husband;
}

/// Stores the verdict history and the couple's names.
///
/// The screens only talk to this class, so the storage (SQLite on the device
/// for now) can be replaced later without touching them.
class VerdictRepository {
  static const _verdicts = 'verdicts';
  static const _settings = 'settings';

  Database? _database;

  Future<Database> _open() async {
    return _database ??= await openDatabase(
      p.join(await getDatabasesPath(), 'dish_judge.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_verdicts (
            id TEXT PRIMARY KEY,
            judged_at TEXT NOT NULL,
            loser TEXT NOT NULL,
            dish_difficulty INTEGER NOT NULL,
            reason TEXT NOT NULL
          )
        ''');
        // One row per setting, such as `('wife_name', 'Hanako')`.
        await db.execute('''
          CREATE TABLE $_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
  }

  /// Adds [verdict] to the history.
  Future<void> save(Verdict verdict) async {
    final db = await _open();
    await db.insert(_verdicts, {
      'id': const Uuid().v4(),
      // Stored in UTC so the order stays right across time zones.
      'judged_at': DateTime.now().toUtc().toIso8601String(),
      'loser': verdict.loserIsWife ? 'wife' : 'husband',
      'dish_difficulty': verdict.dishDifficulty,
      'reason': verdict.reason,
    });
  }

  /// Returns the whole history, newest first.
  Future<List<VerdictRecord>> fetchAll() async {
    final db = await _open();
    final rows = await db.query(_verdicts, orderBy: 'judged_at DESC');
    return [
      for (final row in rows)
        VerdictRecord(
          id: row['id'] as String,
          judgedAt: DateTime.parse(row['judged_at'] as String).toLocal(),
          loserIsWife: row['loser'] == 'wife',
          dishDifficulty: row['dish_difficulty'] as int,
          reason: row['reason'] as String,
        ),
    ];
  }

  /// Removes the record with [id] from the history.
  Future<void> delete(String id) async {
    final db = await _open();
    await db.delete(_verdicts, where: 'id = ?', whereArgs: [id]);
  }

  /// Returns the saved names, empty ones if none were saved yet.
  Future<CoupleNames> fetchNames() async {
    final db = await _open();
    final rows = await db.query(
      _settings,
      where: 'key IN (?, ?)',
      whereArgs: ['wife_name', 'husband_name'],
    );
    final values = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    return CoupleNames(
      wife: values['wife_name'] ?? '',
      husband: values['husband_name'] ?? '',
    );
  }

  /// Saves [names], replacing the ones saved before.
  Future<void> saveNames(CoupleNames names) async {
    final db = await _open();
    // Both rows change together or not at all.
    await db.transaction((txn) async {
      for (final (key, value) in [
        ('wife_name', names.wife),
        ('husband_name', names.husband),
      ]) {
        // `INSERT OR REPLACE`: adds the row, or overwrites the one with the
        // same primary key.
        await txn.insert(_settings, {
          'key': key,
          'value': value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}

/// The repository shared by the whole app.
final verdictRepository = VerdictRepository();

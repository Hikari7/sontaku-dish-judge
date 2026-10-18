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
      version: 2,
      // Runs only on a fresh install.
      onCreate: (db, version) async {
        await db.execute(_createVerdictsSql(_verdicts));
        await db.execute(_createSettingsSql);
      },
      // Runs when an older database is opened, inside a transaction.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _upgradeToVersion2(db);
      },
    );
  }

  static String _createVerdictsSql(String table) =>
      '''
    CREATE TABLE $table (
      id TEXT PRIMARY KEY,
      judged_at TEXT NOT NULL,
      loser TEXT NOT NULL,
      dish_difficulty INTEGER NOT NULL,
      reason TEXT NOT NULL
    )
  ''';

  /// One row per setting, such as `('wife_name', 'Hanako')`.
  static const _createSettingsSql =
      '''
    CREATE TABLE IF NOT EXISTS $_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''';

  /// Version 1 stored the names on every verdict. Version 2 keeps them once in
  /// the settings table and drops the per-verdict name columns.
  ///
  /// Every step checks what is already there, so this also finishes a
  /// database left half-upgraded: one was seen with all the changes applied
  /// but its version still at 1.
  static Future<void> _upgradeToVersion2(Database db) async {
    await db.execute(_createSettingsSql);

    final columns = await db.rawQuery('PRAGMA table_info($_verdicts)');
    if (!columns.any((column) => column['name'] == 'wife_name')) return;

    // Carry over the names from the newest verdict, unless they were only
    // the "Wife" / "Husband" fallbacks. `OR IGNORE` keeps a name that is
    // already saved.
    for (final (column, fallback) in [
      ('wife_name', 'Wife'),
      ('husband_name', 'Husband'),
    ]) {
      await db.execute('''
        INSERT OR IGNORE INTO $_settings (key, value)
        SELECT '$column', $column FROM $_verdicts
        WHERE $column != '$fallback'
        ORDER BY judged_at DESC
        LIMIT 1
      ''');
    }

    // Older SQLite versions cannot drop a column, so copy the rows into a new
    // table without the name columns and swap it in.
    await db.execute('DROP TABLE IF EXISTS ${_verdicts}_new');
    await db.execute(_createVerdictsSql('${_verdicts}_new'));
    await db.execute('''
      INSERT INTO ${_verdicts}_new (id, judged_at, loser, dish_difficulty, reason)
      SELECT id, judged_at, loser, dish_difficulty, reason FROM $_verdicts
    ''');
    await db.execute('DROP TABLE $_verdicts');
    await db.execute('ALTER TABLE ${_verdicts}_new RENAME TO $_verdicts');
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

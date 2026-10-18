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
    required this.wifeName,
    required this.husbandName,
  });

  /// A UUID, so records made on different devices never clash.
  final String id;

  final DateTime judgedAt;

  /// true if the wife did the dishes, false if the husband did.
  final bool loserIsWife;

  final int dishDifficulty;
  final String reason;

  /// The names as they were entered at the time of the verdict.
  final String wifeName;
  final String husbandName;
}

/// Stores the verdict history.
///
/// The screens only talk to this class, so the storage (SQLite on the device
/// for now) can be replaced later without touching them.
class VerdictRepository {
  static const _table = 'verdicts';

  Database? _database;

  Future<Database> _open() async {
    return _database ??= await openDatabase(
      p.join(await getDatabasesPath(), 'dish_judge.db'),
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE $_table (
          id TEXT PRIMARY KEY,
          judged_at TEXT NOT NULL,
          loser TEXT NOT NULL,
          dish_difficulty INTEGER NOT NULL,
          reason TEXT NOT NULL,
          wife_name TEXT NOT NULL,
          husband_name TEXT NOT NULL
        )
      '''),
    );
  }

  /// Adds [verdict] to the history.
  Future<void> save({
    required Verdict verdict,
    required String wifeName,
    required String husbandName,
  }) async {
    final db = await _open();
    await db.insert(_table, {
      'id': const Uuid().v4(),
      // Stored in UTC so the order stays right across time zones.
      'judged_at': DateTime.now().toUtc().toIso8601String(),
      'loser': verdict.loserIsWife ? 'wife' : 'husband',
      'dish_difficulty': verdict.dishDifficulty,
      'reason': verdict.reason,
      'wife_name': wifeName,
      'husband_name': husbandName,
    });
  }

  /// Returns the whole history, newest first.
  Future<List<VerdictRecord>> fetchAll() async {
    final db = await _open();
    final rows = await db.query(_table, orderBy: 'judged_at DESC');
    return [
      for (final row in rows)
        VerdictRecord(
          id: row['id'] as String,
          judgedAt: DateTime.parse(row['judged_at'] as String).toLocal(),
          loserIsWife: row['loser'] == 'wife',
          dishDifficulty: row['dish_difficulty'] as int,
          reason: row['reason'] as String,
          wifeName: row['wife_name'] as String,
          husbandName: row['husband_name'] as String,
        ),
    ];
  }
}

/// The repository shared by the whole app.
final verdictRepository = VerdictRepository();

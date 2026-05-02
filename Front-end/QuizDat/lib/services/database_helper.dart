import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String dbPath;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // On desktop, use a user-writable directory so the app works
      // correctly when installed in Program Files (which is read-only).
      final appData = Platform.isWindows
          ? (Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '.')
          : (Platform.environment['HOME'] ?? '.');
      final dir = Directory(join(appData, 'QuizDat'));
      if (!await dir.exists()) await dir.create(recursive: true);
      dbPath = join(dir.path, 'quizdat.db');
    } else {
      dbPath = join(await getDatabasesPath(), 'quizdat.db');
    }

    return await openDatabase(
      dbPath,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        // Enable foreign key support so ON DELETE CASCADE works
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Repository Table
    await db.execute('''
      CREATE TABLE Repository (
        repository_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        last_modified INTEGER DEFAULT (strftime('%s', 'now')),
        is_synced INTEGER DEFAULT 1,
        deleted_at INTEGER DEFAULT NULL
      )
    ''');

    // SetCard Table
    await db.execute('''
      CREATE TABLE SetCard (
        set_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        repository_id TEXT NOT NULL,
        last_learned_time TEXT,
        last_modified INTEGER DEFAULT (strftime('%s', 'now')),
        is_synced INTEGER DEFAULT 1,
        deleted_at INTEGER DEFAULT NULL,
        FOREIGN KEY (repository_id) REFERENCES Repository(repository_id) ON DELETE CASCADE
      )
    ''');

    // Card Table
    await db.execute('''
      CREATE TABLE Card (
        card_id TEXT PRIMARY KEY,
        term TEXT NOT NULL,
        definition TEXT NOT NULL,
        state TEXT DEFAULT 'new',
        set_id TEXT NOT NULL,
        last_modified INTEGER DEFAULT (strftime('%s', 'now')),
        is_synced INTEGER DEFAULT 1,
        deleted_at INTEGER DEFAULT NULL,
        FOREIGN KEY (set_id) REFERENCES SetCard(set_id) ON DELETE CASCADE
      )
    ''');

    // Calendar Table
    await db.execute('''
      CREATE TABLE Calendar (
        calendar_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        date TEXT NOT NULL,
        type TEXT DEFAULT 'event',
        is_done INTEGER DEFAULT 0,
        created_at TEXT,
        last_modified INTEGER DEFAULT (strftime('%s', 'now')),
        is_synced INTEGER DEFAULT 1,
        deleted_at INTEGER DEFAULT NULL
      )
    ''');

    // Sync Queue Table (for offline operations)
    await db.execute('''
      CREATE TABLE SyncQueue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT,
        created_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // SM2Progress Table (version 4: composite PK (card_id, card_type), buried_until)
    await db.execute('''
      CREATE TABLE SM2Progress (
        card_id       TEXT    NOT NULL,
        card_type     TEXT    NOT NULL DEFAULT 'flip',
        repetitions   INTEGER DEFAULT 0,
        ease_factor   REAL    DEFAULT 2.5,
        interval_days INTEGER DEFAULT 1,
        next_review   TEXT    DEFAULT NULL,
        buried_until  TEXT    DEFAULT NULL,
        PRIMARY KEY (card_id, card_type)
      )
    ''');

    // SM2DailyLog Table
    await db.execute('''
      CREATE TABLE SM2DailyLog (
        date           TEXT PRIMARY KEY,
        new_studied    INTEGER DEFAULT 0,
        review_studied INTEGER DEFAULT 0
      )
    ''');

    // SM2Settings Table
    await db.execute('''
      CREATE TABLE SM2Settings (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS SM2Progress (
          card_id       TEXT PRIMARY KEY,
          repetitions   INTEGER DEFAULT 0,
          ease_factor   REAL    DEFAULT 2.5,
          interval_days INTEGER DEFAULT 1,
          next_review   TEXT    DEFAULT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS SM2DailyLog (
          date           TEXT PRIMARY KEY,
          new_studied    INTEGER DEFAULT 0,
          review_studied INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS SM2Settings (
          key   TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    }
    if (oldVersion < 4) {
      // Migrate SM2Progress: rename, add card_type + buried_until, copy old data as 'flip'
      await db.execute('ALTER TABLE SM2Progress RENAME TO SM2Progress_old');
      await db.execute('''
        CREATE TABLE SM2Progress (
          card_id       TEXT    NOT NULL,
          card_type     TEXT    NOT NULL DEFAULT 'flip',
          repetitions   INTEGER DEFAULT 0,
          ease_factor   REAL    DEFAULT 2.5,
          interval_days INTEGER DEFAULT 1,
          next_review   TEXT    DEFAULT NULL,
          buried_until  TEXT    DEFAULT NULL,
          PRIMARY KEY (card_id, card_type)
        )
      ''');
      await db.execute('''
        INSERT INTO SM2Progress (card_id, card_type, repetitions, ease_factor, interval_days, next_review)
        SELECT card_id, 'flip', repetitions, ease_factor, interval_days, next_review
        FROM SM2Progress_old
      ''');
      await db.execute('DROP TABLE SM2Progress_old');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Repository (
          repository_id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT,
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          is_synced INTEGER DEFAULT 1,
          deleted_at INTEGER DEFAULT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS SetCard (
          set_id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          repository_id TEXT NOT NULL,
          last_learned_time TEXT,
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          is_synced INTEGER DEFAULT 1,
          deleted_at INTEGER DEFAULT NULL,
          FOREIGN KEY (repository_id) REFERENCES Repository(repository_id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS Card (
          card_id TEXT PRIMARY KEY,
          term TEXT NOT NULL,
          definition TEXT NOT NULL,
          state TEXT DEFAULT 'new',
          set_id TEXT NOT NULL,
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          is_synced INTEGER DEFAULT 1,
          deleted_at INTEGER DEFAULT NULL,
          FOREIGN KEY (set_id) REFERENCES SetCard(set_id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS Calendar (
          calendar_id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          description TEXT,
          date TEXT NOT NULL,
          type TEXT DEFAULT 'event',
          is_done INTEGER DEFAULT 0,
          created_at TEXT,
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          is_synced INTEGER DEFAULT 1,
          deleted_at INTEGER DEFAULT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS SyncQueue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          operation TEXT NOT NULL,
          data TEXT,
          created_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');
    }
  }

  // ==========================================
  // SM2 SETTINGS OPERATIONS
  // ==========================================

  Future<int> getSm2NewLimit() async {
    final db = await database;
    final results = await db.query('SM2Settings', where: 'key = ?', whereArgs: ['new_limit']);
    if (results.isEmpty) return 20; // default
    return int.tryParse(results.first['value'] as String? ?? '20') ?? 20;
  }

  Future<int> getSm2ReviewLimit() async {
    final db = await database;
    final results = await db.query('SM2Settings', where: 'key = ?', whereArgs: ['review_limit']);
    if (results.isEmpty) return 200; // default
    return int.tryParse(results.first['value'] as String? ?? '200') ?? 200;
  }

  Future<void> setSm2NewLimit(int limit) async {
    final db = await database;
    await db.insert('SM2Settings', {'key': 'new_limit', 'value': limit.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setSm2ReviewLimit(int limit) async {
    final db = await database;
    await db.insert('SM2Settings', {'key': 'review_limit', 'value': limit.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> getSm2BuryRelated() async {
    final db = await database;
    final results = await db.query('SM2Settings', where: 'key = ?', whereArgs: ['bury_related']);
    if (results.isEmpty) return true; // default: bury on
    return (results.first['value'] as String? ?? '1') == '1';
  }

  Future<void> setSm2BuryRelated(bool value) async {
    final db = await database;
    await db.insert('SM2Settings', {'key': 'bury_related', 'value': value ? '1' : '0'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==========================================
  // SM2 DAILY LOG OPERATIONS
  // ==========================================

  Future<Map<String, int>> getSm2DailyLog(String date) async {
    final db = await database;
    final results = await db.query('SM2DailyLog', where: 'date = ?', whereArgs: [date]);
    if (results.isEmpty) return {'new_studied': 0, 'review_studied': 0};
    return {
      'new_studied': results.first['new_studied'] as int? ?? 0,
      'review_studied': results.first['review_studied'] as int? ?? 0,
    };
  }

  Future<void> incrementSm2DailyNew(String date) async {
    final db = await database;
    await db.rawInsert('''
      INSERT INTO SM2DailyLog (date, new_studied, review_studied)
      VALUES (?, 1, 0)
      ON CONFLICT(date) DO UPDATE SET new_studied = new_studied + 1
    ''', [date]);
  }

  Future<void> incrementSm2DailyReview(String date) async {
    final db = await database;
    await db.rawInsert('''
      INSERT INTO SM2DailyLog (date, new_studied, review_studied)
      VALUES (?, 0, 1)
      ON CONFLICT(date) DO UPDATE SET review_studied = review_studied + 1
    ''', [date]);
  }

  // ==========================================
  // SM2 PROGRESS OPERATIONS
  // ==========================================

  Future<Map<String, dynamic>?> getSm2Progress(String cardId) async {
    final db = await database;
    final results = await db.query(
      'SM2Progress',
      where: 'card_id = ? AND card_type = ?',
      whereArgs: [cardId, 'flip'],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // Lay progress theo card_type cu the
  Future<Map<String, dynamic>?> getSm2ProgressTyped(String cardId, String cardType) async {
    final db = await database;
    final results = await db.query(
      'SM2Progress',
      where: 'card_id = ? AND card_type = ?',
      whereArgs: [cardId, cardType],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> upsertSm2Progress(Map<String, dynamic> data) async {
    final db = await database;
    // Ensure card_type is present
    if (!data.containsKey('card_type')) data['card_type'] = 'flip';
    await db.insert(
      'SM2Progress',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Bury the sibling card (opposite type) until tomorrow
  Future<void> buryRelatedCard(String cardId, String reviewedCardType) async {
    final db = await database;
    final siblingType = reviewedCardType == 'flip' ? 'typing' : 'flip';
    final tomorrow = DateTime.now().add(const Duration(days: 1)).toIso8601String().substring(0, 10);
    await db.rawInsert('''
      INSERT INTO SM2Progress (card_id, card_type, buried_until)
      VALUES (?, ?, ?)
      ON CONFLICT(card_id, card_type) DO UPDATE SET buried_until = ?
    ''', [cardId, siblingType, tomorrow, tomorrow]);
  }

  /// Xoa toan bo SM2 progress cua mot set (reset)
  Future<void> clearSm2ProgressForSet(String setId) async {
    final db = await database;
    await db.rawDelete('''
      DELETE FROM SM2Progress
      WHERE card_id IN (
        SELECT card_id FROM Card WHERE set_id = ? AND deleted_at IS NULL
      )
    ''', [setId]);
  }

  // ==========================================
  // REPOSITORY OPERATIONS
  // ==========================================

  Future<List<Map<String, dynamic>>> getAllRepositories() async {
    final db = await database;
    return await db.query(
      'Repository',
      where: 'deleted_at IS NULL',
      orderBy: 'last_modified DESC',
    );
  }

  Future<Map<String, dynamic>?> getRepositoryById(String id) async {
    final db = await database;
    final results = await db.query(
      'Repository',
      where: 'repository_id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> insertRepository(Map<String, dynamic> repository) async {
    final db = await database;
    await db.insert('Repository', repository);
  }

  Future<void> updateRepository(String id, Map<String, dynamic> data) async {
    final db = await database;
    data['last_modified'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.update(
      'Repository',
      data,
      where: 'repository_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteRepository(String id) async {
    final db = await database;
    // Hard delete: ON DELETE CASCADE sẽ tự động xóa toàn bộ SetCard và Card bên trong
    await db.delete(
      'Repository',
      where: 'repository_id = ?',
      whereArgs: [id],
    );
  }

  // ==========================================
  // SETCARD OPERATIONS
  // ==========================================

  Future<List<Map<String, dynamic>>> getAllSetCards() async {
    final db = await database;
    return await db.query(
      'SetCard',
      where: 'deleted_at IS NULL',
      orderBy: 'last_modified DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getSetCardsByRepositoryId(
      String repositoryId) async {
    final db = await database;
    return await db.query(
      'SetCard',
      where: 'repository_id = ? AND deleted_at IS NULL',
      whereArgs: [repositoryId],
      orderBy: 'last_modified DESC',
    );
  }

  Future<Map<String, dynamic>?> getSetCardById(String id) async {
    final db = await database;
    final results = await db.query(
      'SetCard',
      where: 'set_id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> insertSetCard(Map<String, dynamic> setCard) async {
    final db = await database;
    await db.insert('SetCard', setCard);
  }

  Future<void> updateSetCard(String id, Map<String, dynamic> data) async {
    final db = await database;
    data['last_modified'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.update(
      'SetCard',
      data,
      where: 'set_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteSetCard(String id) async {
    final db = await database;
    // Hard delete: ON DELETE CASCADE sẽ tự động xóa toàn bộ Card bên trong
    await db.delete(
      'SetCard',
      where: 'set_id = ?',
      whereArgs: [id],
    );
  }

  // ==========================================
  // CARD OPERATIONS
  // ==========================================

  Future<List<Map<String, dynamic>>> getCardsBySetId(String setId) async {
    final db = await database;
    return await db.query(
      'Card',
      where: 'set_id = ? AND deleted_at IS NULL',
      whereArgs: [setId],
      orderBy: 'card_id ASC',
    );
  }

  Future<Map<String, dynamic>?> getCardById(String id) async {
    final db = await database;
    final results = await db.query(
      'Card',
      where: 'card_id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> insertCard(Map<String, dynamic> card) async {
    final db = await database;
    await db.insert('Card', card);
  }

  Future<void> updateCard(String id, Map<String, dynamic> data) async {
    final db = await database;
    data['last_modified'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.update(
      'Card',
      data,
      where: 'card_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCard(String id) async {
    final db = await database;
    await db.update(
      'Card',
      {
        'deleted_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'is_synced': 0,
      },
      where: 'card_id = ?',
      whereArgs: [id],
    );
  }

  Future<int> countCardsNeedToLearn() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM Card 
      WHERE (state = 'new' OR state = 'learning') AND deleted_at IS NULL
    ''');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, int>> getSetStatistics(String setId) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT state, COUNT(*) as count 
      FROM Card 
      WHERE set_id = ? AND deleted_at IS NULL 
      GROUP BY state
    ''', [setId]);

    final stats = <String, int>{
      'new': 0,
      'learning': 0,
      'learned': 0,
    };

    for (var row in results) {
      final state = row['state'] as String;
      final count = row['count'] as int;
      stats[state] = count;
    }
    return stats;
  }

  // ==========================================
  // CALENDAR OPERATIONS
  // ==========================================

  Future<List<Map<String, dynamic>>> getAllCalendarEvents() async {
    final db = await database;
    return await db.query(
      'Calendar',
      where: 'deleted_at IS NULL',
      orderBy: 'date DESC',
    );
  }

  Future<Map<String, dynamic>?> getCalendarEventById(String id) async {
    final db = await database;
    final results = await db.query(
      'Calendar',
      where: 'calendar_id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> insertCalendarEvent(Map<String, dynamic> event) async {
    final db = await database;
    await db.insert('Calendar', event);
  }

  Future<void> updateCalendarEvent(String id, Map<String, dynamic> data) async {
    final db = await database;
    data['last_modified'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.update(
      'Calendar',
      data,
      where: 'calendar_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCalendarEvent(String id) async {
    final db = await database;
    await db.update(
      'Calendar',
      {
        'deleted_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'is_synced': 0,
      },
      where: 'calendar_id = ?',
      whereArgs: [id],
    );
  }

  // ==========================================
  // SYNC QUEUE OPERATIONS
  // ==========================================

  Future<void> addToSyncQueue({
    required String tableName,
    required String recordId,
    required String operation,
    String? data,
  }) async {
    final db = await database;
    await db.insert('SyncQueue', {
      'table_name': tableName,
      'record_id': recordId,
      'operation': operation,
      'data': data,
    });
  }

  Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final db = await database;
    return await db.query('SyncQueue', orderBy: 'created_at ASC');
  }

  Future<void> clearSyncQueue() async {
    final db = await database;
    await db.delete('SyncQueue');
  }

  Future<void> removeSyncQueueItem(int id) async {
    final db = await database;
    await db.delete('SyncQueue', where: 'id = ?', whereArgs: [id]);
  }

  // ==========================================
  // BATCH OPERATIONS
  // ==========================================

  Future<void> batchInsertSetCards(List<Map<String, dynamic>> setCards) async {
    final db = await database;
    final batch = db.batch();
    for (var setCard in setCards) {
      batch.insert(
        'SetCard',
        setCard,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> batchInsertCards(List<Map<String, dynamic>> cards) async {
    final db = await database;
    final batch = db.batch();
    for (var card in cards) {
      batch.insert(
        'Card',
        card,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> batchInsertCalendarEvents(List<Map<String, dynamic>> events) async {
    final db = await database;
    final batch = db.batch();
    for (var event in events) {
      batch.insert(
        'Calendar',
        event,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ==========================================
  // UTILITY OPERATIONS
  // ==========================================

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('Repository');
    await db.delete('SetCard');
    await db.delete('Card');
    await db.delete('Calendar');
    await db.delete('SyncQueue');
  }
}

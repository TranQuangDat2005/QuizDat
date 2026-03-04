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
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'quizdat.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
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
    await db.update(
      'Repository',
      {
        'deleted_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'is_synced': 0,
      },
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
    await db.update(
      'SetCard',
      {
        'deleted_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'is_synced': 0,
      },
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
      orderBy: 'last_modified DESC',
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

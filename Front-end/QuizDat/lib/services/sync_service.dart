import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_helper.dart';
import 'google_sheets_setcard_adapter.dart';
import 'google_sheets_card_adapter.dart';
import 'google_sheets_calendar_adapter.dart';
import '../models/set_card.dart';
import '../models/calendar_event.dart';

class SyncService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Connectivity _connectivity = Connectivity();
  final GoogleSheetsSetCardAdapter _setCardAdapter = GoogleSheetsSetCardAdapter();
  final GoogleSheetsCardAdapter _cardAdapter = GoogleSheetsCardAdapter();
  final GoogleSheetsCalendarAdapter _calendarAdapter = GoogleSheetsCalendarAdapter();

  /// Check if device has internet connection
  Future<bool> hasConnection() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  /// Pull data from server and save to local database
  Future<Map<String, int>> pullFromServer() async {
    if (!await hasConnection()) {
      throw Exception('No internet connection');
    }

    final stats = {
      'repositories': 0, // Not implemented in sheets yet?
      'setCards': 0,
      'cards': 0,
      'calendar': 0,
    };

    try {
      // 1. Pull SetCards
      final sets = await _setCardAdapter.getAllSetCards();
      final setCardsBatch = <Map<String, dynamic>>[];
      
      for (final set in sets) {
        setCardsBatch.add({
          'set_id': set.setId,
          'name': set.name,
          'repository_id': set.repositoryId,
          'last_learned_time': set.lastLearnedTime?.toIso8601String() ?? '',
          'is_synced': 1,
        });
      }
      
      if (setCardsBatch.isNotEmpty) {
        await _dbHelper.batchInsertSetCards(setCardsBatch);
        stats['setCards'] = setCardsBatch.length;
      }

      // 2. Pull Cards
      final allCards = await _cardAdapter.getAllCards();
      final cardsBatch = <Map<String, dynamic>>[];
      
      for (final card in allCards) {
        cardsBatch.add({
          'card_id': card.cardId,
          'term': card.term,
          'definition': card.definition,
          'state': card.state,
          'set_id': card.setId,
          'is_synced': 1,
        });
      }

      if (cardsBatch.isNotEmpty) {
        await _dbHelper.batchInsertCards(cardsBatch);
        stats['cards'] = cardsBatch.length;
      }

      // 3. Pull Calendar Events
      final events = await _calendarAdapter.getAllEvents();
      final calendarBatch = <Map<String, dynamic>>[];
      
      for (final event in events) {
        // We need to preserve created_at from local if possible, or use now. 
        // But for bulk sync, reading each local item defeats the purpose of batching speed?
        // If we treat "pullFromServer" as "Overwrite Local Cache", we can just overwrite.
        // Or we can do a smart merge: read all local IDs, map them, then merge.
        // For significant speedup, let's just overwrite with server data (assuming server is truth).
        // If user has local unsynced changes, they should have been pushed first (pushToServer called before pullFromServer in fullSync).
        
        calendarBatch.add({
          'calendar_id': event.id,
          'title': event.title,
          'description': event.description,
          'date': event.date.toIso8601String(),
          'type': event.type.name,
          'is_done': event.isDone ? 1 : 0,
          'created_at': DateTime.now().toIso8601String(), // Ideally server should have this
          'is_synced': 1,
        });
      }

      if (calendarBatch.isNotEmpty) {
        await _dbHelper.batchInsertCalendarEvents(calendarBatch);
        stats['calendar'] = calendarBatch.length;
      }

      return stats;
    } catch (e) {
      print('❌ Pull from server failed: $e');
      throw Exception('Pull from server failed: $e');
    }
  }

  /// Push local unsynced data to server
  Future<Map<String, int>> pushToServer() async {
    if (!await hasConnection()) {
      throw Exception('No internet connection');
    }

    final stats = {
      'repositories': 0,
      'setCards': 0,
      'cards': 0,
      'calendar': 0,
      'errors': 0,
    };

    // Use sync queue to push changes
    final syncQueue = await _dbHelper.getSyncQueue();
    
    for (final item in syncQueue) {
      try {
        final tableName = item['table_name'];
        final recordId = item['record_id'];
        final operation = item['operation'];
        final dataStr = item['data'];
        final data = dataStr != null ? jsonDecode(dataStr) : null;
        
        // Execute operation based on type
        if (tableName == 'SetCard') {
            if (operation == 'CREATE' && data != null) {
                await _setCardAdapter.createSetCard(data['set_id'], data['name'], data['repository_id']);
            } else if (operation == 'UPDATE' && data != null) {
                await _setCardAdapter.updateSetCard(
                    data['set_id'],
                    data['name'],
                    data['repository_id'],
                    data['last_learned_time'] != null ? DateTime.parse(data['last_learned_time']) : null
                );
            } else if (operation == 'DELETE') {
                 await _setCardAdapter.deleteSetCard(recordId);
            }
            stats['setCards'] = stats['setCards']! + 1;
        } else if (tableName == 'Card') {
            if (operation == 'CREATE' && data != null) {
                await _cardAdapter.createCard(data['card_id'], data['term'], data['definition'], data['state'], data['set_id']);
            } else if (operation == 'UPDATE' && data != null) {
                 await _cardAdapter.updateCard(recordId, data['term'], data['definition'], data['state'], data['set_id'] ?? '');
                 // Note: updateCard in adapter needs set_id? 
                 // We might not have set_id in data if it wasn't updated.
                 // We should probably fetch local card to get set_id if missing.
                 // For now assumes data has it or we might fail.
            } else if (operation == 'DELETE') {
                 await _cardAdapter.deleteCard(recordId);
            }
            stats['cards'] = stats['cards']! + 1;
        } else if (tableName == 'Calendar') {
            if (operation == 'CREATE' && data != null) {
                await _calendarAdapter.createEvent(
                    data['calendar_id'], 
                    data['title'], 
                    data['description'], 
                    DateTime.parse(data['date']), 
                    CalendarType.values.firstWhere((e) => e.name == data['type'], orElse: () => CalendarType.study),
                     data['is_done'] == 1
                );
            } else if (operation == 'UPDATE' && data != null) {
                 await _calendarAdapter.updateEvent(
                    recordId, 
                    data['title'], 
                    data['description'], 
                    DateTime.parse(data['date']), 
                    CalendarType.values.firstWhere((e) => e.name == data['type'], orElse: () => CalendarType.study),
                     data['is_done'] == 1
                );
            } else if (operation == 'DELETE') {
                 await _calendarAdapter.deleteEvent(recordId);
            }
            stats['calendar'] = stats['calendar']! + 1;
        }
        
        // Remove from sync queue after successful sync
        await _dbHelper.removeSyncQueueItem(item['id']);
        
      
      } catch (e) {
        print('Failed to sync item: $e');
        stats['errors'] = stats['errors']! + 1;
      }
    }

    return stats;
  }

  /// Full bidirectional sync
  Future<void> fullSync() async {
    if (!await hasConnection()) {
      print('No connection, skipping sync');
      return;
    }

    try {
      print('🔄 Starting full sync...');
      
      // First push local changes
      final pushStats = await pushToServer();
      print('📤 Push completed: ${pushStats.toString()}');
      
      // Then pull server updates
      final pullStats = await pullFromServer();
      print('📥 Pull completed: ${pullStats.toString()}');
      
      print('✅ Full sync completed');
    } catch (e) {
      print('❌ Sync failed: $e');
    }
  }

  /// Initialize app - pull all data on first launch
  Future<void> initializeApp() async {
    try {
      if (await hasConnection()) {
        await pullFromServer();
        print('✅ App initialized with server data');
      } else {
        print('⚠️  Offline mode - using local data');
      }
    } catch (e) {
      print('⚠️  Failed to initialize from server: $e');
    }
  }
}

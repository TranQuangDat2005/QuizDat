import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/calendar_event.dart';
import 'database_helper.dart';
import 'google_sheets_calendar_adapter.dart';
import 'config_manager.dart';

class CalendarService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Connectivity _connectivity = Connectivity();
  final GoogleSheetsCalendarAdapter _sheetsAdapter = GoogleSheetsCalendarAdapter();
  final ConfigManager _config = ConfigManager();

  Future<bool> _hasConnection() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  /// Fetch events (Offline-First)
  // Local-First Strategy but fallback to Remote if empty
  Future<List<CalendarEvent>> fetchEvents() async {
    try {
      final localEvents = await _dbHelper.getAllCalendarEvents();
      
      if (localEvents.isEmpty && await _hasConnection()) {
        try {
          final events = await _sheetsAdapter.getAllEvents();
          // Save to local database
          for (var event in events) {
            final eventData = {
                'calendar_id': event.id,
                'title': event.title,
                'description': event.description,
                'date': event.date.toIso8601String(),
                'type': event.type.name,
                'is_done': event.isDone ? 1 : 0,
                'created_at': DateTime.now().toIso8601String(),
                'is_synced': 1,
            };
            final existing = await _dbHelper.getCalendarEventById(event.id);
            if (existing == null) {
                await _dbHelper.insertCalendarEvent(eventData);
            } else {
                if (existing['created_at'] != null) {
                    eventData['created_at'] = existing['created_at'];
                }
                await _dbHelper.updateCalendarEvent(event.id, eventData);
            }
          }
           return events;
        } catch (e) {
           print('⚠️  Calendar fetch failed: $e');
        }
      }

      return localEvents.map((event) => CalendarEvent.fromJson(event)).toList();
    } catch (e) {
      print('⚠️  Error fetching calendar events: $e');
      return [];
    }
  }

  /// Create event (Offline-First)
  Future<CalendarEvent> createEvent({
    required String title,
    required String description,
    required DateTime date,
    required String type,
  }) async {
    final eventId = DateTime.now().millisecondsSinceEpoch.toString();
    
    final eventData = {
      'calendar_id': eventId,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'type': type,
      'is_done': 0,
      'created_at': DateTime.now().toIso8601String(),
      'is_synced': 0,
    };

    // Save to local database first
    await _dbHelper.insertCalendarEvent(eventData);

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        final newEvent = await _sheetsAdapter.createEvent(
          eventId,
          title,
          description,
          date,
          CalendarType.values.firstWhere((e) => e.name == type, orElse: () => CalendarType.study),
          false
        );
        
        // Update local event with server ID and mark as synced
        await _dbHelper.updateCalendarEvent(eventId, {'is_synced': 1});
        return newEvent;
      } catch (e) {
        print('⚠️  Sheets sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'Calendar',
          recordId: eventId,
          operation: 'CREATE',
          data: jsonEncode(eventData),
        );
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'Calendar',
        recordId: eventId,
        operation: 'CREATE',
        data: jsonEncode(eventData),
      );
    }

    return CalendarEvent.fromJson(eventData);
  }

  /// Update event (Offline-First)
  Future<CalendarEvent> updateEvent({
    required String calendarId,
    required String title,
    required String description,
    required DateTime date,
    required String type,
    required bool isDone,
  }) async {
    final updateData = {
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'type': type,
      'is_done': isDone ? 1 : 0,
      'is_synced': 0,
    };

    // Update local database first
    await _dbHelper.updateCalendarEvent(calendarId, updateData);

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        await _sheetsAdapter.updateEvent(
          calendarId,
          title,
          description,
          date,
          CalendarType.values.firstWhere((e) => e.name == type, orElse: () => CalendarType.study),
          isDone
        );
        
        await _dbHelper.updateCalendarEvent(calendarId, {'is_synced': 1});
        
        // Return updated object
        final localEvent = await _dbHelper.getCalendarEventById(calendarId);
        return CalendarEvent.fromJson(localEvent!);
      } catch (e) {
        print('⚠️  Update sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'Calendar',
          recordId: calendarId,
          operation: 'UPDATE',
          data: jsonEncode(updateData),
        );
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'Calendar',
        recordId: calendarId,
        operation: 'UPDATE',
        data: jsonEncode(updateData),
      );
    }

    final localEvent = await _dbHelper.getCalendarEventById(calendarId);
    return CalendarEvent.fromJson(localEvent!);
  }

  /// Toggle event status (Offline-First)
  Future<void> toggleEventStatus({
    required String calendarId,
    required bool isDone,
  }) async {
    final updateData = {
      'is_done': isDone ? 1 : 0,
      'is_synced': 0,
    };

    // Update local database first
    await _dbHelper.updateCalendarEvent(calendarId, updateData);

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        // We need full event data to update status in Sheets via `updateEvent`
        // Or we need a specific `updateStatus` in adapter.
        // Adapter `updateEvent` requires full data.
        // Let's fetch local data to get other fields.
        final localEventMap = await _dbHelper.getCalendarEventById(calendarId);
        if (localEventMap != null) {
          final event = CalendarEvent.fromJson(localEventMap);
           await _sheetsAdapter.updateEvent(
            calendarId,
            event.title,
            event.description,
            event.date,
            event.type,
            isDone
          );
          await _dbHelper.updateCalendarEvent(calendarId, {'is_synced': 1});
        }
      } catch (e) {
        print('⚠️  Status sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'Calendar',
          recordId: calendarId,
          operation: 'UPDATE',
          data: jsonEncode(updateData),
        );
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'Calendar',
        recordId: calendarId,
        operation: 'UPDATE',
        data: jsonEncode(updateData),
      );
    }
  }

  /// Delete event (Offline-First)
  Future<void> deleteEvent(String calendarId) async {
    // Soft delete in local database
    await _dbHelper.deleteCalendarEvent(calendarId);

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        final result = await _sheetsAdapter.deleteEvent(calendarId);
        if (result) {
          print('✅ Calendar event deleted from Sheets');
        }
      } catch (e) {
        print('⚠️  Delete sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'Calendar',
          recordId: calendarId,
          operation: 'DELETE',
        );
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'Calendar',
        recordId: calendarId,
        operation: 'DELETE',
      );
    }
  }

  Exception _handleError(String message) {
    print("❌ Calendar Error: $message");
    return Exception(message);
  }
}

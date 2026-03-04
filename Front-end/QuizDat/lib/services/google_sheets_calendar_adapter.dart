import 'google_sheets_service.dart';
import '../models/calendar_event.dart';

/// Adapter to convert Google Sheets data to Calendar operations
class GoogleSheetsCalendarAdapter {
  final GoogleSheetsService _sheets = GoogleSheetsService();
  static const _sheetName = 'Calendar';

  /// Get all calendar events from Google Sheets
  Future<List<CalendarEvent>> getAllEvents() async {
    try {
      final rows = await _sheets.getSheetMaps(_sheetName);
      
      return rows.map((row) {
        return CalendarEvent(
          id: row['calendar_id'] ?? '',
          title: row['title'] ?? '',
          description: row['description'] ?? '',
          date: DateTime.tryParse(row['date'] ?? '') ?? DateTime.now(),
          type: CalendarType.values.firstWhere(
            (e) => e.name == (row['type'] ?? 'study'),
            orElse: () => CalendarType.study,
          ),
          isDone: (row['is_done'] == 'true' || row['is_done'] == '1'),
        );
      }).toList();
    } catch (e) {
      print('❌ Error reading calendar events from Sheets: $e');
      rethrow;
    }
  }

  /// Create calendar event in Google Sheets
  Future<CalendarEvent> createEvent(
    String id,
    String title,
    String description,
    DateTime date,
    CalendarType type,
    bool isDone,
  ) async {
    try {
      await _sheets.appendRows(_sheetName, [
        [
          id,
          title,
          description,
          date.toIso8601String(),
          type.name,
          isDone ? '1' : '0',
          DateTime.now().toIso8601String(),
        ],
      ]);

      return CalendarEvent(
        id: id,
        title: title,
        description: description,
        date: date,
        type: type,
        isDone: isDone,
      );
    } catch (e) {
      print('❌ Error creating calendar event in Sheets: $e');
      rethrow;
    }
  }

  /// Update calendar event in Google Sheets
  Future<CalendarEvent> updateEvent(
    String id,
    String title,
    String description,
    DateTime date,
    CalendarType type,
    bool isDone,
  ) async {
    try {
      final rows = await _sheets.getSheetValues(_sheetName);
      
      // Find row index
      int rowIndex = -1;
      // Assume first column is ID
      for (int i = 1; i < rows.length; i++) {
        if (rows[i].isNotEmpty && rows[i][0].toString() == id) {
          rowIndex = i;
          break;
        }
      }

      if (rowIndex == -1) {
        throw Exception('Calendar event not found');
      }

      // Update the row
      // We overwrite the whole row for simplicity, preserving columns order logic
      // Ideally we should use mapping to find column indices but for now we write row by row
      // created_at is at index 6. We should preserve it or just overwrite/ignore if we don't have it locally passed in.
      // The `updateRange` updates what we send.
      // Columns: calendar_id, title, description, date, type, is_done, created_at
      
      // Fetch existing row to preserve created_at?
      // Or just write new params.
      String createdAt = DateTime.now().toIso8601String();
      if (rows[rowIndex].length > 6) {
        createdAt = rows[rowIndex][6].toString();
      }

      await _sheets.updateRange(
        _sheetName,
        'A${rowIndex + 1}:G${rowIndex + 1}',
        [
          [
            id,
            title,
            description,
            date.toIso8601String(),
            type.name,
            isDone ? '1' : '0',
            createdAt,
          ]
        ],
      );

      return CalendarEvent(
        id: id,
        title: title,
        description: description,
        date: date,
        type: type,
        isDone: isDone,
      );
    } catch (e) {
      print('❌ Error updating calendar event in Sheets: $e');
      rethrow;
    }
  }

  /// Delete calendar event from Google Sheets
  Future<bool> deleteEvent(String id) async {
    try {
      final rows = await _sheets.getSheetValues(_sheetName);
      
      // Find row index
      int rowIndex = -1;
      for (int i = 1; i < rows.length; i++) {
        if (rows[i].isNotEmpty && rows[i][0].toString() == id) {
          rowIndex = i;
          break;
        }
      }

      if (rowIndex == -1) {
        return false;
      }

      await _sheets.deleteRow(_sheetName, rowIndex);
      return true;
    } catch (e) {
      print('❌ Error deleting calendar event from Sheets: $e');
      rethrow;
    }
  }
}

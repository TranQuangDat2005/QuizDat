import 'google_sheets_service.dart';
import '../models/repository.dart';

/// Adapter to convert Google Sheets data to Repository operations
class GoogleSheetsRepositoryAdapter {
  final GoogleSheetsService _sheets = GoogleSheetsService();
  static const _sheetName = 'Repository';

  /// Get all repositories from Google Sheets
  Future<List<Repository>> getAllRepositories() async {
    try {
      final rows = await _sheets.getSheetValues(_sheetName);
      
      if (rows.isEmpty || rows.length == 1) {
        return []; // Only header or empty
      }

      // Skip header row
      return rows.skip(1).map((row) {
        return Repository(
          repositoryId: row[0].toString(),
          name: row.length > 1 ? row[1].toString() : '',
          description: row.length > 2 ? row[2].toString() : '',
        );
      }).toList();
    } catch (e) {
      print('❌ Error reading repositories from Sheets: $e');
      rethrow;
    }
  }

  /// Create repository in Google Sheets
  Future<Repository> createRepository(String id, String name, String description) async {
    try {
      await _sheets.appendRows(_sheetName, [
        [id, name, description],
      ]);

      return Repository(
        repositoryId: id,
        name: name,
        description: description,
      );
    } catch (e) {
      print('❌ Error creating repository in Sheets: $e');
      rethrow;
    }
  }

  /// Update repository in Google Sheets
  Future<Repository> updateRepository(String id, String name, String description) async {
    try {
      final rows = await _sheets.getSheetValues(_sheetName);
      
      // Find row index (accounting for 0-indexed array + 1 for header)
      int rowIndex = -1;
      for (int i = 1; i < rows.length; i++) {
        if (rows[i][0].toString() == id) {
          rowIndex = i;
          break;
        }
      }

      if (rowIndex == -1) {
        throw Exception('Repository not found');
      }

      // Update the row (row index + 2 for Sheets: 1 for header, 1 for 1-based indexing)
      await _sheets.updateRange(
        _sheetName,
        'A${rowIndex + 1}:C${rowIndex + 1}',
        [[id, name, description]],
      );

      return Repository(
        repositoryId: id,
        name: name,
        description: description,
      );
    } catch (e) {
      print('❌ Error updating repository in Sheets: $e');
      rethrow;
    }
  }

  /// Delete repository from Google Sheets
  Future<bool> deleteRepository(String id) async {
    try {
      final rows = await _sheets.getSheetValues(_sheetName);
      
      // Find row index
      int rowIndex = -1;
      for (int i = 1; i < rows.length; i++) {
        if (rows[i][0].toString() == id) {
          rowIndex = i;
          break;
        }
      }

      if (rowIndex == -1) {
        return false; // Already deleted or not found
      }

      await _sheets.deleteRow(_sheetName, rowIndex);
      return true;
    } catch (e) {
      print('❌ Error deleting repository from Sheets: $e');
      rethrow;
    }
  }
}

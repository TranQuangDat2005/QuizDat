import 'package:googleapis/sheets/v4.dart' as sheets;
import 'google_sheets_service.dart';
import '../models/set_card.dart';

/// Adapter to convert Google Sheets data to SetCard operations
class GoogleSheetsSetCardAdapter {
  final GoogleSheetsService _sheets = GoogleSheetsService();
  static const _sheetName = 'SetCard';

  /// Get all set cards from Google Sheets
  Future<List<SetCard>> getAllSetCards() async {
    try {
      final rows = await _sheets.getSheetMaps(_sheetName);
      
      return rows.map((row) {
        return SetCard(
          setId: row['set_id'] ?? '',
          name: row['name'] ?? '',
          repositoryId: row['repository_id'] ?? '',
          lastLearnedTime: row['last_learned_time'] != null && row['last_learned_time']!.isNotEmpty
              ? DateTime.tryParse(row['last_learned_time']!)
              : null,
        );
      }).toList();
    } catch (e) {
      print('❌ Error reading set cards from Sheets: $e');
      rethrow;
    }
  }

  /// Get set cards by repository ID
  Future<List<SetCard>> getSetCardsByRepoId(String repoId) async {
    final allSets = await getAllSetCards();
    return allSets.where((set) => set.repositoryId == repoId).toList();
  }

  /// Get recent sets (sorted by last learned time)
  Future<List<SetCard>> getRecentSets() async {
    final allSets = await getAllSetCards();
    allSets.sort((a, b) {
      if (a.lastLearnedTime == null) return 1;
      if (b.lastLearnedTime == null) return -1;
      return b.lastLearnedTime!.compareTo(a.lastLearnedTime!);
    });
    return allSets.take(10).toList();
  }

  /// Create set card in Google Sheets
  Future<SetCard> createSetCard(String id, String name, String repositoryId) async {
    try {
      await _sheets.appendRows(_sheetName, [
        [id, name, repositoryId, ''],
      ]);

      return SetCard(
        setId: id,
        name: name,
        repositoryId: repositoryId,
      );
    } catch (e) {
      print('❌ Error creating set card in Sheets: $e');
      rethrow;
    }
  }

  /// Update set card in Google Sheets
  Future<SetCard> updateSetCard(
    String id,
    String name,
    String repositoryId,
    DateTime? lastLearnedTime,
  ) async {
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
        throw Exception('SetCard not found');
      }

      // Update the row
      await _sheets.updateRange(
        _sheetName,
        'A${rowIndex + 1}:D${rowIndex + 1}',
        [
          [
            id,
            name,
            repositoryId,
            lastLearnedTime?.toIso8601String() ?? '',
          ]
        ],
      );

      return SetCard(
        setId: id,
        name: name,
        repositoryId: repositoryId,
        lastLearnedTime: lastLearnedTime,
      );
    } catch (e) {
      print('❌ Error updating set card in Sheets: $e');
      rethrow;
    }
  }

  /// Delete set card from Google Sheets
  Future<bool> deleteSetCard(String id) async {
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
      print('❌ Error deleting set card from Sheets: $e');
      rethrow;
    }
  }
  /// Bulk create set cards
  Future<void> bulkCreateSetCards(List<SetCard> setCards) async {
    try {
      if (setCards.isEmpty) return;

      final rows = setCards.map((card) => [
        card.setId,
        card.name,
        card.repositoryId,
        card.lastLearnedTime?.toIso8601String() ?? '',
      ]).toList();

      await _sheets.appendRows(_sheetName, rows);
    } catch (e) {
      print('❌ Error bulk creating set cards: $e');
      rethrow;
    }
  }

  /// Bulk update set cards
  Future<void> bulkUpdateSetCards(List<SetCard> setCards) async {
    try {
      if (setCards.isEmpty) return;

      // 1. Get current rows to find indices
      final rows = await _sheets.getSheetValues(_sheetName);
      final idToRowIndex = <String, int>{};
      
      // Skip header (row 0), start from row 1 (which is index 1 in 0-based list)
      for (int i = 1; i < rows.length; i++) {
        if (rows[i].isNotEmpty) {
          idToRowIndex[rows[i][0].toString()] = i;
        }
      }

      // 2. Get Sheet ID
      final sheetId = await _sheets.getSheetIdByName(_sheetName);
      if (sheetId == null) throw Exception('Sheet $_sheetName not found');

      // 3. Prepare requests
      final requests = <sheets.Request>[];

      for (final card in setCards) {
        final rowIndex = idToRowIndex[card.setId];
        if (rowIndex == null) continue; // Skip if ID not found

        // Create row data
        final values = [
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: card.setId)),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: card.name)),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: card.repositoryId)),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: card.lastLearnedTime?.toIso8601String() ?? '')),
        ];

        final request = sheets.Request(
          updateCells: sheets.UpdateCellsRequest(
            start: sheets.GridCoordinate(
              sheetId: sheetId,
              rowIndex: rowIndex,
              columnIndex: 0,
            ),
            rows: [sheets.RowData(values: values)],
            fields: '*', // Update all fields in the range
          ),
        );
        requests.add(request);
      }

      if (requests.isNotEmpty) {
        await _sheets.batchUpdate(requests);
      }
    } catch (e) {
      print('❌ Error bulk updating set cards: $e');
      rethrow;
    }
  }
}

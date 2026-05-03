import 'package:googleapis/sheets/v4.dart' as sheets;
import 'google_sheets_service.dart';
import 'database_helper.dart';
import '../models/card.dart';

/// Adapter to convert Google Sheets data to Card operations
class GoogleSheetsCardAdapter {
  final GoogleSheetsService _sheets = GoogleSheetsService();
  final DatabaseHelper _db = DatabaseHelper();
  static const _sheetName = 'Card';

  // ── Helpers ────────────────────────────────────────────────────────────────
  static int    _parseInt(String? v, [int d = 0])      => int.tryParse(v ?? '') ?? d;
  static double _parseDbl(String? v, [double d = 2.5]) => double.tryParse(v ?? '') ?? d;


  /// Get all cards from Google Sheets.
  /// Also upserts SM-2 progress columns into local SQLite so the app can use them.
  Future<List<VocabCard>> getAllCards() async {
    try {
      final rows = await _sheets.getSheetMaps(_sheetName);

      final cards = rows.map((row) {
        return VocabCard(
          cardId: row['card_id'] ?? '',
          term: row['term'] ?? '',
          definition: row['definition'] ?? '',
          state: row['state'] ?? 'new',
          setId: row['set_id'] ?? '',
        );
      }).toList();

      // Sync SM-2 progress from Sheets → local SQLite
      for (final row in rows) {
        final cardId = row['card_id'] ?? '';
        if (cardId.isEmpty) continue;

        if (row.containsKey('flip_rep') && row['flip_rep']!.isNotEmpty) {
          await _db.upsertSm2Progress({
            'card_id': cardId,
            'card_type': 'flip',
            'repetitions':   _parseInt(row['flip_rep']),
            'ease_factor':   _parseDbl(row['flip_ease']),
            'interval_days': _parseInt(row['flip_interval'], 1),
            'next_review':   row['flip_next']?.isNotEmpty == true ? row['flip_next'] : null,
          });
        }
        if (row.containsKey('type_rep') && row['type_rep']!.isNotEmpty) {
          await _db.upsertSm2Progress({
            'card_id': cardId,
            'card_type': 'typing',
            'repetitions':   _parseInt(row['type_rep']),
            'ease_factor':   _parseDbl(row['type_ease']),
            'interval_days': _parseInt(row['type_interval'], 1),
            'next_review':   row['type_next']?.isNotEmpty == true ? row['type_next'] : null,
          });
        }
      }

      return cards;
    } catch (e) {
      print('❌ Error reading cards from Sheets: $e');
      rethrow;
    }
  }

  /// Get cards by set ID
  Future<List<VocabCard>> getCardsBySetId(String setId) async {
    final allCards = await getAllCards();
    return allCards.where((card) => card.setId == setId).toList();
  }

  /// Get count of cards needing to learn (new + learning)
  Future<int> getCardsNeedToLearnCount() async {
    final allCards = await getAllCards();
    return allCards.where((card) => card.state == 'new' || card.state == 'learning').length;
  }

  /// Create card in Google Sheets
  Future<VocabCard> createCard(
    String id,
    String term,
    String definition,
    String state,
    String setId,
  ) async {
    try {
      await _sheets.appendRows(_sheetName, [
        [id, term, definition, state, setId],
      ]);

      return VocabCard(
        cardId: id,
        term: term,
        definition: definition,
        state: state,
        setId: setId,
      );
    } catch (e) {
      print('❌ Error creating card in Sheets: $e');
      rethrow;
    }
  }

  /// Bulk create cards
  Future<List<VocabCard>> bulkCreateCards(List<Map<String, dynamic>> cardsData, String setId) async {
    try {
      final rows = cardsData.map((card) {
        // Generate a simpler ID if not provided, or ensure unique
        // Using timestamp + index is safer
        final id = DateTime.now().millisecondsSinceEpoch.toString() + cardsData.indexOf(card).toString();
        // Or if ID is passed in cardsData, use it. But for creation, usually we generate.
        // Let's check how it was called. In `CardService` it generates ID locally.
        // But if adapting `CardService` to use this, we might pass pre-generated IDs.
        // For compatibility with previous signature which took Map, let's assume we might generate or use provided.
        // If card['card_id'] exists, use it.
        final cardId = card['card_id'] ?? id;
        
        return [
          cardId,
          card['term'] ?? '',
          card['definition'] ?? '',
          card['state'] ?? 'new',
          setId,
        ];
      }).toList();

      await _sheets.appendRows(_sheetName, rows);

      return rows.map((row) => VocabCard(
        cardId: row[0].toString(),
        term: row[1].toString(),
        definition: row[2].toString(),
        state: row[3].toString(),
        setId: row[4].toString(),
      )).toList();
    } catch (e) {
      print('❌ Error bulk creating cards in Sheets: $e');
      rethrow;
    }
  }

  /// Update card in Google Sheets
  Future<VocabCard> updateCard(
    String id,
    String term,
    String definition,
    String state,
    String setId,
  ) async {
    try {
      final rows = await _sheets.getSheetValues(_sheetName);
      
      // Find row index
      int rowIndex = -1;
      // Assume column 0 is ID
      for (int i = 1; i < rows.length; i++) {
        if (rows[i].isNotEmpty && rows[i][0].toString() == id) {
          rowIndex = i;
          break;
        }
      }

      if (rowIndex == -1) {
        throw Exception('Card not found');
      }

      // Update the row
      await _sheets.updateRange(
        _sheetName,
        'A${rowIndex + 1}:E${rowIndex + 1}',
        [[id, term, definition, state, setId]],
      );

      return VocabCard(
        cardId: id,
        term: term,
        definition: definition,
        state: state,
        setId: setId,
      );
    } catch (e) {
      print('❌ Error updating card in Sheets: $e');
      rethrow;
    }
  }

  /// Bulk update cards
  Future<void> bulkUpdateCards(List<Map<String, dynamic>> updates) async {
    try {
      if (updates.isEmpty) return;

      // 1. Get current rows to find indices
      final rows = await _sheets.getSheetValues(_sheetName);
      final idToRowIndex = <String, int>{};
      
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

      for (final update in updates) {
        final cardId = update['cardId'] ?? update['card_id'];
        if (cardId == null) continue;
        
        final rowIndex = idToRowIndex[cardId];
        if (rowIndex == null) continue;

        // Columns 1-3: term, definition, state
        final baseValues = [
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: update['term'])),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: update['definition'])),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: update['state'])),
        ];

        requests.add(sheets.Request(
          updateCells: sheets.UpdateCellsRequest(
            start: sheets.GridCoordinate(sheetId: sheetId, rowIndex: rowIndex, columnIndex: 1),
            rows: [sheets.RowData(values: baseValues)],
            fields: '*',
          ),
        ));

        // Columns 5-12: SM-2 progress (flip then typing)
        final flipP = await _db.getSm2ProgressTyped(cardId.toString(), 'flip');
        final typeP = await _db.getSm2ProgressTyped(cardId.toString(), 'typing');

        String _s(dynamic v) => v?.toString() ?? '';

        final sm2Values = [
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: _s(flipP?['repetitions']))),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: _s(flipP?['ease_factor']))),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: _s(flipP?['interval_days']))),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: _s(flipP?['next_review']))),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: _s(typeP?['repetitions']))),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: _s(typeP?['ease_factor']))),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: _s(typeP?['interval_days']))),
          sheets.CellData(userEnteredValue: sheets.ExtendedValue(stringValue: _s(typeP?['next_review']))),
        ];

        requests.add(sheets.Request(
          updateCells: sheets.UpdateCellsRequest(
            start: sheets.GridCoordinate(sheetId: sheetId, rowIndex: rowIndex, columnIndex: 5),
            rows: [sheets.RowData(values: sm2Values)],
            fields: '*',
          ),
        ));
      }

      if (requests.isNotEmpty) {
        await _sheets.batchUpdate(requests);
      }
    } catch (e) {
      print('❌ Error bulk updating cards: $e');
      rethrow;
    }
  }


  /// Delete card from Google Sheets
  Future<bool> deleteCard(String id) async {
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
      print('❌ Error deleting card from Sheets: $e');
      rethrow;
    }
  }

  /// Delete multiple cards by their Set IDs (useful for cascading deletes)
  Future<void> deleteCardsBySetIds(List<String> setIds) async {
    if (setIds.isEmpty) return;
    try {
      final rows = await _sheets.getSheetValues(_sheetName);
      List<int> rowsToDelete = [];
      
      // Assuming set_id is at column index 4
      for (int i = 1; i < rows.length; i++) {
        if (rows[i].length > 4 && setIds.contains(rows[i][4].toString())) {
          rowsToDelete.add(i);
        }
      }

      await _sheets.deleteRows(_sheetName, rowsToDelete);
    } catch (e) {
      print('❌ Error deleting cards by set IDs from Sheets: $e');
      rethrow;
    }
  }
}

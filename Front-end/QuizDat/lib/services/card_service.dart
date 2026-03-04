import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/card.dart';
import 'database_helper.dart';
import 'google_sheets_card_adapter.dart';
import 'config_manager.dart';

class CardService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Connectivity _connectivity = Connectivity();
  final GoogleSheetsCardAdapter _sheetsAdapter = GoogleSheetsCardAdapter();
  final ConfigManager _config = ConfigManager();

  /// Check if device has internet connection
  Future<bool> _hasConnection() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  /// Fetch cards by set ID (Offline-First)
  // Local-First Strategy but fallback to Remote if empty
  Future<List<VocabCard>> fetchCardsBySetId(String setId) async {
    try {
      final localCards = await _dbHelper.getCardsBySetId(setId);
      
      if (localCards.isEmpty && await _hasConnection()) {
        print('⚠️  Local cards empty, fetching from Sheets...');
        final cards = await _sheetsAdapter.getCardsBySetId(setId);

        // Save to local database
        for (var card in cards) {
          final cardData = {
            'card_id': card.cardId,
            'term': card.term,
            'definition': card.definition,
            'state': card.state,
            'set_id': card.setId,
            'is_synced': 1,
          };
          
          final existing = await _dbHelper.getCardById(card.cardId);
          if (existing == null) {
            await _dbHelper.insertCard(cardData);
          } else {
            await _dbHelper.updateCard(card.cardId, cardData);
          }
        }
        return cards;
      }
      
      return localCards.map((card) => VocabCard.fromJson(card)).toList();
    } catch (e) {
      print('⚠️  Error fetching cards: $e');
      return [];
    }
  }

  /// Create card (Offline-First)
  Future<VocabCard> createCard({
    required String term,
    required String definition,
    required String setId,
  }) async {
    final cardId = DateTime.now().millisecondsSinceEpoch.toString();
    
    final cardData = {
      'card_id': cardId,
      'term': term,
      'definition': definition,
      'state': 'learning', // Default state
      'set_id': setId,
      'is_synced': 0, // Will be synced later
    };

    // Save to local database first
    await _dbHelper.insertCard(cardData);

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        final newCard = await _sheetsAdapter.createCard(
          cardId, 
          term, 
          definition, 
          'learning', 
          setId
        );
        
        // Update local card with server ID (if changed, but here we control ID) and mark synced
        await _dbHelper.updateCard(cardId, {'is_synced': 1});
        return newCard;
      } catch (e) {
        print('⚠️  Sheets sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'Card',
          recordId: cardId,
          operation: 'CREATE',
          data: jsonEncode(cardData),
        );
      }
    } else {
      // Queue for sync when online
      await _dbHelper.addToSyncQueue(
        tableName: 'Card',
        recordId: cardId,
        operation: 'CREATE',
        data: jsonEncode(cardData),
      );
    }

    return VocabCard.fromJson(cardData);
  }

  /// Create cards in bulk (Offline-First)
  Future<void> createCardsBulk({
    required List<Map<String, String>> cards,
    required String setId,
  }) async {
    final List<Map<String, dynamic>> cardsToSync = [];

    // Save all to local database first
    for (var i = 0; i < cards.length; i++) {
      final cardId = (DateTime.now().millisecondsSinceEpoch + i).toString();
      final cardData = {
        'card_id': cardId,
        'term': cards[i]['term']!,
        'definition': cards[i]['definition']!,
        'state': 'new',
        'set_id': setId,
        'is_synced': 0,
      };
      await _dbHelper.insertCard(cardData);
      cardsToSync.add(cardData);
    }

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        await _sheetsAdapter.bulkCreateCards(cardsToSync, setId);
        print('✅ Bulk cards synced to Sheets');
        // Mark all as synced
        for (var card in cardsToSync) {
           await _dbHelper.updateCard(card['card_id'], {'is_synced': 1});
        }
      } catch (e) {
        print('⚠️  Bulk sync failed, queued for later: $e');
        // Queue individual items or handle bulk queue?
        // Simple: queue individually
        for (var card in cardsToSync) {
          await _dbHelper.addToSyncQueue(
            tableName: 'Card',
            recordId: card['card_id'],
            operation: 'CREATE',
            data: jsonEncode(card),
          );
        }
      }
    }
  }

  /// Update card (Offline-First)
  Future<VocabCard> updateCard({
    required String cardId,
    required String term,
    required String definition,
    required String state,
  }) async {
    final updateData = {
      'term': term,
      'definition': definition,
      'state': state,
      'is_synced': 0,
    };

    // Update local database first
    await _dbHelper.updateCard(cardId, updateData);
    
    // Get current card set_id
    final currentCard = await _dbHelper.getCardById(cardId);
    final setId = currentCard != null ? currentCard['set_id'] : '';

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        await _sheetsAdapter.updateCard(
          cardId,
          term,
          definition,
          state,
          setId
        );
        
        await _dbHelper.updateCard(cardId, {'is_synced': 1});
        // Return updated card object
         return VocabCard(
          cardId: cardId,
          term: term,
          definition: definition,
          state: state,
          setId: setId,
        );
      } catch (e) {
        print('⚠️  Update sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'Card',
          recordId: cardId,
          operation: 'UPDATE',
          data: jsonEncode(updateData),
        );
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'Card',
        recordId: cardId,
        operation: 'UPDATE',
        data: jsonEncode(updateData),
      );
    }

    final localCard = await _dbHelper.getCardById(cardId);
    return VocabCard.fromJson(localCard!);
  }

  /// Update cards in bulk (Offline-First)
  Future<void> updateCardsBulk({
    required List<Map<String, dynamic>> updates,
  }) async {
    // Update all in local database first
    for (var update in updates) {
      await _dbHelper.updateCard(update['cardId'], {
        'term': update['term'],
        'definition': update['definition'],
        'state': update['state'],
        'is_synced': 0,
      });
    }

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        await _sheetsAdapter.bulkUpdateCards(updates);
        
        // Mark all as synced
        for (var update in updates) {
          await _dbHelper.updateCard(update['cardId'], {'is_synced': 1});
        }
      } catch (e) {
        print('⚠️  Bulk update sync failed, queued for later: $e');
         // Queue individual
        for (var update in updates) {
           await _dbHelper.addToSyncQueue(
            tableName: 'Card',
            recordId: update['cardId'],
            operation: 'UPDATE',
            data: jsonEncode({
              'term': update['term'],
              'definition': update['definition'],
              'state': update['state'],
            }),
          );
        }
      }
    }
  }

  /// Delete card (Offline-First)
  Future<void> deleteCard(String cardId) async {
    // Soft delete in local database
    await _dbHelper.deleteCard(cardId);

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        final result = await _sheetsAdapter.deleteCard(cardId);
        if (result) {
          print('✅ Card deleted from Sheets');
        }
      } catch (e) {
        print('⚠️  Delete sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'Card',
          recordId: cardId,
          operation: 'DELETE',
        );
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'Card',
        recordId: cardId,
        operation: 'DELETE',
      );
    }
  }

  /// Delete cards in bulk (Offline-First)
  Future<void> deleteCardsBulk({required List<String> cardIds}) async {
    // Delete all from local database
    for (var id in cardIds) {
      await _dbHelper.deleteCard(id);
    }

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        // We don't have bulk delete in adapter yet.
        // We can do loop or add bulkDelete to adapter.
        // For now loop is safer as deleteRow changes indices.
        // Actually deleteRow changes indices so loop must be careful (reverse order) or by ID.
        // Adapter `deleteCard` finds by ID so it's safe to call in loop.
        for (var id in cardIds) {
           await _sheetsAdapter.deleteCard(id);
        }
        print('✅ Bulk cards deleted from Sheets');
      } catch (e) {
        print('⚠️  Bulk delete sync failed, queued for later: $e');
        // Queue individual
        for (var id in cardIds) {
           await _dbHelper.addToSyncQueue(
            tableName: 'Card',
            recordId: id,
            operation: 'DELETE',
          );
        }
      }
    }
  }

  /// Fetch vocab count needing to learn (Offline-First)
  // Local-First Strategy
  Future<int> fetchVocabNeedToLearn() async {
    try {
      return await _dbHelper.countCardsNeedToLearn();
    } catch (e) {
      print('⚠️  Error fetching vocab count: $e');
      return 0; // Or -1
    }
  }
}

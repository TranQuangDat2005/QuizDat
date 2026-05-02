import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/set_card.dart';
import 'database_helper.dart';
import 'google_sheets_setcard_adapter.dart';
import 'google_sheets_card_adapter.dart';
import 'config_manager.dart';
import '../constants/app_constants.dart';

class SetService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Connectivity _connectivity = Connectivity();
  final GoogleSheetsSetCardAdapter _sheetsAdapter = GoogleSheetsSetCardAdapter();
  final ConfigManager _config = ConfigManager();

  Future<bool> _hasConnection() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  /// Fetch recent sets (Offline-First)
  // Local-First Strategy but fallback to Remote if empty
  Future<List<SetCard>> fetchRecentSets() async {
    try {
      final localSets = await _dbHelper.getAllSetCards();
      
      if (localSets.isEmpty && await _hasConnection()) {
        try {
          final recentSets = await _sheetsAdapter.getRecentSets();
          // Save to local database
          for (var set in recentSets) {
            final setData = {
              'set_id': set.setId,
              'name': set.name,
              'repository_id': set.repositoryId,
              'last_learned_time': set.lastLearnedTime?.toIso8601String() ?? '',
              'is_synced': 1,
            };
            await _dbHelper.insertSetCard(setData);
          }
          return recentSets;
        } catch (e) {
          print('⚠️  Recent sets fetch failed: $e');
        }
      }

      // Sort by last accessed/modified? 
      // The DB query `getAllSetCards` already orders by `last_modified DESC`.
      
      List<SetCard> sets = localSets.take(6).map((set) => SetCard.fromJson(set)).toList();
      
      // Populate status
      for (var i = 0; i < sets.length; i++) {
        sets[i] = await _populateStatus(sets[i]);
      }
      return sets;
    } catch (e) {
      print('⚠️  Error fetching recent sets: $e');
      return [];
    }
  }

  Future<List<SetCard>> fetchNeedToLearnSets() async {
    try {
      final localSets = await _dbHelper.getAllSetCards(); // Get all to filter in memory
      
      // Convert to objects
      List<SetCard> allSets = localSets.map((s) => SetCard.fromJson(s)).toList();

      // Populate status for ALL sets first
      for (var i = 0; i < allSets.length; i++) {
        allSets[i] = await _populateStatus(allSets[i]);
      }

      // Filter: Only "Đang học" (Started but not finished)
      // Logic: Status is 'Đang học'.
      // If user wants 'Chưa học' too, we can add that, but 'Need to learn' usually implies reviewing active stuff.
      // Based on request: "apply display... based on last learned time if that set is not fully learned"
      // So we include 'Đang học'. 'Chưa học' usually has no last_learned_time anyway.

      final needReviewSets = allSets.where((s) => s.status == 'Đang học').toList();

      // Sort by last_learned_time INT (oldest first? or newest?)
      // Usually "Review" means "Haven't seen in a while" -> Oldest date (smallest timestamp) first.
      // DatabaseHelper already sorts by last_modified DESC, but we want last_learned_time ASC for review?
      // Or DESC if we want to show what I was just working on?
      // "Need to Revise" -> usually oldest.
      // Let's stick to current logic: Oldest learned first.
      needReviewSets.sort((a, b) {
        final aTime = a.lastLearnedTime;
        final bTime = b.lastLearnedTime;
        if (aTime == null) return 1; // Put nulls at end (shouldn't happen for 'Đang học')
        if (bTime == null) return -1;
        return aTime.compareTo(bTime); // Oldest first
      });

      return needReviewSets.take(10).toList();
    } catch (e) {
      print('⚠️  Error fetching need to learn sets: $e');
      return [];
    }
  }

  Future<SetCard> _populateStatus(SetCard set) async {
    final stats = await _dbHelper.getSetStatistics(set.setId);
    final total = (stats['new'] ?? 0) + (stats['learning'] ?? 0) + (stats['learned'] ?? 0);
    final learned = stats['learned'] ?? 0;
    
    String status = "Chưa học";
    if (total == 0) {
      status = "Chưa học";
    } else if (learned == total) {
      status = "Đã học";
    } else if (set.lastLearnedTime != null) {
      // Has started learning (has timestamp) and not finished
      status = "Đang học";
    } else {
      // Has cards but no timestamp? Maybe just created/imported.
      // If any card is 'learning' or 'learned', it's 'Đang học' effectively?
      // But strictly following user Request: "last_meaned_time" check.
      // Let's fallback: if any progress, it's 'Đang học'.
      if ((stats['learning'] ?? 0) > 0 || (stats['learned'] ?? 0) > 0) {
        status = "Đang học";
      }
    }

    return set.copyWith(status: status);
  }

  /// Fetch sets by repository ID (Offline-First)
  // Local-First Strategy but fallback to Remote if empty
  Future<List<SetCard>> fetchSetsByRepoId(String repoId) async {
    try {
      final localSets = await _dbHelper.getSetCardsByRepositoryId(repoId);
      
      if (localSets.isEmpty && await _hasConnection()) {
        try {
          final sets = await _sheetsAdapter.getSetCardsByRepoId(repoId);
          for (var set in sets) {
            final setData = {
              'set_id': set.setId,
              'name': set.name,
              'repository_id': set.repositoryId,
              'last_learned_time': set.lastLearnedTime?.toIso8601String() ?? '',
              'is_synced': 1,
            };
            final existing = await _dbHelper.getSetCardById(set.setId);
            if (existing == null) await _dbHelper.insertSetCard(setData);
          }
          return sets;
        } catch (e) {
           print('⚠️  Sets by repo fetch failed: $e');
        }
      }

      List<SetCard> sets = localSets.map((set) => SetCard.fromJson(set)).toList();
      for (var i = 0; i < sets.length; i++) {
        sets[i] = await _populateStatus(sets[i]);
      }
      return sets;
    } catch (e) {
      print('⚠️  Error fetching sets by repo: $e');
      return [];
    }
  }

  /// Create set card (Offline-First)
  Future<SetCard> createSetCard(String name, String repositoryId) async {
    final setId = DateTime.now().millisecondsSinceEpoch.toString();
    
    final setData = {
      'set_id': setId,
      'name': name,
      'repository_id': repositoryId,
      'last_learned_time': '',
      'is_synced': 0,
    };

    // Save to local database first
    await _dbHelper.insertSetCard(setData);

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        final newSet = await _sheetsAdapter.createSetCard(setId, name, repositoryId);
        
        // Mark as synced
        await _dbHelper.updateSetCard(setId, {'is_synced': 1});
        return newSet;
      } catch (e) {
        print('⚠️  Sheets sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'SetCard',
          recordId: setId,
          operation: 'CREATE',
          data: jsonEncode(setData),
        );
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'SetCard',
        recordId: setId,
        operation: 'CREATE',
        data: jsonEncode(setData),
      );
    }

    return SetCard.fromJson(setData);
  }

  /// Update set card (Offline-First)
  Future<SetCard> updateSetCard(
    String setId, {
    String? name,
    DateTime? lastLearnedTime,
  }) async {
    Map<String, dynamic> updateData = {'is_synced': 0};
    
    if (name != null) updateData['name'] = name;
    if (lastLearnedTime != null) {
      updateData['last_learned_time'] = lastLearnedTime.toIso8601String();
    }

    // Update local database first
    await _dbHelper.updateSetCard(setId, updateData);
    
    // Get current data to ensure we have all fields for adapter
    final currentSet = await _dbHelper.getSetCardById(setId);
    if (currentSet == null) throw Exception('Set not found locally');

    // Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        await _sheetsAdapter.updateSetCard(
          setId, 
          name ?? currentSet['name'], 
          currentSet['repository_id'], 
          lastLearnedTime ?? (currentSet['last_learned_time'] != null && currentSet['last_learned_time'].isNotEmpty ? DateTime.parse(currentSet['last_learned_time']) : null)
        );
        
        await _dbHelper.updateSetCard(setId, {'is_synced': 1});
      } catch (e) {
        print('⚠️  Sheets update failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'SetCard',
          recordId: setId,
          operation: 'UPDATE',
          data: jsonEncode(updateData),
        );
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'SetCard',
        recordId: setId,
        operation: 'UPDATE',
        data: jsonEncode(updateData),
      );
    }

    final localSet = await _dbHelper.getSetCardById(setId);
    return SetCard.fromJson(localSet!);
  }

  /// Delete set card (Offline-First)
  Future<bool> deleteSetCard(String setId) async {
    // 1. Local delete (Hard delete via DatabaseHelper which cascades to cards locally)
    await _dbHelper.deleteSetCard(setId);

    // 2. Try to sync with Sheets if online
    if (await _hasConnection()) {
      try {
        // Cascade delete in Sheets: Cards -> SetCard
        final GoogleSheetsCardAdapter cardAdapter = GoogleSheetsCardAdapter();
        await cardAdapter.deleteCardsBySetIds([setId]);
        
        final result = await _sheetsAdapter.deleteSetCard(setId);
        if (result) {
          print('✅ SetCard and its cards deleted from Sheets');
          return true;
        }
      } catch (e) {
        print('⚠️  Delete sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'SetCard',
          recordId: setId,
          operation: 'DELETE',
        );
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'SetCard',
        recordId: setId,
        operation: 'DELETE',
      );
    }

    return true;
  }

  /// Bulk create set cards (Offline-First)
  Future<void> bulkCreateSetCards(List<SetCard> setCards) async {
    for (var set in setCards) {
      final setData = {
        'set_id': set.setId,
        'name': set.name,
        'repository_id': set.repositoryId,
        'last_learned_time': set.lastLearnedTime?.toIso8601String() ?? '',
        'is_synced': 0,
      };
      await _dbHelper.insertSetCard(setData);
    }

    if (await _hasConnection()) {
      try {
        await _sheetsAdapter.bulkCreateSetCards(setCards);
        // Mark all as synced
        for (var set in setCards) {
          await _dbHelper.updateSetCard(set.setId, {'is_synced': 1});
        }
      } catch (e) {
        print('⚠️  Bulk create failed: $e');
        // Add to sync queue individually? Or implement bulk sync queue?
        // simple: add individual sync items
        for (var set in setCards) {
           await _dbHelper.addToSyncQueue(
            tableName: 'SetCard',
            recordId: set.setId,
            operation: 'CREATE',
            data: jsonEncode({
              'set_id': set.setId,
              'name': set.name,
              'repository_id': set.repositoryId,
              'last_learned_time': set.lastLearnedTime?.toIso8601String() ?? '',
            }),
          );
        }
      }
    }
  }

  /// Bulk update set cards (Offline-First)
  Future<void> bulkUpdateSetCards(List<SetCard> setCards) async {
    for (var set in setCards) {
      final updateData = {
        'name': set.name,
        'last_learned_time': set.lastLearnedTime?.toIso8601String() ?? '',
        'is_synced': 0,
      };
      await _dbHelper.updateSetCard(set.setId, updateData);
    }

    if (await _hasConnection()) {
      try {
        await _sheetsAdapter.bulkUpdateSetCards(setCards);
        // Mark as synced
        for (var set in setCards) {
          await _dbHelper.updateSetCard(set.setId, {'is_synced': 1});
        }
      } catch (e) {
         print('⚠️  Bulk update failed: $e');
         // Add to sync queue
         for (var set in setCards) {
           await _dbHelper.addToSyncQueue(
            tableName: 'SetCard',
            recordId: set.setId,
            operation: 'UPDATE',
            data: jsonEncode({
              'name': set.name,
              'last_learned_time': set.lastLearnedTime?.toIso8601String() ?? '',
            }),
          );
         }
      }
    }
  }
}

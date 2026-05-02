import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/repository.dart';
import 'database_helper.dart';
import 'google_sheets_repository_adapter.dart';
import 'google_sheets_setcard_adapter.dart';
import 'google_sheets_card_adapter.dart';
import 'config_manager.dart';

class RepositoryService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Connectivity _connectivity = Connectivity();
  final GoogleSheetsRepositoryAdapter _sheetsAdapter = GoogleSheetsRepositoryAdapter();
  final GoogleSheetsSetCardAdapter _setCardAdapter = GoogleSheetsSetCardAdapter();
  final GoogleSheetsCardAdapter _cardAdapter = GoogleSheetsCardAdapter();
  final ConfigManager _config = ConfigManager();

  Future<bool> _hasConnection() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  /// Get all repositories (Offline-First with Google Sheets)
  Future<List<Repository>> getAllRepositories() async {
    try {
      // Check if configured
      if (await _config.isConfigured() && await _hasConnection()) {
        final repos = await _sheetsAdapter.getAllRepositories();
        
        // Save to local database
        for (var repo in repos) {
          final repoData = {
            'repository_id': repo.repositoryId,
            'name': repo.name,
            'description': repo.description,
            'is_synced': 1,
          };
          
          final existing = await _dbHelper.getRepositoryById(repo.repositoryId);
          if (existing == null) {
            await _dbHelper.insertRepository(repoData);
          } else {
            await _dbHelper.updateRepository(repo.repositoryId, repoData);
          }
        }
        
        return repos;
      }
      
      // Fallback to local database
      print('⚠️  Using offline data for repositories');
      final localRepos = await _dbHelper.getAllRepositories();
      return localRepos.map((repo) => Repository.fromJson(repo)).toList();
    } catch (e) {
      print('⚠️  Google Sheets failed, using local database: $e');
      final localRepos = await _dbHelper.getAllRepositories();
      return localRepos.map((repo) => Repository.fromJson(repo)).toList();
    }
  }

  /// Create repository (Offline-First with Google Sheets)
  Future<Repository> createRepository(String name, String description) async {
    final repoId = DateTime.now().millisecondsSinceEpoch.toString();
    
    final repoData = {
      'repository_id': repoId,
      'name': name,
      'description': description,
      'is_synced': 0,
    };

    // Save to local database first
    await _dbHelper.insertRepository(repoData);

    // Try to sync with Google Sheets if configured and online
    if (await _config.isConfigured() && await _hasConnection()) {
      try {
        await _sheetsAdapter.createRepository(repoId, name, description);
        
        // Mark as synced
        await _dbHelper.updateRepository(repoId, {'is_synced': 1});
        
        return Repository(
          repositoryId: repoId,
          name: name,
          description: description,
        );
      } catch (e) {
        print('⚠️  Google Sheets sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'Repository',
          recordId: repoId,
          operation: 'CREATE',
          data: jsonEncode(repoData),
        );
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'Repository',
        recordId: repoId,
        operation: 'CREATE',
        data: jsonEncode(repoData),
      );
    }

    return Repository.fromJson(repoData);
  }

  /// Update repository (Offline-First with Google Sheets)
  Future<Repository> updateRepository(
    String id,
    String name,
    String description,
  ) async {
    final updateData = {
      'name': name,
      'description': description,
      'is_synced': 0,
    };

    // Update local database first
    await _dbHelper.updateRepository(id, updateData);

    // Try to sync with Google Sheets if configured and online
    if (await _config.isConfigured() && await _hasConnection()) {
      try {
        await _sheetsAdapter.updateRepository(id, name, description);
        await _dbHelper.updateRepository(id, {'is_synced': 1});
        
        return Repository(
          repositoryId: id,
          name: name,
          description: description,
        );
      } catch (e) {
        print('⚠️  Update sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'Repository',
          recordId: id,
          operation: 'UPDATE',
          data: jsonEncode(updateData),
        );
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'Repository',
        recordId: id,
        operation: 'UPDATE',
        data: jsonEncode(updateData),
      );
    }

    final localRepo = await _dbHelper.getRepositoryById(id);
    return Repository.fromJson(localRepo!);
  }

  /// Delete repository (Offline-First with Google Sheets)
  Future<bool> deleteRepository(String id) async {
    // 1. Fetch children BEFORE local hard delete so we know what needs to be deleted remotely
    final sets = await _dbHelper.getSetCardsByRepositoryId(id);
    final setIds = sets.map((s) => s['set_id'].toString()).toList();

    // 2. Hard delete in local database (this automatically cascades to local SetCards and Cards!)
    await _dbHelper.deleteRepository(id);

    // 3. Try to sync with Google Sheets if configured and online
    if (await _config.isConfigured() && await _hasConnection()) {
      try {
        // Cascade delete in Sheets: Cards -> SetCards -> Repository
        if (setIds.isNotEmpty) {
           await _cardAdapter.deleteCardsBySetIds(setIds);
           await _setCardAdapter.deleteSetCardsByRepoIds([id]);
        }
        await _sheetsAdapter.deleteRepository(id);
        print('✅ Repository and its children deleted from Google Sheets');
        return true;
      } catch (e) {
        print('⚠️  Delete sync failed, queued for later: $e');
        await _dbHelper.addToSyncQueue(
          tableName: 'Repository',
          recordId: id,
          operation: 'DELETE',
        );
        // Note: in a fully offline-first app, we'd also queue deletes for the children.
        // But since we can't easily queue "bulk delete by set ID", we rely on the parent queue.
        // SyncService would need to be updated to handle cascading deletes if offline,
        // or we just accept that if they delete offline, it might orphan children on sheets.
        // For now, doing it inline when online is a huge improvement.
        if (setIds.isNotEmpty) {
           for (var setId in setIds) {
             await _dbHelper.addToSyncQueue(tableName: 'SetCard', recordId: setId, operation: 'DELETE');
             // Optionally queue cards, but that might be hundreds of items.
           }
        }
      }
    } else {
      await _dbHelper.addToSyncQueue(
        tableName: 'Repository',
        recordId: id,
        operation: 'DELETE',
      );
      if (setIds.isNotEmpty) {
         for (var setId in setIds) {
           await _dbHelper.addToSyncQueue(tableName: 'SetCard', recordId: setId, operation: 'DELETE');
         }
      }
    }

    return true;
  }
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

/// Manages user-provided configuration (storage mode, Google Sheets credentials)
class ConfigManager {
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;
  ConfigManager._internal();

  final _storage = const FlutterSecureStorage();

  // Storage keys
  static const _keyCredentials = 'google_credentials';
  static const _keySheetId = 'google_sheet_id';
  static const _keyConfigured = 'is_configured';
  static const _keyStorageMode = 'storage_mode';

  // Storage mode values
  static const storageModeGoogleSheets = 'google_sheets';
  static const storageModeLocal = 'local';

  /// Check if user has configured their credentials
  Future<bool> isConfigured() async {
    final configured = await _storage.read(key: _keyConfigured);
    return configured == 'true';
  }

  /// Save Google credentials JSON
  Future<void> saveCredentials(String credentialsJson) async {
    await _storage.write(key: _keyCredentials, value: credentialsJson);
  }

  /// Get stored credentials as JSON string
  Future<String?> getCredentials() async {
    return await _storage.read(key: _keyCredentials);
  }

  /// Get credentials as Map
  Future<Map<String, dynamic>?> getCredentialsMap() async {
    final json = await getCredentials();
    if (json == null) return null;
    return jsonDecode(json);
  }

  /// Save Google Sheet ID
  Future<void> saveSheetId(String sheetId) async {
    await _storage.write(key: _keySheetId, value: sheetId);
  }

  /// Get stored Sheet ID
  Future<String?> getSheetId() async {
    return await _storage.read(key: _keySheetId);
  }

  /// Mark configuration as complete
  Future<void> markConfigured() async {
    await _storage.write(key: _keyConfigured, value: 'true');
  }

  /// Clear all configuration (for logout or reset)
  Future<void> clearConfiguration() async {
    await _storage.deleteAll();
  }

  /// Validate credentials JSON format
  bool validateCredentials(String credentialsJson) {
    try {
      final Map<String, dynamic> data = jsonDecode(credentialsJson);
      
      // Check for required fields from Service Account JSON
      return data.containsKey('type') &&
          data.containsKey('project_id') &&
          data.containsKey('private_key_id') &&
          data.containsKey('private_key') &&
          data.containsKey('client_email') &&
          data['type'] == 'service_account';
    } catch (e) {
      return false;
    }
  }

  /// Validate Sheet ID format (basic check)
  bool validateSheetId(String sheetId) {
    // Google Sheet IDs are typically 44 characters
    return sheetId.trim().isNotEmpty && sheetId.length > 20;
  }

  /// Save storage mode preference
  Future<void> saveStorageMode(String mode) async {
    await _storage.write(key: _keyStorageMode, value: mode);
  }

  /// Get storage mode preference (null if not set yet)
  Future<String?> getStorageMode() async {
    return await _storage.read(key: _keyStorageMode);
  }

  /// Returns true if user chose local SQLite storage
  Future<bool> isLocalMode() async {
    final mode = await getStorageMode();
    return mode == storageModeLocal;
  }

  /// Get service account email from credentials
  Future<String?> getServiceAccountEmail() async {
    final creds = await getCredentialsMap();
    return creds?['client_email'];
  }
}

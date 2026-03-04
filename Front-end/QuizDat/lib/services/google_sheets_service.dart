import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'config_manager.dart';
import 'dart:convert';

/// Service for direct Google Sheets API access using user-provided credentials
class GoogleSheetsService {
  static final GoogleSheetsService _instance = GoogleSheetsService._internal();
  factory GoogleSheetsService() => _instance;
  GoogleSheetsService._internal();

  final ConfigManager _config = ConfigManager();
  
  sheets.SheetsApi? _sheetsApi;
  String? _currentSheetId;

  /// Initialize the Sheets API client with user credentials
  Future<bool> initialize() async {
    try {
      print('📝 Initializing Google Sheets service...');
      
      final credentialsJson = await _config.getCredentials();
      final sheetId = await _config.getSheetId();
      
      print('📋 Credentials loaded: ${credentialsJson != null ? "✅" : "❌"}');
      print('📋 Sheet ID loaded: ${sheetId != null ? "✅ ($sheetId)" : "❌"}');

      if (credentialsJson == null || sheetId == null) {
        print('❌ Missing credentials or sheet ID');
        return false;
      }

      print('🔐 Parsing credentials...');
      final credentials = ServiceAccountCredentials.fromJson(
        jsonDecode(credentialsJson),
      );
      print('✅ Credentials parsed. Service account: ${credentials.email}');

      print('🔗 Creating authenticated client...');
      final client = await clientViaServiceAccount(
        credentials,
        [sheets.SheetsApi.spreadsheetsScope],
      );
      print('✅ Client authenticated');

      _sheetsApi = sheets.SheetsApi(client);
      _currentSheetId = sheetId;
      print('✅ Google Sheets API initialized successfully');
      return true;
    } catch (e) {
      print('❌ Failed to initialize Google Sheets API: $e');
      return false;
    }
  }

  /// Get current sheet ID
  String? get sheetId => _currentSheetId;

  /// Check if API is ready
  bool get isReady => _sheetsApi != null && _currentSheetId != null;

  /// Get numeric Sheet ID by name
  Future<int?> getSheetIdByName(String sheetName) async {
    if (!isReady) await initialize();
    if (!isReady) throw Exception('Google Sheets API not initialized');

    try {
      final spreadsheet = await _sheetsApi!.spreadsheets.get(_currentSheetId!);
      final sheet = spreadsheet.sheets?.firstWhere(
        (s) => s.properties?.title == sheetName,
        orElse: () => sheets.Sheet(),
      );
      return sheet?.properties?.sheetId;
    } catch (e) {
      print('❌ Error getting sheet ID for $sheetName: $e');
      return null;
    }
  }

  /// Test connection to Google Sheets
  Future<bool> testConnection() async {
    print('🧪 Testing Google Sheets connection...');
    print('📊 isReady: $isReady');
    
    if (!isReady) {
      print('⚠️  API not ready, initializing...');
      final initialized = await initialize();
      if (!initialized) {
        print('❌ Initialization failed');
        return false;
      }
    }

    try {
      print('📡 Attempting to fetch spreadsheet metadata...');
      print('📋 Using Sheet ID: $_currentSheetId');
      final spreadsheet = await _sheetsApi!.spreadsheets.get(_currentSheetId!);
      print('✅ Connection successful!');
      print('📄 Spreadsheet title: ${spreadsheet.properties?.title}');
      return true;
    } catch (e) {
      print('❌ Connection test failed: $e');
      return false;
    }
  }

  /// Get all values from a specific sheet
  Future<List<List<dynamic>>> getSheetValues(String sheetName) async {
    if (!isReady) await initialize();
    if (!isReady) throw Exception('Google Sheets API not initialized');

    try {
      final response = await _sheetsApi!.spreadsheets.values.get(
        _currentSheetId!,
        sheetName,
      );
      return response.values ?? [];
    } catch (e) {
      print('❌ Error reading sheet $sheetName: $e');
      rethrow;
    }
  }

  /// Get sheet values as a List of Maps (using first row as header)
  Future<List<Map<String, String>>> getSheetMaps(String sheetName) async {
    try {
      final rows = await getSheetValues(sheetName);
      
      if (rows.isEmpty) return [];
      
      final headers = rows[0].map((e) => e.toString().trim()).toList();
      final dataRows = rows.skip(1).toList();
      
      return dataRows.map((row) {
        final map = <String, String>{};
        for (var i = 0; i < headers.length; i++) {
          final header = headers[i];
          // Use empty string if row doesn't have value for this column
          final value = i < row.length ? row[i].toString() : '';
          map[header] = value;
        }
        return map;
      }).toList();
    } catch (e) {
      print('❌ Error reading sheet maps for $sheetName: $e');
      rethrow;
    }
  }

  /// Append rows to a sheet
  Future<void> appendRows(String sheetName, List<List<dynamic>> rows) async {
    if (!isReady) await initialize();
    if (!isReady) throw Exception('Google Sheets API not initialized');

    try {
      final valueRange = sheets.ValueRange()..values = rows;
      
      await _sheetsApi!.spreadsheets.values.append(
        valueRange,
        _currentSheetId!,
        sheetName,
        valueInputOption: 'RAW',
      );
    } catch (e) {
      print('❌ Error appending rows to $sheetName: $e');
      rethrow;
    }
  }

  /// Update specific range
  Future<void> updateRange(
    String sheetName,
    String range,
    List<List<dynamic>> values,
  ) async {
    if (!isReady) await initialize();
    if (!isReady) throw Exception('Google Sheets API not initialized');

    try {
      final valueRange = sheets.ValueRange()..values = values;
      
      await _sheetsApi!.spreadsheets.values.update(
        valueRange,
        _currentSheetId!,
        '$sheetName!$range',
        valueInputOption: 'RAW',
      );
    } catch (e) {
      print('❌ Error updating range in $sheetName: $e');
      rethrow;
    }
  }

  /// Delete row by row number
  Future<void> deleteRow(String sheetName, int rowIndex) async {
    if (!isReady) await initialize();
    if (!isReady) throw Exception('Google Sheets API not initialized');

    try {
      // Get sheet ID first
      final spreadsheet = await _sheetsApi!.spreadsheets.get(_currentSheetId!);
      final sheet = spreadsheet.sheets?.firstWhere(
        (s) => s.properties?.title == sheetName,
      );
      
      if (sheet == null) throw Exception('Sheet $sheetName not found');

      final request = sheets.Request()
        ..deleteDimension = (sheets.DeleteDimensionRequest()
          ..range = (sheets.DimensionRange()
            ..sheetId = sheet.properties!.sheetId
            ..dimension = 'ROWS'
            ..startIndex = rowIndex
            ..endIndex = rowIndex + 1));

      final batchRequest = sheets.BatchUpdateSpreadsheetRequest()
        ..requests = [request];

      await _sheetsApi!.spreadsheets.batchUpdate(
        batchRequest,
        _currentSheetId!,
      );
    } catch (e) {
      print('❌ Error deleting row from $sheetName: $e');
      rethrow;
    }
  }

  /// Execute a batch update request
  Future<void> batchUpdate(List<sheets.Request> requests) async {
    if (!isReady) await initialize();
    if (!isReady) throw Exception('Google Sheets API not initialized');

    try {
      final batchRequest = sheets.BatchUpdateSpreadsheetRequest()
        ..requests = requests;

      await _sheetsApi!.spreadsheets.batchUpdate(
        batchRequest,
        _currentSheetId!,
      );
    } catch (e) {
      print('❌ Error executing batch update: $e');
      rethrow;
    }
  }

  /// Create sheet structure if not exists
  Future<void> createSheetStructure() async {
    if (!isReady) await initialize();
    if (!isReady) throw Exception('Google Sheets API not initialized');

    try {
      final spreadsheet = await _sheetsApi!.spreadsheets.get(_currentSheetId!);
      final existingSheets = spreadsheet.sheets?.map((s) => s.properties?.title).toList() ?? [];

      final requiredSheets = ['Repository', 'SetCard', 'Card', 'Calendar'];
      final headers = {
        'Repository': ['repository_id', 'name', 'description'],
        'SetCard': ['set_id', 'name', 'repository_id', 'last_learned_time'],
        'Card': ['card_id', 'term', 'definition', 'state', 'set_id'],
        'Calendar': ['calendar_id', 'title', 'description', 'date', 'type', 'is_done', 'created_at'],
      };

      for (final sheetName in requiredSheets) {
        if (!existingSheets.contains(sheetName)) {
          // Create sheet
          final request = sheets.Request()
            ..addSheet = (sheets.AddSheetRequest()
              ..properties = (sheets.SheetProperties()..title = sheetName));

          final batchRequest = sheets.BatchUpdateSpreadsheetRequest()
            ..requests = [request];

          await _sheetsApi!.spreadsheets.batchUpdate(
            batchRequest,
            _currentSheetId!,
          );

          // Add headers
          await appendRows(sheetName, [headers[sheetName]!]);
        }
      }
    } catch (e) {
      print('❌ Error creating sheet structure: $e');
      rethrow;
    }
  }

  /// Clear API client (for logout)
  void dispose() {
    _sheetsApi = null;
    _currentSheetId = null;
  }
}

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/config_manager.dart';
import '../services/google_sheets_service.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_sidebar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ConfigManager _config = ConfigManager();
  final GoogleSheetsService _sheets = GoogleSheetsService();
  final TextEditingController _sheetIdController = TextEditingController();

  bool _isConfigured = false;
  bool _isTesting = false;
  String? _serviceAccountEmail;
  String? _credentialsFileName;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  @override
  void dispose() {
    _sheetIdController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentConfig() async {
    final configured = await _config.isConfigured();
    final sheetId = await _config.getSheetId();
    final email = await _config.getServiceAccountEmail();

    setState(() {
      _isConfigured = configured;
      _serviceAccountEmail = email;
      if (sheetId != null) {
        _sheetIdController.text = sheetId;
      }
    });
  }

  Future<void> _pickCredentialsFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null) return;

      final file = File(result.files.single.path!);
      final contents = await file.readAsString();

      if (!_config.validateCredentials(contents)) {
        if (!mounted) return;
        _showSnackBar('File JSON không hợp lệ. Vui lòng chọn file credentials.json từ Google Cloud.', Colors.red);
        return;
      }

      await _config.saveCredentials(contents);
      setState(() {
        _credentialsFileName = result.files.single.name;
      });
      
      if (!mounted) return;
      _showSnackBar('✅ Đã tải credentials thành công!', Colors.green);
      _loadCurrentConfig();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Lỗi đọc file: $e', Colors.red);
    }
  }

  Future<void> _saveSheetId() async {
    final sheetId = _sheetIdController.text.trim();
    
    if (!_config.validateSheetId(sheetId)) {
      _showSnackBar('Sheet ID không hợp lệ', Colors.red);
      return;
    }

    await _config.saveSheetId(sheetId);
    _showSnackBar('✅ Đã lưu Sheet ID!', Colors.green);
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);

    try {
      final success = await _sheets.testConnection();
      
      if (!mounted) return;

      if (success) {
        await _config.markConfigured();
        _showSnackBar('✅ Kết nối thành công!', Colors.green);
        setState(() => _isConfigured = true);
      } else {
        _showSnackBar('❌ Kết nối thất bại. Kiểm tra lại credentials và Sheet ID.', Colors.red);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('❌ Lỗi: $e', Colors.red);
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _createSheetStructure() async {
    try {
      await _sheets.createSheetStructure();
      if (!mounted) return;
      _showSnackBar('✅ Đã tạo cấu trúc Sheet!', Colors.green);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('❌ Lỗi tạo cấu trúc: $e', Colors.red);
    }
  }

  Future<void> _clearConfiguration() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text(
            'Xác nhận xóa',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Bạn có chắc muốn xóa cấu hình? Bạn sẽ cần setup lại từ đầu.',
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Hủy',
                style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Xóa'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _config.clearConfiguration();
      _sheets.dispose();
      _sheetIdController.clear();
      setState(() {
        _isConfigured = false;
        _serviceAccountEmail = null;
        _credentialsFileName = null;
      });
      if (!mounted) return;
      _showSnackBar('Đã xóa cấu hình', Colors.orange);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Row(
            children: [
              Icon(Icons.help_outline, size: 28, color: theme.iconTheme.color),
              const SizedBox(width: 12),
              Text('Hướng dẫn setup', style: theme.textTheme.titleLarge),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Để sử dụng Google Sheet riêng của bạn:',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  _buildHelpStep(
                    '1',
                    'Tạo Google Cloud Project',
                    'Vào console.cloud.google.com → Tạo project mới',
                  ),
                  _buildHelpStep(
                    '2',
                    'Enable Google Sheets API',
                    'APIs & Services → Library → Tìm "Google Sheets API" → Enable',
                  ),
                  _buildHelpStep(
                    '3',
                    'Tạo Service Account',
                    'IAM & Admin → Service Accounts → Create → Download JSON key',
                  ),
                  _buildHelpStep(
                    '4',
                    'Tạo Google Sheet',
                    'sheets.google.com → Tạo sheet mới → Copy ID từ URL',
                  ),
                  _buildHelpStep(
                    '5',
                    'Share Sheet',
                    'Share với email service account (trong file credentials.json)',
                  ),
                  _buildHelpStep(
                    '6',
                    'Cấu hình App',
                    'Upload credentials.json + nhập Sheet ID → Test kết nối',
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.blue.withOpacity(0.2) : Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Xem hướng dẫn chi tiết trong tài liệu',
                            style: TextStyle(color: isDark ? Colors.blue[200] : Colors.blue[900], fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHelpStep(String number, String title, String description) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.iconTheme.color ?? Colors.black,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: theme.scaffoldBackgroundColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        iconTheme: theme.iconTheme,
        title: Text(
          'CÀI ĐẶT',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline, color: theme.iconTheme.color),
            onPressed: _showHelp,
          ),
        ],
      ),
      drawer: const AppSidebar(currentRoute: '/settings'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Theme Toggle
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    return SwitchListTile(
                      title: const Text(
                        'Chế độ tối (Dark Mode)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      secondary: Icon(
                        themeProvider.isDarkMode
                            ? Icons.dark_mode
                            : Icons.light_mode,
                      ),
                      value: themeProvider.isDarkMode,
                      activeColor: Colors.white,
                      activeTrackColor: Colors.grey,
                      onChanged: (value) {
                        themeProvider.toggleTheme(value);
                      },
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Status Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _isConfigured 
                        ? (isDark ? Colors.green.withOpacity(0.1) : Colors.green[50])
                        : (isDark ? Colors.orange.withOpacity(0.1) : Colors.orange[50]),
                    border: Border.all(
                      color: _isConfigured ? Colors.green : Colors.orange,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isConfigured ? Icons.check_circle : Icons.warning,
                        color: _isConfigured ? Colors.green : Colors.orange,
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isConfigured ? 'Đã cấu hình' : 'Chưa cấu hình',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _isConfigured 
                                    ? (isDark ? Colors.green[200] : Colors.green[900])
                                    : (isDark ? Colors.orange[200] : Colors.orange[900]),
                              ),
                            ),
                            if (_serviceAccountEmail != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _serviceAccountEmail!,
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Credentials Upload
                Text(
                  '1. Upload Credentials',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickCredentialsFile,
                  icon: Icon(Icons.upload_file, color: theme.iconTheme.color),
                  label: Text(
                    _credentialsFileName ?? 'Chọn file credentials.json',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.dividerColor),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Sheet ID Input
                Text(
                  '2. Nhập Google Sheet ID',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _sheetIdController,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Paste Sheet ID từ URL...',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: theme.dividerColor)),
                    suffixIcon: Icon(Icons.content_paste, color: theme.iconTheme.color),
                  ),
                  onChanged: (_) => _saveSheetId(),
                ),
                
                const SizedBox(height: 32),
                
                // Test Connection
                Text(
                  '3. Kiểm tra kết nối',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.wifi_find),
                  label: Text(_isTesting ? 'Đang kiểm tra...' : 'Test kết nối'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor, // Use primary color instead of black
                    foregroundColor: theme.colorScheme.onPrimary,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                
                if (_isConfigured) ...[
                  const SizedBox(height: 24),
                  
                  // Create Structure
                  OutlinedButton.icon(
                    onPressed: _createSheetStructure,
                    icon: const Icon(Icons.table_chart, color: Colors.blue),
                    label: const Text('Tạo cấu trúc Sheet', style: TextStyle(color: Colors.blue)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.blue.withOpacity(0.5)),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Clear Config
                  OutlinedButton.icon(
                    onPressed: _clearConfiguration,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Xóa cấu hình', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.withOpacity(0.5)),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

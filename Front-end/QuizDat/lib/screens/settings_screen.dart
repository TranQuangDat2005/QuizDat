import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/config_manager.dart';
import '../services/google_sheets_service.dart';
import '../services/sm2_service.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_sidebar.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ConfigManager _config = ConfigManager();
  final GoogleSheetsService _sheets = GoogleSheetsService();
  final SM2Service _sm2 = SM2Service();
  final TextEditingController _sheetIdController = TextEditingController();

  bool _isConfigured = false;
  bool _isTesting = false;
  String? _serviceAccountEmail;
  String? _credentialsFileName;
  String? _storageMode;

  // SM-2 limits
  int _sm2NewLimit = 20;
  int _sm2ReviewLimit = 200;
  bool _sm2BuryRelated = true;

  // Anki algorithm params
  double _baseEase = 2.5;
  double _easyBonus = 1.3;
  double _lapseInterval = 0.5;
  double _graduatingInterval = 1.0;
  double _easyInterval = 4.0;

  bool get _isLocalMode => _storageMode == ConfigManager.storageModeLocal;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
    _loadSm2Limits();
    _loadAnkiParams();
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
    final mode = await _config.getStorageMode();

    setState(() {
      _isConfigured = configured;
      _serviceAccountEmail = email;
      _storageMode = mode;
      if (sheetId != null) {
        _sheetIdController.text = sheetId;
      }
    });
  }

  Future<void> _loadSm2Limits() async {
    final limits = await _sm2.getLimits();
    final bury = await _sm2.getBuryRelated();
    if (!mounted) return;
    setState(() {
      _sm2NewLimit = limits.newLimit;
      _sm2ReviewLimit = limits.reviewLimit;
      _sm2BuryRelated = bury;
    });
  }

  Future<void> _saveSm2Limits() async {
    await _sm2.saveLimits(newLimit: _sm2NewLimit, reviewLimit: _sm2ReviewLimit);
    await _sm2.setBuryRelated(_sm2BuryRelated);
  }

  Future<void> _loadAnkiParams() async {
    final db = _sm2.db;
    final bE = await db.getBaseEase();
    final eB = await db.getEasyBonus();
    final lI = await db.getLapseInterval();
    final gI = await db.getGraduatingInterval();
    final eI = await db.getEasyInterval();
    if (!mounted) return;
    setState(() {
      _baseEase = bE;
      _easyBonus = eB;
      _lapseInterval = lI;
      _graduatingInterval = gI;
      _easyInterval = eI;
    });
  }

  Future<void> _saveAnkiParam(String key, double value) async {
    final db = _sm2.db;
    await db.setAnkiParam(key, value);
    _loadAnkiParams();
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
        _storageMode = null;
      });
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/setup');
    }
  }

  Future<void> _changeStorageMode() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text(
            'Đổi phương thức lưu trữ',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Điều này sẽ xóa cấu hình hiện tại và đưa bạn về trang setup. Bạn có chắc không?',
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Hủy', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
              child: const Text('Tiếp tục'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _config.clearConfiguration();
      _sheets.dispose();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/setup');
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
                // Theme Style Selector & Text Scale
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 3-way theme selector
                        Text(
                          'Giao diện',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'light',
                                label: Text('Sáng'),
                              ),
                              ButtonSegment(
                                value: 'dark',
                                label: Text('Tối'),
                              ),
                              ButtonSegment(
                                value: 'custom',
                                label: Text('Tùy chỉnh'),
                              ),
                            ],
                            selected: {themeProvider.themeStyle},
                            onSelectionChanged: (Set<String> selected) {
                              themeProvider.setThemeStyle(selected.first);
                            },
                            style: ButtonStyle(
                              visualDensity: VisualDensity.comfortable,
                            ),
                          ),
                        ),

                        // Custom color pickers (only shown in custom mode)
                        if (themeProvider.isCustomMode) ...[
                          const SizedBox(height: 20),
                          Text(
                            'Tùy chỉnh màu sắc',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: theme.dividerColor),
                            ),
                            child: Column(
                              children: [
                                _buildColorRow('Màu chính (Primary)', 'primary', themeProvider.customPrimary, themeProvider),
                                const SizedBox(height: 12),
                                _buildColorRow('Màu nền (Background)', 'background', themeProvider.customBackground, themeProvider),
                                const SizedBox(height: 12),
                                _buildColorRow('Màu chữ (Text)', 'text', themeProvider.customText, themeProvider),
                                const SizedBox(height: 12),
                                _buildColorRow('Màu thẻ (Card)', 'card', themeProvider.customCard, themeProvider),
                                const SizedBox(height: 12),
                                _buildColorRow('Màu nhấn (Accent)', 'accent', themeProvider.customAccent, themeProvider),
                              ],
                            ),
                          ),
                        ],

                        // Text scale slider
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.text_fields, color: theme.iconTheme.color),
                                  const SizedBox(width: 16),
                                  Text(
                                    'Kích thước chữ: ${(themeProvider.textScaleFactor * 100).toInt()}%',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Slider(
                                value: themeProvider.textScaleFactor,
                                min: 0.8,
                                max: 2.0,
                                divisions: 24,
                                label: '${(themeProvider.textScaleFactor * 100).toInt()}%',
                                activeColor: theme.colorScheme.primary,
                                onChanged: (value) {
                                  themeProvider.setTextScaleFactor(value);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),

                // SM-2 Settings
                Text(
                  'Ôn tập Spaced Repetition (SM-2)',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    children: [
                      _buildNumberSettingRow(
                        icon: Icons.fiber_new_rounded,
                        color: Colors.blue,
                        label: 'Từ mới tối đa / ngày',
                        value: _sm2NewLimit,
                        onChanged: (val) {
                          setState(() => _sm2NewLimit = val);
                          _saveSm2Limits();
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildNumberSettingRow(
                        icon: Icons.repeat_rounded,
                        color: Colors.green,
                        label: 'Từ ôn tập tối đa / ngày',
                        value: _sm2ReviewLimit,
                        onChanged: (val) {
                          setState(() => _sm2ReviewLimit = val);
                          _saveSm2Limits();
                        },
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.hide_source_outlined, color: Colors.indigo, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cất thẻ liên quan (Bury)',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                Text('Nếu bật, sau khi ôn Lật thẻ, thẻ Tự luận cùng từ sẽ bị dời sang ngày mai và ngược lại',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _sm2BuryRelated,
                            onChanged: (val) {
                              setState(() => _sm2BuryRelated = val);
                              _saveSm2Limits();
                            },
                            activeColor: Colors.indigo,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Anki algorithm params
                Text(
                  'Thông số thuật toán Anki',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Giá trị mặc định theo chuẩn Anki. Thay đổi nếu bạn muốn cá nhân hoá tốc độ ôn tập.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    children: [
                      _buildAnkiParamRow('Hệ số Ease mặc định', 'base_ease', _baseEase, 1.3, 5.0,
                          'Ease khởi đầu của thẻ mới (Anki: 2.50)'),
                      const Divider(height: 20),
                      _buildAnkiParamRow('Bonus Easy', 'easy_bonus', _easyBonus, 1.0, 3.0,
                          'Nhân thêm khi chọn Dễ (Anki: 1.30)'),
                      const Divider(height: 20),
                      _buildAnkiParamRow('Hệ số Lapse (Quên)', 'lapse_interval', _lapseInterval, 0.1, 1.0,
                          'Cắt interval khi quên (Anki: 0.50)'),
                      const Divider(height: 20),
                      _buildAnkiParamRow('Graduating Interval (ngày)', 'graduating_interval', _graduatingInterval, 1.0, 30.0,
                          'Số ngày sau khi chọn Tốt lần đầu (Anki: 1)'),
                      const Divider(height: 20),
                      _buildAnkiParamRow('Easy Interval (ngày)', 'easy_interval', _easyInterval, 1.0, 30.0,
                          'Số ngày sau khi chọn Dễ lần đầu (Anki: 4)'),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Storage Mode Card
                if (_storageMode != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isLocalMode
                          ? Colors.green.withOpacity(isDark ? 0.12 : 0.07)
                          : Colors.blue.withOpacity(isDark ? 0.12 : 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isLocalMode
                            ? Colors.green.withOpacity(0.4)
                            : Colors.blue.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isLocalMode ? Icons.computer_rounded : Icons.cloud_rounded,
                          color: _isLocalMode ? Colors.green : Colors.blue,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Phương thức lưu trữ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                _isLocalMode
                                    ? 'Lưu trên máy (SQLite)\nDữ liệu lưu offline trên thiết bị'
                                    : 'Google Sheets (Cloud)\nDữ liệu đồng bộ qua đám mây',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _changeStorageMode,
                          child: const Text('Đổi'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

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
                
                // Google Sheets sections – ẩn khi Local mode
                if (!_isLocalMode) ...[
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
                ], // end if !_isLocalMode
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberSettingRow({
    required IconData icon,
    required Color color,
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        Row(
          children: [
            IconButton(
              onPressed: value > 0 ? () => onChanged(value - (value > 100 ? 10 : (value > 10 ? 5 : 1))) : null,
              icon: Icon(Icons.remove_circle_outline, color: value > 0 ? theme.colorScheme.primary : theme.disabledColor),
              visualDensity: VisualDensity.compact,
            ),
            SizedBox(
              width: 36,
              child: Text(
                value.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            IconButton(
              onPressed: value < 999 ? () => onChanged(value + (value >= 100 ? 10 : (value >= 10 ? 5 : 1))) : null,
              icon: Icon(Icons.add_circle_outline, color: value < 999 ? theme.colorScheme.primary : theme.disabledColor),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnkiParamRow(String label, String key, double value, double min, double max, String hint) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final ctrl = TextEditingController(text: value.toString());
        final result = await showDialog<double>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: theme.cardColor,
            title: Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Giá trị ($min – $max)',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              ElevatedButton(
                onPressed: () {
                  final v = double.tryParse(ctrl.text);
                  if (v != null && v >= min && v <= max) Navigator.pop(ctx, v);
                },
                child: const Text('Lưu'),
              ),
            ],
          ),
        );
        if (result != null) await _saveAnkiParam(key, result);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.tune, size: 20, color: Colors.deepPurple),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                ],
              ),
            ),
            Text(
              value.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 16, color: theme.iconTheme.color?.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildColorRow(String label, String colorKey, Color currentColor, ThemeProvider themeProvider) {
    return InkWell(
      onTap: () => _openColorPicker(label, colorKey, currentColor, themeProvider),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: currentColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: currentColor.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.edit, size: 18, color: Theme.of(context).iconTheme.color?.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  void _openColorPicker(String label, String colorKey, Color currentColor, ThemeProvider themeProvider) {
    Color pickedColor = currentColor;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Chọn $label'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: currentColor,
              onColorChanged: (color) {
                pickedColor = color;
              },
              enableAlpha: false,
              labelTypes: const [],
              pickerAreaHeightPercent: 0.7,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                themeProvider.setCustomColor(colorKey, pickedColor);
                Navigator.pop(ctx);
              },
              child: const Text('Áp dụng'),
            ),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/config_manager.dart';
import '../services/google_sheets_service.dart';

class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  final ConfigManager _config = ConfigManager();
  final GoogleSheetsService _sheets = GoogleSheetsService();
  final TextEditingController _sheetIdController = TextEditingController();
  final PageController _pageController = PageController();

  int _currentPage = 0;
  String? _storageMode; // null = chưa chọn, 'local' hoặc 'google_sheets'
  String? _credentialsFileName;
  bool _isCreatingStructure = false;
  bool _isTesting = false;

  // Page indices
  static const _pageWelcome = 0;
  static const _pageStorageMode = 1;
  static const _pageCredentials = 2;
  static const _pageSheetId = 3;
  static const _pageFinish = 4;

  bool get _isLocalMode => _storageMode == ConfigManager.storageModeLocal;

  /// Tổng số step hiển thị trên progress bar (tùy mode)
  int get _totalSteps => _isLocalMode ? 3 : 5;

  /// Index step hiện tại cho progress bar
  int get _progressStep {
    if (_isLocalMode) {
      // Trang: 0=welcome, 1=mode, 4=finish → map sang 0,1,2
      if (_currentPage <= _pageStorageMode) return _currentPage;
      return 2; // finish
    }
    return _currentPage;
  }

  @override
  void dispose() {
    _sheetIdController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _pickCredentials() async {
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
        _showSnackBar('File JSON không hợp lệ!', Colors.red);
        return;
      }

      await _config.saveCredentials(contents);
      setState(() {
        _credentialsFileName = result.files.single.name;
      });

      if (!mounted) return;
      _showSnackBar('✅ Credentials đã lưu!', Colors.green);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Lỗi: $e', Colors.red);
    }
  }

  Future<void> _saveSheetId() async {
    final id = _sheetIdController.text.trim();
    if (!_config.validateSheetId(id)) {
      _showSnackBar('Sheet ID không hợp lệ', Colors.red);
      return;
    }
    await _config.saveSheetId(id);
  }

  Future<void> _testAndFinish() async {
    setState(() => _isTesting = true);

    try {
      if (_isLocalMode) {
        // Local mode: chỉ lưu mode và mark configured
        await _config.saveStorageMode(ConfigManager.storageModeLocal);
        await _config.markConfigured();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/dashboard');
      } else {
        // Google Sheets mode
        print('🔍 Starting connection test...');
        await _saveSheetId();
        print('✅ Sheet ID saved');

        final success = await _sheets.testConnection();
        print('🧪 Test result: $success');

        if (!mounted) return;

        if (success) {
          print('🎉 Connection successful! Creating structure...');
          setState(() => _isCreatingStructure = true);
          await _sheets.createSheetStructure();
          await _config.saveStorageMode(ConfigManager.storageModeGoogleSheets);
          await _config.markConfigured();

          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed('/dashboard');
        } else {
          print('❌ Connection test returned false');
          _showSnackBar(
              'Kết nối thất bại! Kiểm tra lại credentials và Sheet ID.',
              Colors.red);
        }
      }
    } catch (e) {
      print('💥 Error during test: $e');
      if (!mounted) return;
      _showSnackBar('Lỗi: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _isCreatingStructure = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _nextPage() {
    int nextPage;
    if (_currentPage == _pageStorageMode && _isLocalMode) {
      // Local mode: bỏ qua credentials và sheetId → thẳng finish
      nextPage = _pageFinish;
    } else if (_currentPage < _pageFinish) {
      nextPage = _currentPage + 1;
    } else {
      return;
    }
    _pageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _previousPage() {
    int prevPage;
    if (_currentPage == _pageFinish && _isLocalMode) {
      // Local mode: từ finish quay về chọn mode
      prevPage = _pageStorageMode;
    } else if (_currentPage > 0) {
      prevPage = _currentPage - 1;
    } else {
      return;
    }
    _pageController.animateToPage(
      prevPage,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  bool get _canProceed {
    switch (_currentPage) {
      case _pageWelcome:
        return true;
      case _pageStorageMode:
        return _storageMode != null;
      case _pageCredentials:
        return _credentialsFileName != null;
      case _pageSheetId:
        return _sheetIdController.text.trim().isNotEmpty;
      case _pageFinish:
        return !_isTesting;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: List.generate(_totalSteps, (index) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: index < _totalSteps - 1 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: index <= _progressStep
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Step label
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Bước ${_progressStep + 1} / $_totalSteps',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildWelcomePage(),
                  _buildStorageModePage(),
                  _buildCredentialsPage(),
                  _buildSheetIdPage(),
                  _buildFinishPage(),
                ],
              ),
            ),

            // Navigation buttons
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previousPage,
                        child: const Text('Quay lại'),
                      ),
                    ),
                  if (_currentPage > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _canProceed
                          ? (_currentPage == _pageFinish ? _testAndFinish : _nextPage)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isTesting
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : Text(_currentPage == _pageFinish ? 'Hoàn tất' : 'Tiếp theo'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── PAGE 0: Welcome ─────────────────────────────────────────────────────

  Widget _buildWelcomePage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school_rounded,
                size: 100, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 32),
            const Text(
              'Chào mừng đến QuizDat!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Ứng dụng học flashcard thông minh. Hãy chọn cách bạn muốn lưu trữ dữ liệu.',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Setup chỉ mất vài phút:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Text('✓ Chọn phương thức lưu trữ dữ liệu'),
                  Text('✓ Cấu hình theo lựa chọn của bạn'),
                  Text('✓ Bắt đầu học ngay!'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── PAGE 1: Chọn Storage Mode ────────────────────────────────────────────

  Widget _buildStorageModePage() {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storage_rounded, size: 72, color: primary),
            const SizedBox(height: 20),
            const Text(
              'Lưu trữ dữ liệu',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Chọn nơi bạn muốn lưu dữ liệu flashcard',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Option: Local SQLite
            _StorageModeCard(
              icon: Icons.computer_rounded,
              title: 'Lưu trên máy (Offline)',
              description:
                  'Dữ liệu lưu ngay trên thiết bị của bạn. Không cần internet, không cần tài khoản Google.',
              badge: 'Đơn giản',
              badgeColor: Colors.green,
              selected: _storageMode == ConfigManager.storageModeLocal,
              onTap: () => setState(
                  () => _storageMode = ConfigManager.storageModeLocal),
              selectedColor: primary,
              surfaceColor: surface,
            ),

            const SizedBox(height: 16),

            // Option: Google Sheets
            _StorageModeCard(
              icon: Icons.cloud_rounded,
              title: 'Google Sheets (Cloud)',
              description:
                  'Dữ liệu lưu trên Google Sheets cá nhân. Truy cập từ mọi nơi, sync đám mây.',
              badge: 'Nâng cao',
              badgeColor: Colors.blue,
              selected: _storageMode == ConfigManager.storageModeGoogleSheets,
              onTap: () => setState(
                  () => _storageMode = ConfigManager.storageModeGoogleSheets),
              selectedColor: primary,
              surfaceColor: surface,
            ),
          ],
        ),
      ),
    );
  }

  // ─── PAGE 2: Credentials ─────────────────────────────────────────────────

  Widget _buildCredentialsPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.key, size: 80, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            const Text(
              'Bước 1: Upload credentials.json',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'File credentials từ Google Cloud Service Account',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _pickCredentials,
              icon: const Icon(Icons.upload_file),
              label: Text(_credentialsFileName ?? 'Chọn file credentials.json'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
            if (_credentialsFileName != null) ...[
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text('File đã lưu!', style: TextStyle(color: Colors.green)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── PAGE 3: Sheet ID ─────────────────────────────────────────────────────

  Widget _buildSheetIdPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart,
                size: 80, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            const Text(
              'Bước 2: Nhập Sheet ID',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _sheetIdController,
              decoration: const InputDecoration(
                labelText: 'Google Sheet ID',
                hintText: 'Paste ID từ URL...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.content_paste),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(
              'Tìm ID trong URL Sheet của bạn:\ndocs.google.com/spreadsheets/d/[ID]',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── PAGE 4: Finish ───────────────────────────────────────────────────────

  Widget _buildFinishPage() {
    final isLocal = _storageMode == ConfigManager.storageModeLocal;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isCreatingStructure)
              const CircularProgressIndicator()
            else
              Icon(Icons.rocket_launch,
                  size: 80, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              _isCreatingStructure ? 'Đang tạo cấu trúc...' : 'Sẵn sàng!',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              _isCreatingStructure
                  ? 'Đang setup Google Sheet của bạn...'
                  : isLocal
                      ? 'Dữ liệu sẽ được lưu ngay trên máy của bạn.\nNhấn "Hoàn tất" để bắt đầu!'
                      : 'Nhấn "Hoàn tất" để test kết nối Google Sheets và bắt đầu!',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Summary chip
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLocal ? Icons.computer_rounded : Icons.cloud_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isLocal ? 'Lưu trên máy (SQLite)' : 'Google Sheets',
                    style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helper Widget ────────────────────────────────────────────────────────────

class _StorageModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String badge;
  final Color badgeColor;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color surfaceColor;

  const _StorageModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.badgeColor,
    required this.selected,
    required this.onTap,
    required this.selectedColor,
    required this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected
              ? selectedColor.withOpacity(0.08)
              : surfaceColor,
          border: Border.all(
            color: selected ? selectedColor : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? selectedColor.withOpacity(0.15)
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 32,
                color: selected ? selectedColor : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: selected ? selectedColor : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 11,
                            color: badgeColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected ? selectedColor : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

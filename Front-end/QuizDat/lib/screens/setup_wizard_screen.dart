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
  String? _credentialsFileName;
  bool _isCreatingStructure = false;
  bool _isTesting = false;

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
      print('🔍 Starting connection test...');
      
      // Save Sheet ID first before testing connection
      await _saveSheetId();
      print('✅ Sheet ID saved');
      
      final success = await _sheets.testConnection();
      print('🧪 Test result: $success');
      
      if (!mounted) return;

      if (success) {
        print('🎉 Connection successful! Creating structure...');
        setState(() => _isCreatingStructure = true);
        await _sheets.createSheetStructure();
        await _config.markConfigured();
        
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/dashboard');
      } else {
        print('❌ Connection test returned false');
        _showSnackBar('Kết nối thất bại! Kiểm tra lại credentials và Sheet ID.', Colors.red);
      }
    } catch (e) {
      print('💥 Error during test: $e');
      if (!mounted) return;
      _showSnackBar('Lỗi kết nối: $e', Colors.red);
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
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
              padding: const EdgeInsets.all(20),
              child: Row(
                children: List.generate(4, (index) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: index < 3 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: index <= _currentPage 
                            ? Theme.of(context).colorScheme.primary 
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
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
                      onPressed: _currentPage == 3
                          ? (_isTesting ? null : _testAndFinish)
                          : (_currentPage == 1 && _credentialsFileName == null
                              ? null
                              : (_currentPage == 2 && _sheetIdController.text.trim().isEmpty
                                  ? null
                                  : _nextPage)),
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
                          : Text(_currentPage == 3 ? 'Hoàn tất' : 'Tiếp theo'),
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

  Widget _buildWelcomePage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud, size: 100, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 32),
            const Text(
              'Chào mừng đến QuizDat!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Bạn cần setup Google Sheet riêng của mình để bắt đầu.',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Bạn sẽ cần:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Text('✓ File credentials.json từ Google Cloud'),
                  Text('✓ Google Sheet ID'),
                  Text('✓ Vài phút để setup'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
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

  Widget _buildSheetIdPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart, size: 80, color: Theme.of(context).colorScheme.primary),
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

  Widget _buildFinishPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isCreatingStructure)
              const CircularProgressIndicator()
            else
              Icon(Icons.rocket_launch, size: 80, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              _isCreatingStructure ? 'Đang tạo cấu trúc...' : 'Sẵn sàng!',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              _isCreatingStructure
                  ? 'Đang setup Google Sheet của bạn...'
                  : 'Nhấn "Hoàn tất" để test kết nối và bắt đầu!',
              style: TextStyle(
                fontSize: 16, 
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

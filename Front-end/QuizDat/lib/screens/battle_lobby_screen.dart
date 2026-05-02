import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/battle_provider.dart';
import '../widgets/app_sidebar.dart';
import '../models/battle_models.dart';
import '../models/card.dart';
import '../models/set_card.dart';
import '../services/database_helper.dart';
import 'battle_quiz_screen.dart';

class BattleLobbyScreen extends StatefulWidget {
  const BattleLobbyScreen({super.key});

  @override
  State<BattleLobbyScreen> createState() => _BattleLobbyScreenState();
}

class _BattleLobbyScreenState extends State<BattleLobbyScreen> {
  bool _isScanning = false;
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  void _createRoom() async {
    final provider = context.read<BattleProvider>();
    bool success = await provider.startHosting();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể tạo phòng. Hãy kiểm tra kết nối Wifi.')),
      );
    }
  }

  void _joinRoom(String ip) async {
    final provider = context.read<BattleProvider>();
    setState(() => _isScanning = false);
    
    // Show loading
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    
    bool success = await provider.joinLobby(ip);
    
    if (mounted) {
      Navigator.pop(context); // Close loading
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể kết nối tới phòng. Kiểm tra lại IP hoặc kết nối Wifi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<BattleProvider>();

    // Listen for battle start
    if (provider.isStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const BattleQuizScreen()),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đấu Trường P2P'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          if (provider.isConnected)
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: Colors.red),
              tooltip: 'Thoát phòng',
              onPressed: () {
                provider.disconnect();
              },
            ),
        ],
      ),
      drawer: const AppSidebar(currentRoute: '/battle'),
      body: provider.isConnected ? _buildLobby(theme, provider) : _buildRoleSelection(theme),
    );
  }

  Widget _buildRoleSelection(ThemeData theme) {
    if (_isScanning) {
      return Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
                    _joinRoom(barcode.rawValue!);
                    break; // Only join the first one detected
                  }
                }
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => setState(() => _isScanning = false),
                  icon: const Icon(Icons.cancel),
                  label: const Text('Hủy quét'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
          )
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sports_esports, size: 100, color: Colors.blue),
            const SizedBox(height: 30),
            Text(
              'Chọn vai trò của bạn',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _createRoom,
                icon: const Icon(Icons.add_home_work),
                label: const Text('Tạo Phòng (Host)', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('HOẶC', style: theme.textTheme.bodyMedium),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _isScanning = true),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Quét QR Vào Phòng', style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'Nhập IP (VD: 192.168.1.10)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    if (_ipController.text.isNotEmpty) {
                      _joinRoom(_ipController.text);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                  child: const Text('Vào'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLobby(ThemeData theme, BattleProvider provider) {
    return Column(
      children: [
        if (provider.isHost)
          Container(
            padding: const EdgeInsets.all(20),
            color: theme.cardColor,
            child: Row(
              children: [
                QrImageView(
                  data: provider.localIp,
                  version: QrVersions.auto,
                  size: 100.0,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quét QR để vào phòng', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 5),
                      Text('Hoặc nhập IP:', style: theme.textTheme.bodyMedium),
                      Text(
                        provider.localIp, 
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        )
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
        if (!provider.isHost)
          Container(
            padding: const EdgeInsets.all(20),
            width: double.infinity,
            color: theme.cardColor,
            child: Text(
              'Đang ở trong phòng của: ${provider.localIp}',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          
        const SizedBox(height: 20),
        
        // Quiz Selection Status
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange),
          ),
          child: Row(
            children: [
              const Icon(Icons.library_books, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bộ câu hỏi hiện tại:', style: theme.textTheme.bodySmall),
                    Text(
                      provider.selectedSet?.name ?? 'Chưa chọn',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if (provider.isHost)
                ElevatedButton(
                  onPressed: _showQuizSelectionDialog,
                  child: const Text('Đổi'),
                ),
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Players list
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Người chơi (${provider.players.length}/8)', style: theme.textTheme.titleLarge),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            itemCount: provider.players.length,
            itemBuilder: (context, index) {
              final p = provider.players[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.primaries[index % Colors.primaries.length],
                  child: Text(p.name[0].toUpperCase()),
                ),
                title: Text(p.name + (index == 0 && provider.isHost ? " (Host)" : "")),
                trailing: p.isReady 
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
              );
            },
          ),
        ),
        
        // Action buttons
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Row(
            children: [
              if (!provider.isHost)
                Expanded(
                  child: ElevatedButton(
                    onPressed: provider.selectedSet != null ? () => provider.setReady() : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('SẴN SÀNG', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              if (provider.isHost)
                Expanded(
                  child: ElevatedButton(
                    onPressed: provider.players.every((p) => p.isReady) && provider.selectedSet != null
                        ? () => provider.startBattle()
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('BẮT ĐẦU CHIẾN', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showQuizSelectionDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchSets(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("Không có bộ câu hỏi nào"));
                }
                
                final sets = snapshot.data!;
                return ListView.builder(
                  controller: scrollController,
                  itemCount: sets.length,
                  itemBuilder: (context, index) {
                    final setData = sets[index];
                    return ListTile(
                      title: Text(setData['name'] ?? 'Không tên'),
                      subtitle: Text("Từ thư viện của bạn"),
                      onTap: () => _selectSetForBattle(setData),
                    );
                  },
                );
              },
            );
          },
        );
      }
    );
  }

  Future<List<Map<String, dynamic>>> _fetchSets() async {
    final dbHelper = DatabaseHelper();
    // Fetch all sets from all repos. It requires a custom query or fetching all repos first.
    // Let's assume we can fetch all repos, then all sets.
    final repos = await dbHelper.getAllRepositories();
    List<Map<String, dynamic>> allSets = [];
    for (var repo in repos) {
      final sets = await dbHelper.getSetCardsByRepositoryId(repo['repository_id']);
      allSets.addAll(sets);
    }
    return allSets;
  }

  void _selectSetForBattle(Map<String, dynamic> setData) async {
    Navigator.pop(context); // Close bottom sheet
    
    // Show loading
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      final dbHelper = DatabaseHelper();
      final cardsData = await dbHelper.getCardsBySetId(setData['set_id']);
      
      final setCard = SetCard.fromJson(setData);
      final cards = cardsData.map((c) => VocabCard.fromJson(c)).toList();
      
      if (cards.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bộ câu hỏi này không có thẻ nào!')),
          );
        }
        return;
      }

      if (mounted) {
        context.read<BattleProvider>().selectQuiz(setCard, cards);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }
}

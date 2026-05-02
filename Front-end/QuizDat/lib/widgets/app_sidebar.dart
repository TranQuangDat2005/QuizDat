import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/dashboard.dart';
import '../screens/folder_management.dart';
import '../screens/calendar_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/battle_lobby_screen.dart';

class AppSidebar extends StatelessWidget {
  final String currentRoute;

  const AppSidebar({super.key, required this.currentRoute});

  void _navigateTo(BuildContext context, String routeName, Widget screen) {
    if (currentRoute == routeName) {
      Navigator.pop(context); // Just close drawer
    } else {
      Navigator.pop(context); // Close drawer first
      if (routeName == '/dashboard') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => screen),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => screen),
        );
      }
    }
  }

  void _showSupportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        
        return AlertDialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.dividerColor, width: 2),
          ),
          title: Row(
            children: [
              Icon(Icons.contact_support_outlined, color: theme.iconTheme.color),
              const SizedBox(width: 10),
              Text("Hỗ trợ", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Mọi thắc mắc vui lòng liên hệ:", style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "datquangtran05@gmail.com",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.blue),
                      tooltip: "Sao chép Email",
                      onPressed: () {
                        Clipboard.setData(
                          const ClipboardData(text: "datquangtran05@gmail.com"),
                        );
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Đã sao chép Email!"), backgroundColor: Colors.green),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                "Đóng",
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.black,
            ),
            child: const Center(
              child: Text(
                "QuizDat",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: Icon(Icons.home, color: theme.iconTheme.color),
                  title: Text('Trang chủ', style: theme.textTheme.bodyLarge),
                  selected: currentRoute == '/dashboard',
                  selectedColor: theme.primaryColor,
                  selectedTileColor: isDark ? Colors.white12 : Colors.grey[200],
                  onTap: () => _navigateTo(context, '/dashboard', const Dashboard()),
                ),
                ListTile(
                  leading: Icon(Icons.folder, color: theme.iconTheme.color),
                  title: Text('Thư mục của tôi', style: theme.textTheme.bodyLarge),
                  selected: currentRoute == '/folders',
                  selectedColor: theme.primaryColor,
                  selectedTileColor: isDark ? Colors.white12 : Colors.grey[200],
                  onTap: () => _navigateTo(context, '/folders', const FolderManagementScreen()),
                ),
                ListTile(
                  leading: Icon(Icons.calendar_month, color: theme.iconTheme.color),
                  title: Text('Lịch học tập', style: theme.textTheme.bodyLarge),
                  selected: currentRoute == '/calendar',
                  selectedColor: theme.primaryColor,
                  selectedTileColor: isDark ? Colors.white12 : Colors.grey[200],
                  onTap: () => _navigateTo(context, '/calendar', const CalendarScreen()),
                ),
                ListTile(
                  leading: Icon(Icons.sports_esports, color: theme.iconTheme.color),
                  title: Text('Đấu trường P2P', style: theme.textTheme.bodyLarge),
                  selected: currentRoute == '/battle',
                  selectedColor: theme.primaryColor,
                  selectedTileColor: isDark ? Colors.white12 : Colors.grey[200],
                  onTap: () => _navigateTo(context, '/battle', const BattleLobbyScreen()),
                ),
              ],
            ),
          ),
          Divider(color: theme.dividerColor),
          ListTile(
            leading: Icon(Icons.settings, color: theme.iconTheme.color),
            title: Text('Cài đặt', style: theme.textTheme.bodyLarge),
            selected: currentRoute == '/settings',
            selectedColor: theme.primaryColor,
            selectedTileColor: isDark ? Colors.white12 : Colors.grey[200],
            onTap: () => _navigateTo(context, '/settings', const SettingsScreen()),
          ),
          ListTile(
            leading: Icon(Icons.mail_outline, color: theme.iconTheme.color),
            title: Text('Hỗ trợ', style: theme.textTheme.bodyLarge),
            onTap: () {
              Navigator.pop(context);
              _showSupportDialog(context);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

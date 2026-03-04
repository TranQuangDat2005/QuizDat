import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 1. Import để dùng Clipboard
import '../models/repository.dart';
import '../services/repository_service.dart';
import 'folder_detail_screen.dart';
import 'calendar_screen.dart'; // 2. Thêm import trang Lịch
import '../widgets/app_sidebar.dart';

class FolderManagementScreen extends StatefulWidget {
  const FolderManagementScreen({super.key});

  @override
  State<FolderManagementScreen> createState() => _FolderManagementScreenState();
}

class _FolderManagementScreenState extends State<FolderManagementScreen> {
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  List<Repository> _folders = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadFolders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- HÀM HIỂN THỊ HỘP THOẠI SUPPORT ---
  void _showSupportDialog() {
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
                        _showSnackBar("Đã sao chép Email!", Colors.green);
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

  List<Repository> get _filteredFolders {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return _folders;
    return _folders
        .where((folder) => folder.name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);
    try {
      final folders = await RepositoryService().getAllRepositories();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar("Lỗi tải thư mục: $e", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _showCreateFolderDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    _showFolderFormDialog(
      title: "Tạo thư mục mới",
      actionText: "Tạo",
      nameController: nameController,
      descController: descController,
      onConfirm: () async {
        final name = nameController.text.trim();
        final desc = descController.text.trim();
        await RepositoryService().createRepository(
          name,
          desc.isEmpty ? "Thư mục học tập" : desc,
        );
        _loadFolders();
      },
    );
  }

  void _showEditFolderDialog(Repository folder) {
    final nameController = TextEditingController(text: folder.name);
    final descController = TextEditingController(text: folder.description);

    _showFolderFormDialog(
      title: "Chỉnh sửa thư mục",
      actionText: "Lưu",
      nameController: nameController,
      descController: descController,
      onConfirm: () async {
        final newName = nameController.text.trim();
        final newDesc = descController.text.trim();

        await RepositoryService().updateRepository(
          folder.repositoryId,
          newName,
          newDesc,
        );

        setState(() {
          final index = _folders.indexWhere(
            (f) => f.repositoryId == folder.repositoryId,
          );
          if (index != -1) {
            _folders[index] = Repository(
              repositoryId: folder.repositoryId,
              name: newName,
              description: newDesc,
            );
          }
        });
      },
    );
  }

  void _showFolderFormDialog({
    required String title,
    required String actionText,
    required TextEditingController nameController,
    required TextEditingController descController,
    required Future<void> Function() onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        final theme = Theme.of(context);
        return Dialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: theme.dividerColor, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_shared_outlined,
                  size: 60,
                  color: theme.iconTheme.color,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: "Tên thư mục",
                    hintText: "Nhập tên...",
                    labelStyle: theme.textTheme.bodyMedium,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: theme.primaryColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: "Mô tả",
                    hintText: "Nhập mô tả ngắn...",
                    labelStyle: theme.textTheme.bodyMedium,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: theme.primaryColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(
                        "Hủy",
                        style: TextStyle(
                          color: theme.disabledColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (nameController.text.trim().isEmpty) return;
                        Navigator.pop(dialogContext);
                        _showSnackBar("Đang xử lý...", theme.textTheme.bodyMedium?.color ?? Colors.black);
                        try {
                          await onConfirm();
                          _showSnackBar("Thành công!", Colors.green);
                        } catch (e) {
                          _showSnackBar("Lỗi: $e", Colors.red);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(actionText),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteFolder(Repository folder) {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text(
            "Xóa thư mục?",
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: Text(
            "Xác nhận xóa '${folder.name}'?",
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Hủy", style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await RepositoryService().deleteRepository(folder.repositoryId);
                  _showSnackBar("Đã xóa thư mục", Colors.green);
                  _loadFolders();
                } catch (e) {
                  _showSnackBar("Lỗi: $e", Colors.red);
                }
              },
              child: const Text("Xóa"),
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
    final displayFolders = _filteredFolders;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        iconTheme: theme.iconTheme,
        title: Container(
          width: MediaQuery.of(context).size.width * 0.6,
          height: 40,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: theme.dividerColor, width: 1.0),
          ),
          child: TextField(
            controller: _searchController,
            cursorColor: theme.primaryColor,
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14),
            decoration: InputDecoration(
              hintText: "Tìm thư mục...",
              hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38),
              border: InputBorder.none,
              prefixIcon: Icon(
                Icons.search,
                color: theme.iconTheme.color,
                size: 20,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: theme.iconTheme.color,
                        size: 18,
                      ),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: _showCreateFolderDialog,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: theme.dividerColor, width: 0.8),
              ),
              child: Icon(Icons.add, color: theme.iconTheme.color),
            ),
          ),
        ],
      ),
      drawer: const AppSidebar(currentRoute: '/folders'),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : displayFolders.isEmpty
          ? Center(
              child: Text(
                _searchController.text.isEmpty
                    ? "Bạn chưa có thư mục nào."
                    : "Không tìm thấy thư mục phù hợp.",
                style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6)),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: displayFolders.length,
              itemBuilder: (context, index) {
                final folder = displayFolders[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor, width: 1.5),
                  ),
                  child: ListTile(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => FolderDetailScreen(folder: folder),
                      ),
                    ),
                    leading: Icon(
                      Icons.folder,
                      color: theme.iconTheme.color,
                      size: 40,
                    ),
                    title: Text(
                      folder.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    subtitle: Text(
                      folder.description.isEmpty
                          ? "Thư mục học tập"
                          : folder.description,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.edit_outlined,
                            color: theme.iconTheme.color,
                          ),
                          onPressed: () => _showEditFolderDialog(folder),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.iconTheme.color,
                          ),
                          onPressed: () => _confirmDeleteFolder(folder),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

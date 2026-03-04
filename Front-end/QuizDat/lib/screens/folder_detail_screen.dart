import 'package:flutter/material.dart';
import '../models/repository.dart';
import '../models/set_card.dart';
import '../services/set_card_service.dart';
import 'vocab_set_library.dart';

class FolderDetailScreen extends StatefulWidget {
  final Repository folder;

  const FolderDetailScreen({super.key, required this.folder});

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  List<SetCard> _sets = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadSetsInFolder();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SetCard> get _filteredSets {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return _sets;
    return _sets
        .where((set) => set.name.toLowerCase().contains(query))
        .toList();
  }

  // =========================================
  // LOGIC XỬ LÝ DỮ LIỆU (API)
  // =========================================

  Future<void> _loadSetsInFolder() async {
    setState(() => _isLoading = true);
    try {
      final sets = await SetService().fetchSetsByRepoId(
        widget.folder.repositoryId,
      );
      if (!mounted) return;
      setState(() {
        _sets = sets;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar("Lỗi tải học phần: $e", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  // =========================================
  // LOGIC DIALOG (TẠO & SỬA)
  // =========================================

  void _showSetFormDialog({
    required String title,
    required String actionText,
    SetCard? existingSet,
  }) {
    final nameController = TextEditingController(text: existingSet?.name ?? "");

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
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  existingSet == null
                      ? Icons.library_add_outlined
                      : Icons.edit_note_outlined,
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
                  cursorColor: theme.primaryColor,
                  decoration: InputDecoration(
                    labelText: "Tên học phần",
                    hintText: "Ví dụ: Từ vựng Bài 1...",
                    hintStyle: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5)),
                    labelStyle: theme.textTheme.bodyMedium,
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
                        final name = nameController.text.trim();
                        if (name.isEmpty) return;
                        Navigator.pop(dialogContext);
                        try {
                          if (existingSet == null) {
                            await SetService().createSetCard(
                              name,
                              widget.folder.repositoryId,
                            );
                            _loadSetsInFolder();
                          } else {
                            await SetService().updateSetCard(
                              existingSet.setId,
                              name: name,
                            );
                            setState(() {
                              final index = _sets.indexWhere(
                                (s) => s.setId == existingSet.setId,
                              );
                              if (index != -1) {
                                _sets[index] = SetCard(
                                  setId: existingSet.setId,
                                  name: name,
                                  repositoryId: existingSet.repositoryId,
                                  lastLearnedTime: existingSet.lastLearnedTime,
                                );
                              }
                            });
                          }
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

  void _confirmDeleteSet(SetCard setCard) {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text(
            "Xóa học phần?",
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: Text(
            "Xác nhận xóa '${setCard.name}'?",
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
                  await SetService().deleteSetCard(setCard.setId);
                  _showSnackBar("Đã xóa", Colors.green);
                  _loadSetsInFolder();
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

  // =========================================
  // GIAO DIỆN CHÍNH
  // =========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final displaySets = _filteredSets;

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
              hintText: "Tìm học phần...",
              hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38),
              border: InputBorder.none,
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: theme.iconTheme.color,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 18, color: theme.iconTheme.color),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          // --- SỬA LẠI NÚT ADD THEO STYLE MỚI ---
          GestureDetector(
            onTap: () => _showSetFormDialog(
              title: "Tạo học phần mới",
              actionText: "Tạo",
            ),
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
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "THƯ MỤC: ${widget.folder.name.toUpperCase()}",
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Expanded(
                  child: displaySets.isEmpty
                      ? const Center(child: Text("Không có học phần nào."))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: displaySets.length,
                          itemBuilder: (context, index) {
                            final set = displaySets[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: theme.cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.dividerColor,
                                  width: 1.5,
                                ),
                              ),
                              child: ListTile(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          VocabSetLibrary(setCard: set),
                                    ),
                                  );
                                },
                                leading: Icon(
                                  Icons.style,
                                  color: theme.iconTheme.color,
                                  size: 30,
                                ),
                                title: Text(
                                  set.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  "Lần học cuối: ${set.formattedDate}",
                                  style: theme.textTheme.bodySmall,
                                ),
                                trailing: PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
                                  color: theme.cardColor,
                                  onSelected: (val) {
                                    if (val == 'edit') {
                                      _showSetFormDialog(
                                        title: "Sửa tên",
                                        actionText: "Lưu",
                                        existingSet: set,
                                      );
                                    }
                                    if (val == 'delete') _confirmDeleteSet(set);
                                  },
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text("Sửa tên", style: theme.textTheme.bodyMedium),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        "Xóa",
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/set_card.dart';
import '../models/calendar_event.dart';
import '../services/set_card_service.dart';
import '../services/repository_service.dart';
import '../services/card_service.dart';
import '../services/calendar_service.dart';
import 'folder_management.dart';
import 'vocab_set_library.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';
import '../widgets/app_sidebar.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  List<SetCard> _recentSets = [];
  List<SetCard> _reviewSets = [];
  int _vocabCount = 0;
  List<CalendarEvent> _upcomingEvents = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  List<SetCard> get _searchResults {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return [];

    final Map<String, SetCard> uniqueSets = {};
    for (var s in _recentSets) {
      uniqueSets[s.setId] = s;
    }
    for (var s in _reviewSets) {
      uniqueSets[s.setId] = s;
    }

    return uniqueSets.values
        .where((s) => s.name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        SetService().fetchRecentSets(),
        SetService().fetchNeedToLearnSets(),
        CardService().fetchVocabNeedToLearn(),
        CalendarService().fetchEvents(),
      ]);

      if (!mounted) return;

      // Filter events for next 14 days
      final now = DateTime.now();
      final in14Days = now.add(const Duration(days: 14));
      final filteredEvents = (results[3] as List<CalendarEvent>)
          .where((event) =>
              event.date.isAfter(now) && event.date.isBefore(in14Days))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      setState(() {
        _recentSets = results[0] as List<SetCard>;
        _reviewSets = results[1] as List<SetCard>;
        _vocabCount = results[2] as int;
        _upcomingEvents = filteredEvents.take(5).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar("Lỗi tải dữ liệu: $e", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _showCreateFolderDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;

        return Dialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.outline, width: 2),
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
                  color: colorScheme.onSurface,
                ),
                const SizedBox(height: 16),
                Text(
                  "Tạo thư mục mới",
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  cursorColor: colorScheme.primary,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: "Tên thư mục",
                    labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
                    hintText: "Ví dụ: Từ vựng TOPIK...",
                    hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.primary, width: 2),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.outline),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  cursorColor: colorScheme.primary,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: "Mô tả",
                    labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
                    hintText: "Mô tả ngắn gọn về thư mục...",
                    hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.primary, width: 2),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.outline),
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
                          color: colorScheme.onSurface.withOpacity(0.6),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final desc = descController.text.trim();
                        if (name.isEmpty) return;

                        Navigator.pop(dialogContext);

                        if (!mounted) return;
                        _showSnackBar("Đang tạo thư mục...", colorScheme.primary);

                        try {
                          await RepositoryService().createRepository(
                            name,
                            desc.isEmpty ? "Thư mục học tập" : desc,
                          );

                          if (!mounted) return;
                          _showSnackBar("Đã tạo thư mục: $name", Colors.green);
                          _loadData();
                        } catch (e) {
                          if (!mounted) return;
                          _showSnackBar("Lỗi tạo thư mục: $e", Colors.red);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text("Tạo"),
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

  void _showCreateSetDialog() async {
    final TextEditingController nameController = TextEditingController();
    List<dynamic> folders = [];
    String? selectedFolderId;

    // Load danh sách thư mục
    try {
      folders = await RepositoryService().getAllRepositories();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Lỗi tải thư mục: $e", Colors.red);
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final colorScheme = Theme.of(context).colorScheme;
            final textTheme = Theme.of(context).textTheme;

            return Dialog(
              backgroundColor: colorScheme.surface,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: colorScheme.outline, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.school_outlined,
                      size: 60,
                      color: colorScheme.onSurface,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Tạo học phần mới",
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Tên học phần
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      cursorColor: colorScheme.primary,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Tên học phần",
                        labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
                        hintText: "Ví dụ: Từ vựng N3...",
                        hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.primary, width: 2),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Dropdown chọn thư mục
                    DropdownButtonFormField<String>(
                      value: selectedFolderId,
                      dropdownColor: colorScheme.surface,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Thư mục",
                        labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.primary, width: 2),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                      ),
                      hint: Text(
                        folders.isEmpty ? "Chưa có thư mục" : "Chọn thư mục...",
                        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
                      ),
                      items: folders.map((folder) {
                        return DropdownMenuItem<String>(
                          value: folder.repositoryId,
                          child: Text(
                            folder.name,
                            style: TextStyle(color: colorScheme.onSurface),
                          ),
                        );
                      }).toList(),
                      onChanged: folders.isEmpty
                          ? null
                          : (val) => setStateDialog(() => selectedFolderId = val),
                    ),
                    if (folders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          "Hãy tạo thư mục trước khi tạo học phần.",
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                            fontStyle: FontStyle.italic,
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
                              color: colorScheme.onSurface.withOpacity(0.6),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: (selectedFolderId == null || folders.isEmpty)
                              ? null
                              : () async {
                                  final name = nameController.text.trim();
                                  if (name.isEmpty) return;

                                  Navigator.pop(dialogContext);

                                  if (!mounted) return;
                                  _showSnackBar("Đang tạo học phần...", colorScheme.primary);

                                  try {
                                    await SetService().createSetCard(name, selectedFolderId!);
                                    if (!mounted) return;
                                    _showSnackBar("Đã tạo học phần: $name", Colors.green);
                                    _loadData();
                                  } catch (e) {
                                    if (!mounted) return;
                                    _showSnackBar("Lỗi tạo học phần: $e", Colors.red);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text("Tạo"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTable(List<SetCard> data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.dividerColor, width: 1.2),
        ),
        child: data.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(
                  child: Text(
                    "Chưa có dữ liệu",
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5)),
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: data.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: theme.dividerColor),
                itemBuilder: (context, index) {
                  final item = data[index];
                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VocabSetLibrary(setCard: item),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[800] : Colors.black,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.style,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.status != null && item.status!.isNotEmpty
                                      ? "${item.status} • ${item.formattedDate.isEmpty ? 'Chưa có ngày' : item.formattedDate}"
                                      : (item.formattedDate.isEmpty
                                          ? "Chưa học"
                                          : "${item.formattedDate} • ${item.repositoryId}"),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: _getStatusColor(item.status),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: theme.iconTheme.color?.withOpacity(0.3),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    if (status == 'Đã học') return Colors.green;
    if (status == 'Đang học') return Colors.blue;
    return Colors.grey;
  }

  Widget _buildVocabCounter() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.dividerColor, width: 1.2),
      ),
      child: Column(
        children: [
          Text(
            _vocabCount.toString(),
            style: TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w900,
              color: theme.textTheme.titleLarge?.color,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "từ mới & đang học",
            style: TextStyle(
              fontSize: 13,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingEvents() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.dividerColor, width: 1.2),
      ),
      child: _upcomingEvents.isEmpty
          ? Center(
              child: Text(
                "Không có sự kiện",
                style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5)),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _upcomingEvents.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: theme.dividerColor),
              itemBuilder: (context, index) {
                final event = _upcomingEvents[index];
                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CalendarScreen(),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: event.isDone
                                  ? (isDark ? Colors.white70 : Colors.black)
                                  : (isDark ? Colors.white30 : Colors.black38),
                              width: 1.5,
                            ),
                            color: event.isDone
                                ? (isDark ? Colors.white70 : Colors.black)
                                : theme.cardColor,
                          ),
                          child: event.isDone
                              ? Icon(
                                  Icons.check,
                                  size: 10,
                                  color: isDark ? Colors.black : Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textTheme.titleMedium?.color,
                                  decoration: event.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: theme.textTheme.titleMedium?.color,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "${DateFormat('dd/MM').format(event.date)} • ${DateFormat('HH:mm').format(event.date)}",
                                style: theme.textTheme.bodySmall,
                              ),
                              if (event.description.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  event.description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          _getEventIcon(event.type),
                          size: 16,
                          color: theme.iconTheme.color?.withOpacity(0.5),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  IconData _getEventIcon(CalendarType type) {
    switch (type) {
      case CalendarType.study:
        return Icons.school;
      case CalendarType.exam:
        return Icons.assignment;
      case CalendarType.deadline:
        return Icons.alarm;
      case CalendarType.meeting:
        return Icons.people;
      case CalendarType.other:
        return Icons.event;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.appBarTheme.backgroundColor,
          elevation: 0,
          centerTitle: true,
          title: Container(
            width: MediaQuery.of(context).size.width * 0.5,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: theme.dividerColor, width: 1.0),
            ),
            child: TextField(
              controller: _searchController,
              cursorColor: theme.primaryColor,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: "Tìm kiếm...",
                hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38),
                border: InputBorder.none,
                prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: theme.iconTheme.color),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
              ),
            ),
          ),
          actions: [
            PopupMenuButton<String>(
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
              onSelected: (String value) {
                if (value == 'folder') {
                  _showCreateFolderDialog();
                } else if (value == 'set') {
                  _showCreateSetDialog();
                }
              },
              color: isDark ? Colors.grey[900] : Colors.white,
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'folder',
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, color: isDark ? Colors.white70 : Colors.grey),
                      const SizedBox(width: 10),
                      Text('Tạo thư mục', style: theme.textTheme.bodyLarge),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'set',
                  child: Row(
                    children: [
                      Icon(Icons.school, color: isDark ? Colors.white70 : Colors.grey),
                      const SizedBox(width: 10),
                      Text('Tạo học phần', style: theme.textTheme.bodyLarge),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        drawer: const AppSidebar(currentRoute: '/dashboard'),
        body: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: theme.colorScheme.primary),
              )
            : RefreshIndicator(
                onRefresh: _loadData,
                color: theme.colorScheme.primary,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 24.0,
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: _searchController.text.isNotEmpty
                      ? Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "KẾT QUẢ TÌM KIẾM",
                                  style: TextStyle(
                                    fontSize: 16,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildTable(_searchResults),
                              ],
                            ),
                          ),
                        )
                      : Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // TOP ROW: Recent Sets + Vocab Counter
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // LEFT: Recent Sets (60%)
                                    Expanded(
                                      flex: 6,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "HỌC PHẦN GẦN ĐÂY",
                                            style: TextStyle(
                                              fontSize: 16,
                                              letterSpacing: 1.2,
                                              fontWeight: FontWeight.w900,
                                              color: theme.textTheme.titleLarge?.color,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          _buildTable(_recentSets),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // RIGHT: Vocab Counter (40%)
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "TỪ VỰNG CẦN HỌC",
                                            style: TextStyle(
                                              fontSize: 16,
                                              letterSpacing: 1.2,
                                              fontWeight: FontWeight.w900,
                                              color: theme.textTheme.titleLarge?.color,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          _buildVocabCounter(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 40),

                                // BOTTOM ROW: Review Sets + Upcoming Events
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // LEFT: Review Sets (60%)
                                    Expanded(
                                      flex: 6,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "HỌC PHẦN CẦN ÔN TẬP",
                                            style: TextStyle(
                                              fontSize: 16,
                                              letterSpacing: 1.2,
                                              fontWeight: FontWeight.w900,
                                              color: theme.textTheme.titleLarge?.color,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          _buildTable(_reviewSets),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // RIGHT: Upcoming Events (40%)
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "SỰ KIỆN SẮP TỚI",
                                            style: TextStyle(
                                              fontSize: 16,
                                              letterSpacing: 1.2,
                                              fontWeight: FontWeight.w900,
                                              color: theme.textTheme.titleLarge?.color,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          _buildUpcomingEvents(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/card.dart';
import '../services/card_service.dart';
import 'flashcard_widget.dart';

class FlashcardFocusScreen extends StatefulWidget {
  final List<VocabCard> cards;
  final String setName;

  const FlashcardFocusScreen({
    super.key,
    required this.cards,
    required this.setName,
  });

  @override
  State<FlashcardFocusScreen> createState() => _FlashcardFocusScreenState();
}

class _FlashcardFocusScreenState extends State<FlashcardFocusScreen> {
  late PageController _pageController;
  final CardService _cardService = CardService();

  int _currentIndex = 0;
  int _learnedCount = 0;
  int _learningCount = 0;

  late List<VocabCard> _sessionCards;
  late List<GlobalKey<FlashcardWidgetState>> _cardKeys;

  // 1. Biến lưu trữ các thay đổi trạng thái trong phiên học này
  // Key: cardId, Value: newState
  final Map<String, String> _pendingUpdates = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    _sessionCards = widget.cards
        .where((card) => card.state != 'learned')
        .toList();

    _cardKeys = List.generate(
      _sessionCards.length,
      (index) => GlobalKey<FlashcardWidgetState>(),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // 2. Hàm lưu tất cả tiến độ học tập một lần duy nhất
  Future<void> _saveAllProgress() async {
    if (_pendingUpdates.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      // Chuyển Map thành List định dạng bulk-update
      final updates = _pendingUpdates.entries.map((e) {
        final card = _sessionCards.firstWhere((c) => c.cardId == e.key);
        return {
          "cardId": e.key,
          "term": card.term,
          "definition": card.definition,
          "state": e.value,
        };
      }).toList();

      await _cardService.updateCardsBulk(updates: updates);
      debugPrint("✅ Đã lưu hàng loạt tiến độ học tập");
    } catch (e) {
      debugPrint("❌ Lỗi lưu bulk: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _markCard(String newState) {
    if (_sessionCards.isEmpty || _isSaving) return;

    final currentCard = _sessionCards[_currentIndex];

    setState(() {
      // Lưu vào danh sách chờ thay vì gọi API ngay
      _pendingUpdates[currentCard.cardId] = newState;

      if (newState == 'learned') {
        _learnedCount++;
      } else {
        _learningCount++;
      }
    });

    if (_currentIndex < _sessionCards.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _showCompletionDialog();
    }
  }

  Future<void> _showCompletionDialog() async {
    // Lưu dữ liệu trước khi hiện Dialog để đảm bảo an toàn
    await _saveAllProgress();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text(
          "Hoàn thành!",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Bạn đã xem hết các thẻ cần học.\n\n"
          "✅ Đã nhớ: $_learnedCount\n"
          "❌ Chưa nhớ: $_learningCount",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text("QUAY LẠI THƯ VIỆN"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_sessionCards.isEmpty) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(widget.setName.toUpperCase(), style: theme.textTheme.titleLarge),
          backgroundColor: theme.appBarTheme.backgroundColor,
          elevation: 0,
          leading: BackButton(color: theme.iconTheme.color),
        ),
        body: Center(
          child: Text(
            "Chúc mừng! Bạn đã thuộc hết bộ thẻ.",
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }

    // 3. Sử dụng PopScope để lưu dữ liệu khi nhấn nút Back vật lý hoặc AppBar back
    return PopScope(
      canPop: false, // Ngăn chặn thoát ngay lập tức
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveAllProgress(); // Lưu xong mới thoát
        if (context.mounted) Navigator.pop(context, true);
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.appBarTheme.backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
            onPressed: () async {
              await _saveAllProgress();
              if (mounted) Navigator.pop(context, true);
            },
          ),
          title: Text(
            widget.setName.toUpperCase(),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          centerTitle: true,
        ),
        body: _isSaving
            ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
            : Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.space) {
                      _cardKeys[_currentIndex].currentState?.flipCard();
                      return KeyEventResult.handled;
                    } else if (event.logicalKey ==
                        LogicalKeyboardKey.arrowLeft) {
                      _markCard('learning');
                      return KeyEventResult.handled;
                    } else if (event.logicalKey ==
                        LogicalKeyboardKey.arrowRight) {
                      _markCard('learned');
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      "${_currentIndex + 1} / ${_sessionCards.length}",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: theme.textTheme.titleMedium?.color?.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LinearProgressIndicator(
                        value: (_currentIndex + 1) / _sessionCards.length,
                        backgroundColor: theme.dividerColor,
                        color: theme.primaryColor,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 30),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (i) => setState(() => _currentIndex = i),
                        itemCount: _sessionCards.length,
                        itemBuilder: (ctx, i) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: FlashcardWidget(
                            key: _cardKeys[i],
                            frontText: _sessionCards[i].term,
                            backText: _sessionCards[i].definition,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildActionControls(),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildActionControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildActionButton(
            label: "CHƯA NHỚ",
            count: _learningCount,
            color: Colors.red,
            icon: Icons.close,
            onTap: () => _markCard('learning'),
          ),
          _buildActionButton(
            label: "ĐÃ NHỚ",
            count: _learnedCount,
            color: Colors.green,
            icon: Icons.check,
            onTap: () => _markCard('learned'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.4,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              count.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

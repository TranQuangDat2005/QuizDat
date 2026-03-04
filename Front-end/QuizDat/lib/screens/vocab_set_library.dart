import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/set_card.dart';
import '../models/card.dart';
import '../services/card_service.dart';
import '../services/set_card_service.dart';
import 'flashcard_widget.dart';
import 'set_card_management.dart';
import 'export_cards_screen.dart';
import 'flash_card_focus_screen.dart';
import 'learn_screen.dart'; // 1. BỔ SUNG IMPORT MÀN HÌNH HỌC

class VocabSetLibrary extends StatefulWidget {
  final SetCard setCard;

  const VocabSetLibrary({super.key, required this.setCard});

  @override
  State<VocabSetLibrary> createState() => _VocabSetLibraryState();
}

class _VocabSetLibraryState extends State<VocabSetLibrary> {
  bool _isLoading = true;
  List<VocabCard> _originalCards = [];
  List<VocabCard> _displayCards = [];
  bool _isShuffled = false;
  String _searchQuery = "";

  late PageController _pageController;
  final ScrollController _listScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _mainFocusNode = FocusNode();

  int _currentIndex = 0;
  List<GlobalKey<FlashcardWidgetState>> _cardKeys = [];
  final Map<String, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadCards();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _listScrollController.dispose();
    _searchController.dispose();
    _mainFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    try {
      final cards = await CardService().fetchCardsBySetId(widget.setCard.setId);
      if (mounted) {
        setState(() {
          _originalCards = List.from(cards);
          _displayCards = List.from(cards);
          _itemKeys.clear();
          for (var card in _originalCards) {
            _itemKeys[card.cardId] = GlobalKey();
          }
          _generateKeys();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _notify("Lỗi tải từ vựng: $e", Colors.red);
      }
    }
  }

  void _generateKeys() {
    _cardKeys = List.generate(
      _displayCards.length,
      (index) => GlobalKey<FlashcardWidgetState>(),
    );
  }

  void _handleSearch(String query) {
    if (query.trim().isEmpty) return;
    final q = query.toLowerCase().trim();
    try {
      final targetCard = _originalCards.firstWhere(
        (c) =>
            c.term.toLowerCase().contains(q) ||
            c.definition.toLowerCase().contains(q),
      );
      final key = _itemKeys[targetCard.cardId];
      if (key != null && key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          alignment: 0.1,
        );
      }
    } catch (e) {
      _notify("Không tìm thấy thẻ phù hợp", Colors.black54);
    }
    _mainFocusNode.requestFocus();
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffled = !_isShuffled;
      if (_isShuffled) {
        _displayCards.shuffle();
      } else {
        _displayCards = List.from(_originalCards);
      }
      _generateKeys();
      _currentIndex = 0;
    });
    if (_pageController.hasClients) _pageController.jumpToPage(0);
  }

  void _nextCard() {
    if (_currentIndex < _displayCards.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _confirmResetProgress() {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text(
            "Đặt lại tiến độ?",
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: Text(
            "Tất cả các thẻ sẽ quay về trạng thái 'Mới'. Bạn sẽ bắt đầu học lại từ đầu?",
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
                setState(() => _isLoading = true);
                try {
                  final updates = _originalCards
                      .map(
                        (c) => {
                          "cardId": c.cardId,
                          "term": c.term,
                          "definition": c.definition,
                          "state": "new",
                        },
                      )
                      .toList();
                  await CardService().updateCardsBulk(updates: updates);
                  _notify("Đã đặt lại toàn bộ tiến độ học tập", Colors.green);
                  _loadCards();
                } catch (e) {
                  _notify("Lỗi khi reset: $e", Colors.red);
                  setState(() => _isLoading = false);
                }
              },
              child: const Text("Đặt lại"),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteSet() {
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
            "Xác nhận xóa vĩnh viễn '${widget.setCard.name}'?",
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
                  await SetService().deleteSetCard(widget.setCard.setId);
                  if (!mounted) return;
                  _notify("Đã xóa học phần", Colors.green);
                  Navigator.pop(context, true);
                } catch (e) {
                  if (!mounted) return;
                  _notify("Lỗi: $e", Colors.red);
                }
              },
              child: const Text("Xóa"),
            ),
          ],
        );
      }
    );
  }

  void _notify(String m, Color c) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final learningCards = _originalCards
        .where((c) => c.state != 'learned')
        .toList();
    final masteredCards = _originalCards
        .where((c) => c.state == 'learned')
        .toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        iconTheme: theme.iconTheme,
        title: _buildSearchBox(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : Focus(
              focusNode: _mainFocusNode,
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent && _displayCards.isNotEmpty) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    _nextCard();
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    _prevCard();
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.space) {
                    if (_cardKeys.isNotEmpty &&
                        _currentIndex < _cardKeys.length) {
                      _cardKeys[_currentIndex].currentState?.flipCard();
                    }
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                onTap: () => _mainFocusNode.requestFocus(),
                child: ListView(
                  controller: _listScrollController,
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    _buildHeader(),
                    _buildStudyModes(), // 2. ĐÃ CẬP NHẬT LOGIC NÚT HỌC TẠI ĐÂY
                    const SizedBox(height: 32),
                    if (_displayCards.isNotEmpty) ...[
                      SizedBox(
                        height: 460,
                        child: Column(
                          children: [
                            Expanded(
                              child: PageView.builder(
                                controller: _pageController,
                                onPageChanged: (i) =>
                                    setState(() => _currentIndex = i),
                                itemCount: _displayCards.length,
                                itemBuilder: (ctx, i) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: FlashcardWidget(
                                    key: _cardKeys[i],
                                    frontText: _displayCards[i].term,
                                    backText: _displayCards[i].definition,
                                  ),
                                ),
                              ),
                            ),
                            _buildCarouselControls(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 50),
                    ],
                    if (learningCards.isNotEmpty)
                      _buildVocabSection("Đang học", learningCards),
                    if (masteredCards.isNotEmpty)
                      _buildVocabSection("Đã học", masteredCards),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSearchBox() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor, width: 1.5),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        onSubmitted: (_) {
          _handleSearch(_searchController.text);
          _mainFocusNode.requestFocus();
        },
        style: theme.textTheme.bodyLarge,
        cursorColor: theme.primaryColor,
        decoration: InputDecoration(
          hintText: "Tìm kiếm thuật ngữ...",
          hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38),
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search, color: theme.iconTheme.color, size: 20),
          suffixIcon: IconButton(
            icon: Icon(Icons.clear, color: theme.iconTheme.color, size: 18),
            onPressed: () {
              _searchController.clear();
              _mainFocusNode.requestFocus();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              "THƯ VIỆN: ${widget.setCard.name.toUpperCase()}",
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1.2,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: theme.iconTheme.color),
            color: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: theme.dividerColor, width: 1.5),
            ),
            onSelected: (val) async {
              if (val == 'edit') {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        SetCardManagement(setCard: widget.setCard),
                  ),
                );
                if (result == true) _loadCards();
              } else if (val == 'export') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ExportCardsScreen(
                      cards: _originalCards,
                      setName: widget.setCard.name,
                    ),
                    fullscreenDialog: true,
                  ),
                );
              } else if (val == 'reset') {
                _confirmResetProgress();
              } else if (val == 'delete') {
                _confirmDeleteSet();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(
                  'Sửa học phần',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: Text(
                  'Xuất dữ liệu (Export)',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              PopupMenuItem(
                value: 'reset',
                child: Text(
                  'Đặt lại tiến độ (Reset)',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Xóa học phần',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 2. CẬP NHẬT LOGIC NÚT HỌC Ở ĐÂY
  Widget _buildStudyModes() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        // Chế độ Thẻ ghi nhớ (Flashcard Focus)
        _buildModeBtn(Icons.copy_all, "Thẻ ghi nhớ", () {
          final cardsToStudy = _originalCards
              .where((c) => c.state != 'learned')
              .toList();
          if (cardsToStudy.isEmpty) {
            _notify("Bạn đã thuộc hết các thẻ trong bộ này rồi!", Colors.blue);
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FlashcardFocusScreen(
                cards: _originalCards,
                setName: widget.setCard.name,
              ),
            ),
          ).then((_) => _loadCards());
        }),
        const SizedBox(width: 12),

        // Chế độ Học (Learn Screen) - Đã tích hợp Bottom Sheet chọn chế độ
        _buildModeBtn(Icons.psychology, "Học", () {
          // Kiểm tra xem còn thẻ để học không
          final availableCards = _originalCards
              .where((c) => c.state != 'learned')
              .toList();
          if (availableCards.isEmpty) {
            _notify(
              "Bạn đã thuộc hết bộ thẻ này! Hãy Reset để học lại.",
              Colors.green,
            );
            return;
          }

          showModalBottomSheet(
            context: context,
            backgroundColor: Theme.of(context).cardColor,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (ctx) {
              final theme = Theme.of(context);
              return Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Chọn chế độ học",
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(
                        Icons.flash_on,
                        color: Colors.amber,
                        size: 32,
                      ),
                      title: Text(
                        "Học siêu tốc",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        "Chỉ trắc nghiệm, tập trung tốc độ.",
                        style: theme.textTheme.bodyMedium,
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LearnScreen(
                              cards: _originalCards, // Truyền hết, bên kia tự lọc
                              setName: widget.setCard.name,
                              mode: LearnMode.speed,
                            ),
                          ),
                        ).then((_) => _loadCards()); // Tải lại thẻ khi quay về
                      },
                    ),
                    Divider(color: theme.dividerColor),
                    ListTile(
                      leading: const Icon(
                        Icons.edit_note,
                        color: Colors.blue,
                        size: 32,
                      ),
                      title: Text(
                        "Học thuộc lòng",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        "Kết hợp trắc nghiệm và tự luận.",
                        style: theme.textTheme.bodyMedium,
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LearnScreen(
                              cards: _originalCards,
                              setName: widget.setCard.name,
                              mode: LearnMode.memorize,
                            ),
                          ),
                        ).then((_) => _loadCards());
                      },
                    ),
                  ],
                ),
              );
            },
          );
        }),
      ],
    ),
  );

  Widget _buildModeBtn(IconData icon, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Expanded(
        child: Material(
          color: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.dividerColor, width: 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Icon(icon, size: 32, color: theme.iconTheme.color),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  Widget _buildVocabSection(String title, List<VocabCard> cards) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$title (${cards.length})",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          ...cards.map((card) => _buildVocabListItem(card)),
        ],
      ),
    );
  }

  Widget _buildVocabListItem(VocabCard card) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      key: _itemKeys[card.cardId],
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor, width: 2.5),
        boxShadow: [
          BoxShadow(
              color: isDark ? Colors.black54 : Colors.black,
              offset: const Offset(4, 4),
              blurRadius: 0
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  card.term,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            Container(width: 2.5, color: theme.dividerColor),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  card.definition,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarouselControls() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _toggleShuffle,
            icon: Icon(
              Icons.shuffle,
              color: _isShuffled
                  ? theme.iconTheme.color
                  : theme.disabledColor,
              size: 26,
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: _prevCard,
                icon: Icon(Icons.arrow_back_ios, size: 20, color: theme.iconTheme.color),
              ),
              Text(
                "${_currentIndex + 1} / ${_displayCards.length}",
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              IconButton(
                onPressed: _nextCard,
                icon: Icon(Icons.arrow_forward_ios, size: 20, color: theme.iconTheme.color),
              ),
            ],
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

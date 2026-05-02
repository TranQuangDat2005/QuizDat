import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/set_card.dart';
import '../models/card.dart';
import '../services/card_service.dart';
import '../services/set_card_service.dart';
import '../services/sm2_service.dart';
import 'flashcard_widget.dart';
import 'set_card_management.dart';
import 'export_cards_screen.dart';
import 'flash_card_focus_screen.dart';
import 'learn_screen.dart';
import 'sm2_review_screen.dart';

class VocabSetLibrary extends StatefulWidget {
  final SetCard setCard;

  const VocabSetLibrary({super.key, required this.setCard});

  @override
  State<VocabSetLibrary> createState() => _VocabSetLibraryState();
}

class _VocabSetLibraryState extends State<VocabSetLibrary>
    with TickerProviderStateMixin {
  // ── Tab ──────────────────────────────────────────────────────────────────
  late TabController _tabController;

  // ── Data ─────────────────────────────────────────────────────────────────
  bool _isLoading = true;
  List<VocabCard> _originalCards = [];
  List<VocabCard> _displayCards = [];

  // ── SM-2 ─────────────────────────────────────────────────────────────────
  int _sm2DueCount = 0;
  int _sm2NewCount = 0;
  int _sm2LearnedCount = 0; // thẻ không cần ôn hôm nay
  Map<String, int> _sm2DailyStats = {};
  final SM2Service _sm2Service = SM2Service();
  /// true  = cột "Thuật ngữ" là ngôn ngữ muốn học (mặc định)
  /// false = cột "Định nghĩa" là ngôn ngữ muốn học
  bool _termIsLearning = true;

  // ── Flashcard viewer ─────────────────────────────────────────────────────
  bool _isShuffled = false;
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
    _tabController = TabController(length: 2, vsync: this);
    _pageController = PageController(initialPage: 0);
    _loadCards();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    _listScrollController.dispose();
    _searchController.dispose();
    _mainFocusNode.dispose();
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _loadCards() async {
    setState(() => _isLoading = true);
    try {
      final cards = await CardService().fetchCardsBySetId(widget.setCard.setId);
      if (!mounted) return;
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
      await _loadSm2Stats();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _notify('Lỗi tải từ vựng: $e', Colors.red);
      }
    }
  }

  Future<void> _loadSm2Stats() async {
    if (_originalCards.isEmpty) return;
    final result = await _sm2Service.getCardsForReviewWithLimits(_originalCards);
    final stats = await _sm2Service.getDailyStats();
    if (!mounted) return;
    setState(() {
      _sm2NewCount = result.newCards.length;
      _sm2DueCount = result.dueCards.length;
      _sm2LearnedCount = _originalCards.length - result.newCards.length - result.dueCards.length;
      if (_sm2LearnedCount < 0) _sm2LearnedCount = 0;
      _sm2DailyStats = stats;
    });
  }

  // ── Flashcard helpers ─────────────────────────────────────────────────────

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
      _notify('Không tìm thấy thẻ phù hợp', Colors.red);
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

  void _notify(String m, Color c) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _confirmResetProgress() {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text('Đặt lại tiến độ?',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          content: Text('Tất cả thẻ về trạng thái Mới.',
              style: theme.textTheme.bodyMedium),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Hủy', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                try {
                  final updates = _originalCards
                      .map((c) => {'cardId': c.cardId, 'term': c.term, 'definition': c.definition, 'state': 'new'})
                      .toList();
                  await CardService().updateCardsBulk(updates: updates);
                  _notify('Đã đặt lại tiến độ', Colors.green);
                  _loadCards();
                } catch (e) {
                  _notify('Lỗi: $e', Colors.red);
                  setState(() => _isLoading = false);
                }
              },
              child: const Text('Đặt lại'),
            ),
          ],
        );
      },
    );
  }

  void _confirmResetSm2() {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text('Reset tiến độ SM-2?',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          content: Text('Toàn bộ lịch ôn tập SM-2 sẽ bị xóa và bắt đầu lại từ đầu.',
              style: theme.textTheme.bodyMedium),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Hủy', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                await _sm2Service.resetProgressForSet(widget.setCard.setId);
                _notify('Đã reset SM-2 từ đầu', Colors.green);
                _loadSm2Stats();
              },
              child: const Text('Reset'),
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
          title: Text('Xóa học phần?',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          content: Text("Xác nhận xóa '${widget.setCard.name}'?",
              style: theme.textTheme.bodyMedium),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Hủy', style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await SetService().deleteSetCard(widget.setCard.setId);
                  if (!mounted) return;
                  _notify('Đã xóa học phần', Colors.green);
                  Navigator.pop(context, true);
                } catch (e) {
                  if (!mounted) return;
                  _notify('Lỗi: $e', Colors.red);
                }
              },
              child: const Text('Xóa'),
            ),
          ],
        );
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════

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
        title: _buildSearchBox(),
        actions: [
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
                    builder: (context) => SetCardManagement(setCard: widget.setCard),
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
                child: Text('Sửa học phần',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
              PopupMenuItem(
                value: 'export',
                child: Text('Xuất dữ liệu (Export)',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
              PopupMenuItem(
                value: 'reset',
                child: Text('Đặt lại tiến độ (Reset)',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Xóa học phần',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            const Tab(icon: Icon(Icons.school_outlined, size: 20), text: 'Học'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, size: 18),
                  const SizedBox(width: 6),
                  const Text('Ôn SM-2', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  if (_sm2DueCount + _sm2NewCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_sm2DueCount + _sm2NewCount}',
                        style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildQuizletTab(),
                _buildSm2Tab(),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════
  // TAB 1: QUIZLET (Học)
  // ═══════════════════════════════════════

  Widget _buildQuizletTab() {
    final theme = Theme.of(context);
    final learningCards = _originalCards.where((c) => c.state != 'learned').toList();
    final masteredCards = _originalCards.where((c) => c.state == 'learned').toList();

    return Focus(
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
            if (_cardKeys.isNotEmpty && _currentIndex < _cardKeys.length) {
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
            _buildSetHeader(),
            _buildStudyModeButtons(),
            const SizedBox(height: 24),
            // Flashcard carousel
            if (_displayCards.isNotEmpty) ...[
              SizedBox(
                height: 460,
                child: Column(
                  children: [
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (i) => setState(() => _currentIndex = i),
                        itemCount: _displayCards.length,
                        itemBuilder: (ctx, i) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
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
              const SizedBox(height: 40),
            ],
            if (learningCards.isNotEmpty)
              _buildVocabSection('Đang học', learningCards),
            if (masteredCards.isNotEmpty)
              _buildVocabSection('Đã học', masteredCards),
          ],
        ),
      ),
    );
  }

  Widget _buildSetHeader() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        'THƯ VIỆN: ${widget.setCard.name.toUpperCase()}',
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 1.2,
          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildStudyModeButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildModeBtn(Icons.copy_all, 'Thẻ ghi nhớ', () {
            if (_originalCards.isEmpty) {
              _notify('Chưa có thẻ nào!', Colors.red);
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
          _buildModeBtn(Icons.psychology, 'Học', () {
            final available = _originalCards.where((c) => c.state != 'learned').toList();
            if (available.isEmpty) {
              _notify('Bạn đã thuộc hết! Hãy Reset để học lại.', Colors.green);
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
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chọn chế độ học',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.flash_on, color: Colors.amber, size: 32),
                        title: Text('Học siêu tốc', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        subtitle: Text('Chỉ trắc nghiệm, tập trung tốc độ.', style: theme.textTheme.bodyMedium),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LearnScreen(
                                cards: _originalCards,
                                setName: widget.setCard.name,
                                mode: LearnMode.speed,
                              ),
                            ),
                          ).then((_) => _loadCards());
                        },
                      ),
                      Divider(color: theme.dividerColor),
                      ListTile(
                        leading: const Icon(Icons.edit_note, color: Colors.blue, size: 32),
                        title: Text('Học thuộc lòng', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        subtitle: Text('Kết hợp trắc nghiệm và tự luận.', style: theme.textTheme.bodyMedium),
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
  }

  Widget _buildModeBtn(IconData icon, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
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
                Text(label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCarouselControls() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, left: 16, right: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _toggleShuffle,
            icon: Icon(
              Icons.shuffle,
              color: _isShuffled ? theme.iconTheme.color : theme.disabledColor,
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
                '${_currentIndex + 1} / ${_displayCards.length}',
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

  Widget _buildVocabSection(String title, List<VocabCard> cards) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${cards.length})',
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
            blurRadius: 0,
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
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
                ),
              ),
            ),
          ],
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
        onSubmitted: (_) {
          _handleSearch(_searchController.text);
          _mainFocusNode.requestFocus();
        },
        style: theme.textTheme.bodyLarge,
        cursorColor: theme.colorScheme.primary,
        decoration: InputDecoration(
          hintText: 'Tìm kiếm thuật ngữ...',
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

  // ═══════════════════════════════════════
  // TAB 2: ANKI SM-2 (Ôn tập)
  // ═══════════════════════════════════════

  Widget _buildSm2Tab() {
    final theme = Theme.of(context);
    final totalDue = _sm2DueCount + _sm2NewCount;
    final totalCards = _originalCards.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tiêu đề ──────────────────────────────────────────────────────
          Text(
            'Lặp lại ngắt quãng',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Thuật toán SM-2 — lên lịch ôn tập thông minh',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // ── Daily Limits Stats ───────────────────────────────────────────
          if (_sm2DailyStats.isNotEmpty) ...[
            Text('Tiến độ hôm nay', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildDailyLimitProgress(
              label: 'Thẻ mới',
              studied: _sm2DailyStats['new_studied']!,
              limit: _sm2DailyStats['new_limit']!,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            _buildDailyLimitProgress(
              label: 'Thẻ ôn',
              studied: _sm2DailyStats['review_studied']!,
              limit: _sm2DailyStats['review_limit']!,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 32),
          ],

          // ── Stats cards ───────────────────────────────────────────────────
          Row(
            children: [
              _buildStatCard('Thẻ mới chờ ôn', _sm2NewCount, theme.colorScheme.primary, Icons.fiber_new_outlined),
              const SizedBox(width: 12),
              _buildStatCard('Thẻ cũ cần ôn', _sm2DueCount, theme.colorScheme.primary, Icons.replay_outlined),
            ],
          ),

          const SizedBox(height: 24),

          // ── Progress bar tổng ─────────────────────────────────────────────
          if (totalCards > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tiến độ tổng của học phần',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                Text('$_sm2LearnedCount / $totalCards',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: totalCards > 0 ? _sm2LearnedCount / totalCards : 0.0,
                minHeight: 8,
                backgroundColor: theme.dividerColor,
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Chọn chiều học ────────────────────────────────────────────────
          _buildLearningDirectionSelector(),

          const SizedBox(height: 20),

          // ── Nút bắt đầu ôn ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: totalDue == 0
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Sm2ReviewScreen(
                            allCards: _originalCards,
                            setName: widget.setCard.name,
                            termIsLearning: _termIsLearning,
                          ),
                        ),
                      ).then((_) {
                        _loadCards();
                        _loadSm2Stats();
                      });
                    },
              icon: const Icon(Icons.play_arrow_rounded, size: 28),
              label: Text(
                totalDue > 0 ? 'Bắt đầu ôn tập ($totalDue thẻ)' : 'Không có thẻ cần ôn hôm nay 🎉',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: totalDue > 0 ? theme.colorScheme.primary : theme.disabledColor,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: totalDue > 0 ? 4 : 0,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Hướng dẫn SM-2 ────────────────────────────────────────────────
          _buildSm2InfoPanel(),

          const SizedBox(height: 16),

          // ── Reset option ─────────────────────────────────────────────────
          TextButton.icon(
            onPressed: _confirmResetSm2,
            icon: Icon(Icons.refresh, color: theme.colorScheme.onSurface, size: 18),
            label: Text('Reset tiến độ SM-2',
                style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Widget chọn chiều học ─────────────────────────────────────────────────

  Widget _buildLearningDirectionSelector() {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.swap_horiz, size: 18, color: primary),
          const SizedBox(width: 6),
          Text('Ngôn ngữ muốn học',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: primary)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _buildDirOption(
            label: 'Thuật ngữ (trái)',
            sublabel: 'Cột trái = Ngôn ngữ học',
            isSelected: _termIsLearning,
            onTap: () => setState(() => _termIsLearning = true),
          )),
          const SizedBox(width: 10),
          Expanded(child: _buildDirOption(
            label: 'Định nghĩa (phải)',
            sublabel: 'Cột phải = Ngôn ngữ học',
            isSelected: !_termIsLearning,
            onTap: () => setState(() => _termIsLearning = false),
          )),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: primary.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            Icon(Icons.info_outline, size: 14, color: primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _termIsLearning
                    ? 'Lật thẻ: Thuật ngữ → Định nghĩa và ngược lại\nTự luận: Xem Định nghĩa → Viết Thuật ngữ'
                    : 'Lật thẻ: Định nghĩa → Thuật ngữ và ngược lại\nTự luận: Xem Thuật ngữ → Viết Định nghĩa',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: primary,
                  height: 1.5,
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildDirOption({
    required String label,
    required String sublabel,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.1) : theme.cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? primary : theme.dividerColor,
            width: isSelected ? 2 : 1.5,
          ),
        ),
        child: Row(children: [
          Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
            color: isSelected ? primary : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? primary : null,
                )),
            Text(sublabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ])),
        ]),
      ),
    );
  }

  Widget _buildStatCard(String label, int count, Color color, IconData icon) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSm2InfoPanel() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Cách hoạt động', style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('🔴 Lại', 'Quên — ôn lại ngay trong session hiện tại'),
          _buildInfoRow('🟠 Khó', 'Nhớ được nhưng khó — khoảng cách ngắn'),
          _buildInfoRow('🟢 Tốt', 'Nhớ sau khi suy nghĩ — khoảng cách vừa'),
          _buildInfoRow('💙 Dễ', 'Nhớ ngay — khoảng cách dài hơn nhiều'),
          const SizedBox(height: 8),
          Text(
            'Khoảng cách ôn tập tăng dần theo cấp số nhân, giúp nhớ lâu hơn với ít lần ôn hơn.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String desc) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(desc, style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyLimitProgress({
    required String label,
    required int studied,
    required int limit,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final isDone = studied >= limit;
    final progress = limit > 0 ? (studied / limit).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(
              isDone ? 'Đã đạt giới hạn hôm nay' : '$studied / $limit',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDone ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: theme.dividerColor,
            valueColor: AlwaysStoppedAnimation<Color>(isDone ? theme.colorScheme.primary : color),
          ),
        ),
      ],
    );
  }
}

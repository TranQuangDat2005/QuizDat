import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../models/card.dart';
import '../services/card_service.dart';
import '../services/set_card_service.dart';

enum LearnMode { speed, memorize }

enum QuestionType { multipleChoice, written }

class CardProgress {
  final VocabCard card;
  bool passedMC = false;
  bool passedWritten = false;

  CardProgress(this.card);
}

class LearnScreen extends StatefulWidget {
  final List<VocabCard> cards;
  final String setName;
  final LearnMode mode;

  const LearnScreen({
    super.key,
    required this.cards,
    required this.setName,
    required this.mode,
  });

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  final CardService _cardService = CardService();
  final SetService _setService = SetService();

  late List<CardProgress> _allProgressItems;
  late List<CardProgress> _pool;
  List<CardProgress> _currentBatch = [];
  List<CardProgress> _roundQueue = [];

  int _totalSteps = 0;
  int _completedSteps = 0;
  int _currentStreak = 0;

  CardProgress? _currentProgress;
  QuestionType _currentType = QuestionType.multipleChoice;
  List<String> _mcOptions = [];

  bool _isChecking = false;
  String? _selectedOption;

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final FocusNode _screenFocusNode = FocusNode();

  bool _showWrittenCorrection = false;

  bool _enableMC = true;
  bool _enableWritten = true;
  bool _isShuffled = false;

  final Map<String, String> _pendingUpdates = {};
  bool _isSaving = false;
  bool _isRoundSummary = false;

  bool _allowPop = false;

  @override
  void initState() {
    super.initState();

    if (widget.mode == LearnMode.speed) {
      _enableMC = true;
      _enableWritten = false;
    } else {
      _enableMC = true;
      _enableWritten = true;
    }

    _allProgressItems = widget.cards
        .where((c) => c.state != 'learned')
        .map((c) => CardProgress(c))
        .toList();

    _pool = List.from(_allProgressItems);
    if (_isShuffled) _pool.shuffle();

    _recalculateTotalSteps();
    _startNextBatch();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    _screenFocusNode.dispose();
    super.dispose();
  }

  void _recalculateTotalSteps() {
    int cardCount = widget.cards.length;
    int multiplier = 0;
    if (_enableMC) multiplier++;
    if (_enableWritten) multiplier++;
    if (multiplier == 0) multiplier = 1;

    setState(() {
      _totalSteps = cardCount * multiplier;
      int preLearned = widget.cards.where((c) => c.state == 'learned').length;
      _completedSteps = preLearned * multiplier;

      for (var item in _allProgressItems) {
        if (_enableMC && item.passedMC) _completedSteps++;
        if (_enableWritten && item.passedWritten) _completedSteps++;
      }
    });
  }

  // FIX QUAN TRỌNG: Sửa logic để tránh vòng lặp vô tận
  void _startNextBatch() {
    // Nếu hết thẻ trong kho (_pool rỗng), dừng lại ngay
    if (_pool.isEmpty) {
      setState(() {
        _isRoundSummary = false;
        _currentBatch = [];
        _roundQueue = [];
      });
      // KHÔNG gọi _nextCard() ở đây nữa.
      // Việc _currentBatch rỗng và _isRoundSummary = false sẽ kích hoạt màn hình "Hoàn thành" trong hàm build.
      return;
    }

    setState(() {
      _isRoundSummary = false;
      int count = min(7, _pool.length);
      _currentBatch = _pool.take(count).toList();
      _pool.removeRange(0, count);
      _roundQueue = List.from(_currentBatch);
    });
    _nextCard();
  }

  void _nextCard() {
    if (_roundQueue.isEmpty) {
      setState(() => _isRoundSummary = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).requestFocus(_screenFocusNode);
      });
      return;
    }

    setState(() {
      _currentProgress = _roundQueue.removeAt(0);
      _showWrittenCorrection = false;
      _isChecking = false;
      _selectedOption = null;
      _inputController.clear();
      _determineQuestionType();
    });
  }

  void _determineQuestionType() {
    if (_currentProgress == null) return;

    if (widget.mode == LearnMode.speed) {
      _currentType = QuestionType.multipleChoice;
    } else {
      if (_enableMC && !_currentProgress!.passedMC) {
        _currentType = QuestionType.multipleChoice;
      } else if (_enableWritten) {
        _currentType = QuestionType.written;
      } else {
        _currentType = QuestionType.multipleChoice;
      }
    }

    if (_currentType == QuestionType.multipleChoice) {
      _generateMCOptions();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocusNode.requestFocus();
      });
    }
  }

  void _reevaluateCurrentCard() {
    if (_currentProgress == null) return;
    _recalculateTotalSteps();

    bool isMCSatisfied = !_enableMC || _currentProgress!.passedMC;
    bool isWrittenSatisfied =
        !_enableWritten || _currentProgress!.passedWritten;

    if (isMCSatisfied && isWrittenSatisfied) {
      _pendingUpdates[_currentProgress!.card.cardId] = 'learned';
      _nextCard();
    } else {
      if (_currentType == QuestionType.written && !_enableWritten) {
        _currentType = QuestionType.multipleChoice;
        _generateMCOptions();
      } else if (_currentType == QuestionType.multipleChoice && !_enableMC) {
        _currentType = QuestionType.written;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _inputFocusNode.requestFocus();
        });
      }
    }
  }

  void _generateMCOptions() {
    if (_currentProgress == null) return;
    final correct = _currentProgress!.card.definition;

    List<String> allDefs = widget.cards
        .where((c) => c.definition != correct)
        .map((c) => c.definition)
        .toSet()
        .toList();
    allDefs.shuffle();

    _mcOptions = allDefs.take(3).toList();
    _mcOptions.add(correct);
    _mcOptions.shuffle();
  }

  void _handleAnswer(String userAnswer) {
    if (_isChecking || _currentProgress == null) return;

    final correctAnswer = _currentType == QuestionType.multipleChoice
        ? _currentProgress!.card.definition
        : _currentProgress!.card.term;

    bool isCorrect =
        userAnswer.trim().toLowerCase() == correctAnswer.trim().toLowerCase();

    setState(() {
      _isChecking = true;
      _selectedOption = userAnswer;

      if (isCorrect) {
        _currentStreak++;
        _completedSteps++;

        if (_currentType == QuestionType.multipleChoice) {
          _currentProgress!.passedMC = true;
          if (widget.mode == LearnMode.memorize && _enableWritten) {
            _roundQueue.add(_currentProgress!);
          } else {
            _pendingUpdates[_currentProgress!.card.cardId] = 'learned';
          }
        } else {
          _currentProgress!.passedWritten = true;
          _pendingUpdates[_currentProgress!.card.cardId] = 'learned';
        }
      } else {
        _currentStreak = 0;
        _pendingUpdates[_currentProgress!.card.cardId] = 'learning';
        _roundQueue.add(_currentProgress!);
      }
    });

    if (isCorrect) {
      Future.delayed(const Duration(milliseconds: 1000), _nextCard);
    } else {
      if (_currentType == QuestionType.written) {
        setState(() => _showWrittenCorrection = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          FocusScope.of(context).requestFocus(_screenFocusNode);
        });
      } else {
        Future.delayed(const Duration(milliseconds: 2000), _nextCard);
      }
    }
  }

  Future<void> _saveAndExit() async {
    if (_pendingUpdates.isNotEmpty) {
      setState(() => _isSaving = true);
      try {
        final updates = _pendingUpdates.entries.map((e) {
          final card = widget.cards.firstWhere((c) => c.cardId == e.key);
          return {
            "cardId": e.key,
            "term": card.term,
            "definition": card.definition,
            "state": e.value,
          };
        }).toList();
        await _cardService.updateCardsBulk(updates: updates);
        
        if (widget.cards.isNotEmpty) {
          await _setService.updateSetCard(
            widget.cards.first.setId,
            lastLearnedTime: DateTime.now(),
          );
        }
      } catch (e) {
        debugPrint("Lỗi save: $e");
      }
    }

    if (mounted) {
      setState(() {
        _allowPop = true;
      });
      Navigator.pop(context, true);
    }
  }

  void _resetProgress() async {
    Navigator.pop(context); // Đóng modal nếu đang mở

    setState(() => _isSaving = true);
    final updates = widget.cards
        .map(
          (c) => {
            "cardId": c.cardId,
            "term": c.term,
            "definition": c.definition,
            "state": "new",
          },
        )
        .toList();
    await _cardService.updateCardsBulk(updates: updates);
    if (mounted) {
      setState(() {
        _isSaving = false;
        _currentStreak = 0;
        _completedSteps = 0;

        _allProgressItems = widget.cards.map((c) => CardProgress(c)).toList();
        _pool = List.from(_allProgressItems);

        if (_isShuffled) _pool.shuffle();

        _recalculateTotalSteps();
        _startNextBatch();
      });
    }
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Tùy chọn học",
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  title: Text(
                    "Xáo trộn thẻ",
                    style: theme.textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    "Áp dụng cho các vòng sau",
                    style: theme.textTheme.bodySmall,
                  ),
                  value: _isShuffled,
                  activeColor: theme.primaryColor,
                  onChanged: (val) {
                    setModalState(() => _isShuffled = val);
                    setState(() {
                      _isShuffled = val;
                      if (_isShuffled) {
                        _pool.shuffle();
                      } else {
                        _pool.sort(
                          (a, b) => widget.cards
                              .indexOf(a.card)
                              .compareTo(widget.cards.indexOf(b.card)),
                        );
                      }
                    });
                  },
                ),
                Divider(color: theme.dividerColor),
                if (widget.mode == LearnMode.memorize) ...[
                  SwitchListTile(
                    title: Text(
                      "Trắc nghiệm",
                      style: theme.textTheme.bodyMedium,
                    ),
                    value: _enableMC,
                    activeColor: theme.primaryColor,
                    onChanged: (val) {
                      if (!val && !_enableWritten) return;
                      setModalState(() => _enableMC = val);
                      setState(() {
                        _enableMC = val;
                        _reevaluateCurrentCard();
                      });
                    },
                  ),
                  SwitchListTile(
                    title: Text(
                      "Tự luận",
                      style: theme.textTheme.bodyMedium,
                    ),
                    value: _enableWritten,
                    activeColor: theme.primaryColor,
                    onChanged: (val) {
                      if (!val && !_enableMC) return;
                      setModalState(() => _enableWritten = val);
                      setState(() {
                        _enableWritten = val;
                        _reevaluateCurrentCard();
                      });
                    },
                  ),
                  Divider(color: theme.dividerColor),
                ],
                ListTile(
                  leading: const Icon(Icons.refresh, color: Colors.red),
                  title: const Text(
                    "Đặt lại tiến trình học",
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: _resetProgress,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isSaving) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: theme.primaryColor)),
      );
    }

    // Màn hình hoàn thành (Trophy)
    if (_currentBatch.isEmpty && !_isRoundSummary) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          leading: CloseButton(color: theme.iconTheme.color),
          backgroundColor: theme.appBarTheme.backgroundColor,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.emoji_events, size: 80, color: Colors.amber),
                const SizedBox(height: 20),
                Text(
                  "Bạn đã thuộc hết các thẻ!",
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                // FIX: Thêm nút để thoát ra ngoài library
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saveAndExit, // Gọi hàm save để thoát
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4255FF),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      "Hoàn thành & Quay về",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _resetProgress,
                  child: Text("Học lại từ đầu", style: TextStyle(color: theme.primaryColor)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isRoundSummary) return _buildRoundSummaryUI();

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveAndExit();
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.appBarTheme.backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close, color: theme.iconTheme.color),
            onPressed: _saveAndExit,
          ),
          title: _buildSegmentedProgressBar(),
          actions: [
            IconButton(
              icon: Icon(Icons.settings_outlined, color: theme.iconTheme.color),
              onPressed: _showSettings,
            ),
          ],
        ),
        body: GestureDetector(
          onTap: () {
            if (_showWrittenCorrection) {
              _nextCard();
            } else if (_currentType == QuestionType.written) {
              _inputFocusNode.requestFocus();
            }
          },
          behavior: HitTestBehavior.translucent,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _currentType == QuestionType.multipleChoice
                ? _buildMCView()
                : _buildWrittenView(),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedProgressBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    bool isOnFire = _currentStreak >= 10;
    Color activeColor = isOnFire ? Colors.orange : const Color(0xFF2DCF89);

    double targetProgress = _totalSteps > 0
        ? _completedSteps / _totalSteps
        : 0.0;

    if (targetProgress > 1.0) targetProgress = 1.0;
    if (targetProgress < 0.0) targetProgress = 0.0;

    int batchSize = 7;
    int totalCards = widget.cards.length;
    int totalSegments = (totalCards / batchSize).ceil();

    if (_totalSteps == 0) return const SizedBox();

    return Row(
      children: [
        if (isOnFire) ...[
          const Icon(
            Icons.local_fire_department,
            color: Colors.orange,
            size: 24,
          ),
          const SizedBox(width: 8),
        ],

        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              double gapSize = 4.0;

              double totalGapWidth = (totalSegments - 1) * gapSize;
              if (totalGapWidth < 0) totalGapWidth = 0;
              double availableWidth = totalWidth - totalGapWidth;

              return TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(end: targetProgress),
                builder: (context, value, child) {
                  double animatedCompletedSteps = value * _totalSteps;
                  double progressInCardsEquivalent =
                      (animatedCompletedSteps / _totalSteps) * totalCards;

                  double thumbPos = 0.0;
                  int fullSegments = (progressInCardsEquivalent / batchSize)
                      .floor();
                  double remainder = progressInCardsEquivalent % batchSize;

                  for (int i = 0; i < fullSegments; i++) {
                    int cardsInSeg = (i == totalSegments - 1)
                        ? (totalCards % batchSize == 0
                              ? batchSize
                              : totalCards % batchSize)
                        : batchSize;
                    double segWidth =
                        (cardsInSeg / totalCards) * availableWidth;
                    thumbPos += segWidth + gapSize;
                  }

                  if (fullSegments < totalSegments) {
                    double segWidth = (remainder / totalCards) * availableWidth;
                    thumbPos += segWidth;
                  }

                  if (thumbPos > totalWidth) thumbPos = totalWidth;

                  return SizedBox(
                    height: 24,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      clipBehavior: Clip.none,
                      children: [
                        Row(
                          children: List.generate(totalSegments, (index) {
                            int cardsInThisSegment = 7;
                            if (index == totalSegments - 1) {
                              int remainder = totalCards % 7;
                              if (remainder > 0) cardsInThisSegment = remainder;
                            }

                            int startCardIndex = index * 7;
                            double fillPercent = 0.0;
                            if (progressInCardsEquivalent >=
                                startCardIndex + cardsInThisSegment) {
                              fillPercent = 1.0;
                            } else if (progressInCardsEquivalent >
                                startCardIndex) {
                              fillPercent =
                                  (progressInCardsEquivalent - startCardIndex) /
                                  cardsInThisSegment;
                            }

                            return Expanded(
                              flex: cardsInThisSegment,
                              child: Container(
                                margin: EdgeInsets.only(
                                  right: index < totalSegments - 1
                                      ? gapSize
                                      : 0,
                                ),
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: fillPercent,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: activeColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),

                        Positioned(
                          left: (thumbPos - 12).clamp(0.0, totalWidth - 24),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: activeColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? Colors.black : Colors.white,
                                width: 2.5,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                "$_completedSteps",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),

        const SizedBox(width: 12),

        Text(
          "$_totalSteps",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMCView() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: Center(
            child: SingleChildScrollView(
              child: Text(
                _currentProgress!.card.term,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Text(
          "Chọn thuật ngữ đúng",
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ..._mcOptions.map((opt) => _buildOptionButton(opt)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildOptionButton(String optionText) {
    bool isSelected = _selectedOption == optionText;
    bool isCorrectOption = optionText == _currentProgress!.card.definition;
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color bgColor = theme.cardColor;
    Color borderColor = theme.dividerColor;
    Color textColor = theme.textTheme.bodyMedium?.color ?? Colors.black;
    IconData? icon;

    if (_isChecking) {
      if (isCorrectOption) {
        bgColor = isDark ? Colors.green.withOpacity(0.2) : const Color(0xFFE8F5E9);
        borderColor = Colors.green;
        textColor = Colors.green;
        icon = Icons.check_circle;
      } else if (isSelected && !isCorrectOption) {
        bgColor = isDark ? Colors.red.withOpacity(0.2) : const Color(0xFFFFEBEE);
        borderColor = Colors.red;
        textColor = Colors.red;
        icon = Icons.cancel;
      } else {
        textColor = theme.disabledColor;
        borderColor = theme.dividerColor.withOpacity(0.5);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: borderColor, width: 2),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        onPressed: _isChecking ? null : () => _handleAnswer(optionText),
        child: Row(
          children: [
            Expanded(
              child: Text(
                optionText,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, color: textColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWrittenView() {
    final theme = Theme.of(context);
    if (_showWrittenCorrection) return _buildCorrectionView();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Định nghĩa", style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)),
              const SizedBox(height: 16),
              SingleChildScrollView(
                child: Text(
                  _currentProgress!.card.definition,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        TextField(
          controller: _inputController,
          focusNode: _inputFocusNode,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Nhập thuật ngữ",
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) => _handleAnswer(val.trim()),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                if (_currentProgress!.card.term.isNotEmpty) {
                  _inputController.text = _currentProgress!.card.term.substring(
                    0,
                    1,
                  );
                  _inputFocusNode.requestFocus();
                }
              },
              child: Text(
                "Gợi ý",
                style: TextStyle(fontWeight: FontWeight.bold, color: theme.primaryColor),
              ),
            ),
            TextButton(
              onPressed: () => _handleAnswer("___DONT_KNOW___"),
              child: const Text(
                "Bạn không biết?",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCorrectionView() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RawKeyboardListener(
      focusNode: _screenFocusNode,
      autofocus: true,
      onKey: (event) {
        if (event is RawKeyDownEvent) _nextCard();
      },
      child: GestureDetector(
        onTap: _nextCard,
        behavior: HitTestBehavior.translucent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Đừng lo, bạn vẫn đang học!",
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? Colors.green.withOpacity(0.2) : const Color(0xFFE8F5E9),
                border: Border.all(color: Colors.green),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "ĐÁP ÁN ĐÚNG",
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentType == QuestionType.multipleChoice
                        ? _currentProgress!.card.definition
                        : _currentProgress!.card.term,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? Colors.red.withOpacity(0.2) : const Color(0xFFFFEBEE),
                border: Border.all(color: Colors.red),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "BẠN ĐÃ TRẢ LỜI",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedOption == "___DONT_KNOW___"
                        ? "Không biết"
                        : (_selectedOption ?? ""),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 18,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _nextCard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4255FF),
                ),
                child: const Text(
                  "Tiếp tục",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundSummaryUI() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RawKeyboardListener(
      focusNode: _screenFocusNode,
      autofocus: true,
      onKey: (event) {
        if (event is RawKeyDownEvent) _startNextBatch();
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: GestureDetector(
          onTap: _startNextBatch,
          child: Container(
            color: Colors.transparent,
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.all(24.0),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    "Vòng này đã xong!",
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Tiếp tục giữ vững phong độ nhé (Streak: $_currentStreak)",
                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    "Thuật ngữ trong vòng này",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _currentBatch.length,
                      itemBuilder: (ctx, i) {
                        final card = _currentBatch[i].card;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(8),
                            border: isDark ? Border.all(color: theme.dividerColor) : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  card.term,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  card.definition,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4255FF),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        "Nhấn phím bất kỳ để tiếp tục",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

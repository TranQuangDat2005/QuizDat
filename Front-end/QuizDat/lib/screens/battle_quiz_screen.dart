import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auto_size_text/auto_size_text.dart';
import '../providers/battle_provider.dart';
import '../models/card.dart';
import 'dart:math';

class BattleQuizScreen extends StatefulWidget {
  const BattleQuizScreen({super.key});

  @override
  State<BattleQuizScreen> createState() => _BattleQuizScreenState();
}

class _BattleQuizScreenState extends State<BattleQuizScreen>
    with TickerProviderStateMixin {
  List<VocabCard> _cards = [];

  // Options for the current question
  List<String> _currentOptions = [];
  int _lastGeneratedIndex = -1;

  // Whether the local player has already answered this question
  bool _hasAnsweredThisQuestion = false;

  // Result feedback
  bool? _localAnswerResult;
  String? _selectedOption;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // Leaderboard toggle for mobile
  bool _showLeaderboard = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 12).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<BattleProvider>();
      setState(() {
        _cards = List.from(provider.quizCards);
        _regenerateOptionsIfNeeded(provider.currentQuestionIndex);
      });
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _regenerateOptionsIfNeeded(int questionIndex) {
    if (questionIndex == _lastGeneratedIndex) return;
    if (questionIndex >= _cards.length) return;

    _lastGeneratedIndex = questionIndex;
    _hasAnsweredThisQuestion = false;
    _localAnswerResult = null;
    _selectedOption = null;

    final currentCard = _cards[questionIndex];
    final correctAnswer = currentCard.definition;

    final otherCards =
        _cards.where((c) => c.cardId != currentCard.cardId).toList();
    otherCards.shuffle(Random());

    final wrongAnswers = otherCards.take(3).map((c) => c.definition).toList();
    _currentOptions = [correctAnswer, ...wrongAnswers]..shuffle(Random());
  }

  void _handleAnswer(String selectedAnswer, BattleProvider provider) {
    if (_hasAnsweredThisQuestion) return;
    if (provider.isQuestionLocked) return;
    if (provider.isGameOver) return;

    final currentCard = _cards[provider.currentQuestionIndex];
    final isCorrect = selectedAnswer == currentCard.definition;

    setState(() {
      _hasAnsweredThisQuestion = true;
      _localAnswerResult = isCorrect;
      _selectedOption = selectedAnswer;
    });

    provider.submitAnswer(isCorrect);

    if (!isCorrect) {
      _shakeController.forward(from: 0);
    }
  }

  bool _isWideScreen(BuildContext context) {
    return MediaQuery.of(context).size.width > 700;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = _isWideScreen(context);

    return Consumer<BattleProvider>(
      builder: (context, provider, _) {
        // Sync cards if needed
        if (_cards.isEmpty && provider.quizCards.isNotEmpty) {
          _cards = List.from(provider.quizCards);
        }

        // Regenerate options when question changes
        _regenerateOptionsIfNeeded(provider.currentQuestionIndex);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            bool? confirm = await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Rời khỏi trận đấu?'),
                content: const Text('Nếu thoát, bạn sẽ mất kết nối với phòng.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Hủy')),
                  TextButton(
                    onPressed: () {
                      provider.disconnect();
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('Thoát',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
            if (confirm == true && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(provider.selectedSet?.name ?? 'Đấu Trường'),
              backgroundColor: theme.colorScheme.surface,
              elevation: 0,
              actions: [
                if (!isWide && !provider.isGameOver)
                  IconButton(
                    icon: Stack(
                      children: [
                        const Icon(Icons.leaderboard),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 14, minHeight: 14,
                            ),
                            child: Text(
                              '${provider.players.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 9),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                    tooltip: 'Bảng xếp hạng',
                    onPressed: () {
                      setState(() => _showLeaderboard = !_showLeaderboard);
                    },
                  ),
              ],
            ),
            body: Stack(
              children: [
                // Main content
                isWide
                    ? Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildMainContent(theme, provider),
                          ),
                          Container(
                            width: 260,
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              border: Border(
                                  left: BorderSide(color: theme.dividerColor)),
                            ),
                            child: _buildLeaderboard(theme, provider),
                          ),
                        ],
                      )
                    : _buildMainContent(theme, provider),

                // Mobile leaderboard overlay
                if (!isWide && _showLeaderboard && !provider.isGameOver)
                  _buildMobileLeaderboardOverlay(theme, provider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainContent(ThemeData theme, BattleProvider provider) {
    if (provider.isGameOver) {
      return _buildGameSummary(theme, provider);
    }
    if (_cards.isEmpty || _currentOptions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return _buildQuizArea(theme, provider);
  }

  Widget _buildQuizArea(ThemeData theme, BattleProvider provider) {
    final currentIndex = provider.currentQuestionIndex;
    final currentCard = _cards[currentIndex];
    final isLocked = provider.isQuestionLocked;
    final winnerId = provider.currentQuestionWinner;
    final myId = provider.myDeviceId;
    final iWon = winnerId == myId;
    final timerSec = provider.timerSeconds;

    String winnerName = '';
    if (winnerId != null) {
      try {
        winnerName =
            provider.players.firstWhere((p) => p.deviceId == winnerId).name;
      } catch (_) {
        winnerName = 'Ai đó';
      }
    }

    // Timer color
    Color timerColor = Colors.blue;
    if (timerSec <= 5) {
      timerColor = Colors.red;
    } else if (timerSec <= 10) {
      timerColor = Colors.orange;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxHeight < 600;
        final padding = isCompact ? 12.0 : 20.0;

        return SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - padding * 2,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top section: progress + timer
                Column(
                  children: [
                    // Timer + Progress row
                    Row(
                      children: [
                        // Timer circle
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: timerColor.withAlpha(30),
                            border: Border.all(color: timerColor, width: 3),
                          ),
                          child: Center(
                            child: Text(
                              '$timerSec',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: timerColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Câu ${currentIndex + 1} / ${_cards.length}',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: LinearProgressIndicator(
                                  value: (currentIndex + 1) / _cards.length,
                                  backgroundColor: Colors.grey[300],
                                  color: Colors.blue,
                                  minHeight: 8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Lock banner
                    if (isLocked)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: iWon
                              ? Colors.green.withAlpha(30)
                              : Colors.orange.withAlpha(30),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: iWon ? Colors.green : Colors.orange,
                              width: 1.5),
                        ),
                        child: Text(
                          iWon
                              ? 'Bạn trả lời đúng trước! +10 điểm'
                              : '$winnerName đã trả lời đúng! Chờ câu tiếp…',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: iWon
                                ? Colors.green[700]
                                : Colors.orange[800],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),

                SizedBox(height: isCompact ? 10 : 20),

                // Question Card
                AnimatedBuilder(
                  animation: _shakeAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(
                          _shakeAnimation.value *
                              (1 - _shakeController.value * 2),
                          0),
                      child: child,
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      minHeight: isCompact ? 80 : 100,
                      maxHeight: isCompact ? 160 : 220,
                    ),
                    padding: EdgeInsets.all(isCompact ? 16 : 24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: theme.colorScheme.primary, width: 2),
                    ),
                    child: Center(
                      child: AutoSizeText(
                        currentCard.term,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        minFontSize: 14,
                        maxLines: 6,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: isCompact ? 10 : 20),

                // Answer Options
                Column(
                  children: _currentOptions.map((option) {
                    final isCorrectOption = option == currentCard.definition;
                    final isThisSelected = _selectedOption == option;

                    Color? btnColor;
                    Color? borderColor;
                    Color? textColor;

                    if (isLocked || _hasAnsweredThisQuestion) {
                      if (isCorrectOption) {
                        btnColor = Colors.green.withAlpha(40);
                        borderColor = Colors.green;
                        textColor = Colors.green[800];
                      } else if (isThisSelected && _localAnswerResult == false) {
                        btnColor = Colors.red.withAlpha(40);
                        borderColor = Colors.red;
                        textColor = Colors.red[800];
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 52,
                          maxHeight: 120,
                          minWidth: double.infinity,
                        ),
                        child: ElevatedButton(
                          onPressed: (isLocked || _hasAnsweredThisQuestion)
                              ? null
                              : () => _handleAnswer(
                                  option, context.read<BattleProvider>()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: btnColor ?? theme.cardColor,
                            disabledBackgroundColor:
                                btnColor ?? theme.cardColor.withAlpha(180),
                            foregroundColor:
                                theme.textTheme.bodyLarge?.color,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                  color:
                                      borderColor ?? theme.dividerColor,
                                  width: borderColor != null ? 2 : 1),
                            ),
                          ),
                          child: AutoSizeText(
                            option,
                            style: TextStyle(
                              fontSize: 15,
                              color: textColor,
                              fontWeight: (isLocked && isCorrectOption) ||
                                      (isThisSelected &&
                                          _localAnswerResult == false)
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            textAlign: TextAlign.center,
                            minFontSize: 11,
                            maxLines: 4,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── GAME SUMMARY (shown when game is over) ─────────────────

  Widget _buildGameSummary(ThemeData theme, BattleProvider provider) {
    final sortedPlayers = List.from(provider.players)
      ..sort((a, b) => b.score.compareTo(a.score));
    final myId = provider.myDeviceId;
    final topPlayer = sortedPlayers.isNotEmpty ? sortedPlayers.first : null;
    final isIWinner = topPlayer?.deviceId == myId;

    // Find my rank
    int myRank = 0;
    for (int i = 0; i < sortedPlayers.length; i++) {
      if (sortedPlayers[i].deviceId == myId) {
        myRank = i + 1;
        break;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 10),

          // Trophy icon
          Icon(
            isIWinner ? Icons.emoji_events : Icons.flag,
            size: 80,
            color: isIWinner ? Colors.amber : Colors.blue,
          ),
          const SizedBox(height: 12),

          Text(
            isIWinner ? '🏆 Bạn là nhà vô địch!' : 'Trận đấu kết thúc!',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),

          if (myRank > 0)
            Text(
              'Bạn xếp hạng #$myRank${topPlayer != null ? " · Top 1: ${topPlayer.name} (${topPlayer.score} điểm)" : ""}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),

          const SizedBox(height: 24),

          // Podium cards
          ...List.generate(sortedPlayers.length, (index) {
            final p = sortedPlayers[index];
            final isMe = p.deviceId == myId;

            IconData? medalIcon;
            Color? medalColor;
            if (index == 0) {
              medalIcon = Icons.looks_one;
              medalColor = Colors.amber;
            } else if (index == 1) {
              medalIcon = Icons.looks_two;
              medalColor = Colors.grey[400];
            } else if (index == 2) {
              medalIcon = Icons.looks_3;
              medalColor = Colors.brown[300];
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe
                    ? theme.colorScheme.primary.withAlpha(20)
                    : theme.cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isMe
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                  width: isMe ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  if (medalIcon != null)
                    Icon(medalIcon, color: medalColor, size: 28)
                  else
                    SizedBox(
                      width: 28,
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMe ? '${p.name} (bạn)' : p.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isMe
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${p.score} điểm',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 24),

          // Exit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                provider.disconnect();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.exit_to_app, color: Colors.white),
              label: const Text('Thoát Phòng',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─── MOBILE LEADERBOARD OVERLAY ────────────────────────────

  Widget _buildMobileLeaderboardOverlay(
      ThemeData theme, BattleProvider provider) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width * 0.65,
      child: Material(
        elevation: 8,
        child: Container(
          color: theme.cardColor,
          child: Column(
            children: [
              // Header with close button
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: Colors.blue,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'BẢNG XẾP HẠNG',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _showLeaderboard = false),
                      child:
                          const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildLeaderboardContent(theme, provider)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── SIDEBAR LEADERBOARD (desktop) ─────────────────────────

  Widget _buildLeaderboard(ThemeData theme, BattleProvider provider) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          color: Colors.blue,
          width: double.infinity,
          child: const Text(
            'BẢNG XẾP HẠNG',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(child: _buildLeaderboardContent(theme, provider)),
      ],
    );
  }

  Widget _buildLeaderboardContent(ThemeData theme, BattleProvider provider) {
    final sortedPlayers = List.from(provider.players)
      ..sort((a, b) => b.score.compareTo(a.score));

    return Column(
      children: [
        // Timer indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.blue.withAlpha(20),
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer, size: 14, color: Colors.blue[700]),
              const SizedBox(width: 4),
              Text(
                'Câu ${provider.currentQuestionIndex + 1}/${provider.quizCards.length}  ·  ${provider.timerSeconds}s',
                style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold, color: Colors.blue[700]),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: sortedPlayers.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = sortedPlayers[index];
              final isMe = p.deviceId == provider.myDeviceId;
              final isWinner =
                  p.deviceId == provider.currentQuestionWinner;
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: index == 0
                      ? Colors.amber
                      : (index == 1
                          ? Colors.grey[400]
                          : (index == 2
                              ? Colors.brown[300]
                              : Colors.blueGrey)),
                  radius: 14,
                  child: Text('${index + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        isMe ? '${p.name} (bạn)' : p.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isMe
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isWinner)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child:
                            Icon(Icons.star, color: Colors.amber, size: 14),
                      ),
                  ],
                ),
                trailing: Text('${p.score}',
                    style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              );
            },
          ),
        ),
      ],
    );
  }
}

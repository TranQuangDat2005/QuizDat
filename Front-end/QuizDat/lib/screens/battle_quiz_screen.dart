import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/battle_provider.dart';
import '../models/card.dart';
import 'dart:math';

class BattleQuizScreen extends StatefulWidget {
  const BattleQuizScreen({super.key});

  @override
  State<BattleQuizScreen> createState() => _BattleQuizScreenState();
}

class _BattleQuizScreenState extends State<BattleQuizScreen> {
  int _currentIndex = 0;
  List<VocabCard> _cards = [];
  bool _isFinished = false;

  // Options for multiple choice
  List<String> _currentOptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initQuiz();
    });
  }

  void _initQuiz() {
    final provider = context.read<BattleProvider>();
    // Shuffle cards for a random experience, but wait, 
    // we want everyone to have the same order?
    // In a true multiplayer quiz, host could shuffle and broadcast order.
    // For now, we use the order from provider (which is deterministic).
    setState(() {
      _cards = List.from(provider.quizCards);
      _generateOptions();
    });
  }

  void _generateOptions() {
    if (_currentIndex >= _cards.length) return;
    
    final currentCard = _cards[_currentIndex];
    final correctAnswer = currentCard.definition;
    
    // Get 3 random wrong answers from other cards
    final otherCards = _cards.where((c) => c.cardId != currentCard.cardId).toList();
    otherCards.shuffle(Random());
    
    final wrongAnswers = otherCards.take(3).map((c) => c.definition).toList();
    
    _currentOptions = [correctAnswer, ...wrongAnswers];
    _currentOptions.shuffle(Random());
  }

  void _handleAnswer(String selectedAnswer) {
    if (_isFinished) return;

    final currentCard = _cards[_currentIndex];
    final isCorrect = selectedAnswer == currentCard.definition;

    if (isCorrect) {
      // Award 10 points
      context.read<BattleProvider>().updateMyScore(10);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chính xác! +10 điểm'), backgroundColor: Colors.green, duration: Duration(milliseconds: 500)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sai rồi!'), backgroundColor: Colors.red, duration: Duration(milliseconds: 500)),
      );
    }

    // Move to next question
    if (_currentIndex < _cards.length - 1) {
      setState(() {
        _currentIndex++;
        _generateOptions();
      });
    } else {
      setState(() {
        _isFinished = true;
      });
      _showGameOverDialog();
    }
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Hoàn Thành!'),
        content: const Text('Bạn đã hoàn thành bộ câu hỏi. Hãy chờ những người khác!'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text('Xem Bảng Xếp Hạng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<BattleProvider>();

    return WillPopScope(
      onWillPop: () async {
        bool? confirm = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Rời khỏi trận đấu?'),
            content: const Text('Nếu thoát, bạn sẽ mất kết nối với phòng.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              TextButton(
                onPressed: () {
                  provider.disconnect();
                  Navigator.pop(ctx, true);
                }, 
                child: const Text('Thoát', style: TextStyle(color: Colors.red))
              ),
            ],
          )
        );
        return confirm ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(provider.selectedSet?.name ?? 'Đấu Trường'),
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
        ),
        body: Row(
          children: [
            // Main Quiz Area
            Expanded(
              flex: 3,
              child: _isFinished 
                ? _buildFinishedState(theme)
                : _buildQuizArea(theme),
            ),
            
            // Sidebar Leaderboard
            Container(
              width: 250,
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border(left: BorderSide(color: theme.dividerColor)),
              ),
              child: _buildLeaderboard(theme, provider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizArea(ThemeData theme) {
    if (_cards.isEmpty || _currentOptions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentCard = _cards[_currentIndex];

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Progress
          LinearProgressIndicator(
            value: (_currentIndex + 1) / _cards.length,
            backgroundColor: Colors.grey[300],
            color: Colors.blue,
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
          const SizedBox(height: 20),
          Text(
            'Câu ${_currentIndex + 1} / ${_cards.length}',
            style: theme.textTheme.titleMedium,
          ),
          const Spacer(),
          
          // Question Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.primary, width: 2),
            ),
            child: Center(
              child: Text(
                currentCard.term,
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          
          const Spacer(),
          
          // Options
          ..._currentOptions.map((option) => Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: () => _handleAnswer(option),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.cardColor,
                  foregroundColor: theme.textTheme.bodyLarge?.color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: theme.dividerColor),
                  ),
                ),
                child: Text(option, style: const TextStyle(fontSize: 16)),
              ),
            ),
          )).toList(),
          
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildFinishedState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events, size: 100, color: Colors.amber),
          const SizedBox(height: 20),
          Text('Tuyệt vời!', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('Bạn đã hoàn thành bộ câu hỏi. Hãy theo dõi bảng xếp hạng!'),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () {
              context.read<BattleProvider>().disconnect();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Thoát Phòng', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildLeaderboard(ThemeData theme, BattleProvider provider) {
    // Sort players by score descending
    final sortedPlayers = List.from(provider.players);
    sortedPlayers.sort((a, b) => b.score.compareTo(a.score));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue,
          width: double.infinity,
          child: const Text(
            'BẢNG XẾP HẠNG',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: sortedPlayers.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = sortedPlayers[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: index == 0 ? Colors.amber : (index == 1 ? Colors.grey[400] : (index == 2 ? Colors.brown[300] : Colors.blueGrey)),
                  radius: 16,
                  child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text('${p.score} pts', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              );
            },
          ),
        ),
      ],
    );
  }
}

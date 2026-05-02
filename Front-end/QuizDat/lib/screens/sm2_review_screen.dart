import 'dart:math';
import 'package:flutter/material.dart';
import '../models/card.dart';
import '../services/sm2_service.dart';

// Luồng cho mỗi SM2Card:
// - FlipCard A:  hiện ngôn-ngữ-học → lật xem ngôn-ngữ-mẹ-đẻ → đánh giá 4 nút
// - FlipCard B:  hiện ngôn-ngữ-mẹ-đẻ → lật xem ngôn-ngữ-học → đánh giá 4 nút
// - TypingCard:  hiện ngôn-ngữ-mẹ-đẻ → gõ ngôn-ngữ-học → đánh giá 4 nút
enum _CardPhase { front, revealed }

/// Chiều flip: A = học→mẹ đẻ, B = mẹ đẻ→học
enum SM2FlipDir { aLearningFirst, bNativeFirst }

class Sm2ReviewScreen extends StatefulWidget {
  final List<VocabCard> allCards;
  final String setName;
  /// true  = cột "Thuật ngữ" là ngôn ngữ muốn học (mặc định)
  /// false = cột "Định nghĩa" là ngôn ngữ muốn học
  final bool termIsLearning;

  const Sm2ReviewScreen({
    super.key,
    required this.allCards,
    required this.setName,
    this.termIsLearning = true,
  });

  @override
  State<Sm2ReviewScreen> createState() => _Sm2ReviewScreenState();
}

class _Sm2ReviewScreenState extends State<Sm2ReviewScreen>
    with SingleTickerProviderStateMixin {
  final SM2Service _sm2 = SM2Service();

  List<SM2Card> _queue = [];
  // Chiều flip tương ứng với từng card trong queue
  List<SM2FlipDir?> _queueDirs = [];

  int _totalSession = 0;
  int _doneCount = 0;
  int _newCount = 0;
  int _dueCount = 0;
  int _againCount = 0;

  SM2Card? _current;
  SM2FlipDir? _currentDir; // chỉ có giá trị khi cardType == flip
  bool _isLoading = true;
  bool _sessionDone = false;
  _CardPhase _phase = _CardPhase.front;

  // Typing state
  final TextEditingController _answerCtrl = TextEditingController();
  String _userAnswer = '';

  // Flip animation
  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;

  Map<String, int> _intervals = {'again': 1, 'hard': 1, 'good': 1, 'easy': 1};

  // ── Helpers: tên hiển thị ngôn ngữ ──────────────────────────────────────

  /// Text hiển thị trên mặt trước (front) của thẻ hiện tại
  String get _frontText {
    if (_current == null) return '';
    final card = _current!.card;
    if (_current!.cardType == SM2CardType.typing) {
      // Typing: luôn hiện ngôn ngữ mẹ đẻ để hỏi
      return widget.termIsLearning ? card.definition : card.term;
    }
    // Flip: phụ thuộc vào chiều
    if (_currentDir == SM2FlipDir.aLearningFirst) {
      return widget.termIsLearning ? card.term : card.definition;
    } else {
      return widget.termIsLearning ? card.definition : card.term;
    }
  }

  /// Text hiển thị ở mặt sau (answer)
  String get _backText {
    if (_current == null) return '';
    final card = _current!.card;
    if (_current!.cardType == SM2CardType.typing) {
      // Typing: đáp án là ngôn ngữ muốn học
      return widget.termIsLearning ? card.term : card.definition;
    }
    if (_currentDir == SM2FlipDir.aLearningFirst) {
      return widget.termIsLearning ? card.definition : card.term;
    } else {
      return widget.termIsLearning ? card.term : card.definition;
    }
  }

  /// Nhãn mặt trước (loại ngôn ngữ)
  String get _frontLabel {
    if (_current == null) return '';
    if (_current!.cardType == SM2CardType.typing) {
      return widget.termIsLearning ? 'Định nghĩa' : 'Thuật ngữ';
    }
    if (_currentDir == SM2FlipDir.aLearningFirst) {
      return widget.termIsLearning ? 'Thuật ngữ' : 'Định nghĩa';
    } else {
      return widget.termIsLearning ? 'Định nghĩa' : 'Thuật ngữ';
    }
  }

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _flipAnim = Tween<double>(begin: 0, end: pi)
        .animate(CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut));
    _buildQueue();
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _buildQueue() async {
    final originalQueue = await _sm2.getReviewQueue(widget.allCards);
    if (!mounted) return;

    // Với mỗi FlipCard trong queue, tạo thêm một bản sao chiều B
    // Typing card giữ nguyên
    final expandedQueue = <SM2Card>[];
    final expandedDirs = <SM2FlipDir?>[];

    for (final card in originalQueue) {
      if (card.cardType == SM2CardType.flip) {
        expandedQueue.add(card);
        expandedDirs.add(SM2FlipDir.aLearningFirst);
        expandedQueue.add(card);
        expandedDirs.add(SM2FlipDir.bNativeFirst);
      } else {
        expandedQueue.add(card);
        expandedDirs.add(null);
      }
    }

    // Shuffle để 2 chiều flip không liên tiếp nhau
    final combined = List.generate(expandedQueue.length, (i) => MapEntry(expandedQueue[i], expandedDirs[i]));
    combined.shuffle();

    setState(() {
      _queue = combined.map((e) => e.key).toList();
      _queueDirs = combined.map((e) => e.value).toList();
      // Đếm theo card gốc (không nhân đôi)
      _newCount = originalQueue.where((c) => c.isNew).length;
      _dueCount = originalQueue.where((c) => !c.isNew).length;
      _totalSession = _queue.length;
      _isLoading = false;
      _sessionDone = _queue.isEmpty;
    });
    if (_queue.isNotEmpty) _loadNext();
  }

  void _loadNext() {
    if (_queue.isEmpty) {
      setState(() => _sessionDone = true);
      return;
    }
    final card = _queue.removeAt(0);
    final dir = _queueDirs.removeAt(0);
    _intervals = _sm2.previewIntervals(
      repetitions: card.repetitions,
      easeFactor: card.easeFactor,
      intervalDays: card.intervalDays,
    );
    _flipCtrl.reset();
    _answerCtrl.clear();
    setState(() {
      _current = card;
      _currentDir = dir;
      _phase = _CardPhase.front;
      _userAnswer = '';
    });
  }

  void _reveal() {
    if (_current!.cardType == SM2CardType.typing) {
      setState(() => _userAnswer = _answerCtrl.text.trim());
    }
    _flipCtrl.forward().then((_) {
      if (mounted) setState(() => _phase = _CardPhase.revealed);
    });
  }

  void _showHint() {
    final answer = _backText;
    final len = (answer.length * 0.35).ceil().clamp(1, answer.length);
    _answerCtrl.text = answer.substring(0, len);
    _answerCtrl.selection = TextSelection.fromPosition(TextPosition(offset: len));
  }

  Future<void> _rate(int quality) async {
    if (_current == null) return;
    await _sm2.recordAnswer(card: _current!, quality: quality);

    if (quality < 3) {
      _againCount++;
      _queue.add(SM2Card(
        card: _current!.card,
        cardType: _current!.cardType,
        repetitions: 0,
        easeFactor: _current!.easeFactor,
        intervalDays: 1,
        isNew: false,
      ));
      // Cho chiều bị sai vào cuối queue với cùng hướng
      _queueDirs.add(_currentDir);
    } else {
      _doneCount++;
    }
    _loadNext();
  }

  // ═══ BUILD ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)));
    }
    if (_sessionDone) return _buildDone();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(children: [
          _buildProgress(),
          _buildTypeBadge(),
          Expanded(
            child: AnimatedBuilder(
              animation: _flipAnim,
              builder: (ctx, _) {
                final angle = _flipAnim.value;
                final showFront = angle < pi / 2;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateX(angle),
                  child: showFront ? _buildFrontView() : _buildRevealedView(angle),
                );
              },
            ),
          ),
          _buildBottom(),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  // ─── APP BAR ──────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: theme.appBarTheme.backgroundColor,
      elevation: 0,
      leading: IconButton(icon: Icon(Icons.close, color: theme.iconTheme.color), onPressed: () => Navigator.pop(context)),
      title: Column(children: [
        Text(widget.setName,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _chip(_newCount, Colors.blue, 'Mới'),
          const SizedBox(width: 6),
          _chip(_dueCount, Colors.green, 'Ôn tập'),
          if (_againCount > 0) ...[const SizedBox(width: 6), _chip(_againCount, Colors.red, 'Lại')],
        ]),
      ]),
      centerTitle: true,
    );
  }

  Widget _chip(int n, Color c, String l) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: Text('$n $l', style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.bold)),
      );

  Widget _buildProgress() {
    final theme = Theme.of(context);
    final progress = _totalSession > 0 ? _doneCount / _totalSession : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress, minHeight: 6,
              backgroundColor: theme.dividerColor,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('${_queue.length} còn lại', style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildTypeBadge() {
    if (_current == null) return const SizedBox();
    final isFlip = _current!.cardType == SM2CardType.flip;
    final color = isFlip ? Colors.blue : Colors.purple;
    final icon = isFlip ? Icons.flip_rounded : Icons.edit_rounded;

    String label;
    if (isFlip) {
      label = _currentDir == SM2FlipDir.aLearningFirst
          ? 'Lật thẻ (Học → Mẹ đẻ)'
          : 'Lật thẻ (Mẹ đẻ → Học)';
    } else {
      label = 'Tự luận (viết ngôn ngữ học)';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            if (_current!.isNew) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text('MỚI', style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  // ─── FRONT VIEW ───────────────────────────────────────────────────────────

  Widget _buildFrontView() {
    if (_current == null) return const SizedBox();
    return _current!.cardType == SM2CardType.flip
        ? _buildFlipFront()
        : _buildTypingFront();
  }

  Widget _buildFlipFront() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: _reveal,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor, width: 2),
            boxShadow: [BoxShadow(color: isDark ? Colors.black45 : Colors.black12, blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Stack(children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _frontText,
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 32, height: 1.3),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Positioned(
              top: 12, left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_frontLabel,
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ),
            ),
            Positioned(
              bottom: 16, right: 16,
              child: Text('Chạm để lật', style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildTypingFront() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final learningLangLabel = widget.termIsLearning ? 'Thuật ngữ' : 'Định nghĩa';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Question card (hiện ngôn ngữ mẹ đẻ)
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor, width: 2),
            boxShadow: [BoxShadow(color: isDark ? Colors.black45 : Colors.black12, blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Column(children: [
            Text(
              _frontText,
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 28),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // Input box
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4), width: 1.5),
          ),
          child: TextField(
            controller: _answerCtrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _reveal(),
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Nhập $learningLangLabel...',
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ]),
    );
  }

  // ─── REVEALED VIEW (after flip animation) ────────────────────────────────

  Widget _buildRevealedView(double angle) {
    if (_current == null) return const SizedBox();
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateX(pi),
      child: _current!.cardType == SM2CardType.flip
          ? _buildFlipBack()
          : _buildTypingResult(),
    );
  }

  Widget _buildFlipBack() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Nhãn cho mặt trước và mặt sau
    final backLabel = _currentDir == SM2FlipDir.aLearningFirst
        ? (widget.termIsLearning ? 'Định nghĩa' : 'Thuật ngữ')
        : (widget.termIsLearning ? 'Thuật ngữ' : 'Định nghĩa');
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor, width: 2),
          boxShadow: [BoxShadow(color: isDark ? Colors.black45 : Colors.black12, blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1.5))),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(_frontLabel,
                    style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_frontText,
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 16),
                    textAlign: TextAlign.center),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(backLabel,
                    style: const TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _backText,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 26, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// Chuẩn hóa chuỗi: trim + lowercase + NFC (để so sánh tiếng Hàn đúng)
  String _normalize(String s) => s.trim().toLowerCase();

  Widget _buildTypingResult() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final correct = _backText; // ngôn ngữ muốn học
    final isCorrect = _normalize(_userAnswer) == _normalize(correct);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Term header (ngôn ngữ mẹ đẻ đã hỏi)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Text(_frontText,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
        ),
        const SizedBox(height: 10),

        // Correct answer (ngôn ngữ muốn học)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerColor, width: 2),
            boxShadow: [BoxShadow(color: isDark ? Colors.black45 : Colors.black12, blurRadius: 6, offset: const Offset(0, 3))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Đáp án đúng', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(correct, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 22)),
          ]),
        ),
        const SizedBox(height: 10),

        // User answer comparison
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isCorrect
                ? Colors.green.withValues(alpha: isDark ? 0.15 : 0.07)
                : Colors.red.withValues(alpha: isDark ? 0.15 : 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isCorrect ? Colors.green.withValues(alpha: 0.5) : Colors.red.withValues(alpha: 0.5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: isCorrect ? Colors.green : Colors.red, size: 18),
              const SizedBox(width: 8),
              Text(isCorrect ? 'Chính xác!' : 'Chưa đúng',
                  style: TextStyle(fontWeight: FontWeight.bold, color: isCorrect ? Colors.green[600] : Colors.red[600], fontSize: 13)),
            ]),
            const SizedBox(height: 6),
            if (_userAnswer.isEmpty)
              Text('(Không nhập gì)', style: TextStyle(color: Colors.red[400], fontStyle: FontStyle.italic))
            else if (isCorrect)
              Text(_userAnswer, style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600, fontSize: 15))
            else
              _buildDiff(_userAnswer, correct),
          ]),
        ),
      ]),
    );
  }

  Widget _buildDiff(String user, String correct) {
    final theme = Theme.of(context);
    final u = user.toLowerCase();
    final c = correct.toLowerCase();
    final spans = <TextSpan>[];
    final minLen = u.length < c.length ? u.length : c.length;

    for (int i = 0; i < minLen; i++) {
      final ok = u[i] == c[i];
      spans.add(TextSpan(
        text: correct[i],
        style: TextStyle(
          color: ok ? Colors.green[700] : Colors.red[700],
          fontWeight: FontWeight.bold,
          backgroundColor: ok ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12),
        ),
      ));
    }
    if (correct.length > user.length) {
      spans.add(TextSpan(
        text: correct.substring(minLen),
        style: TextStyle(color: Colors.red[300], fontWeight: FontWeight.bold),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Bạn đã gõ:', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 4),
      RichText(text: TextSpan(children: spans, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15))),
    ]);
  }

  // ─── BOTTOM BUTTONS ───────────────────────────────────────────────────────

  Widget _buildBottom() {
    if (_phase == _CardPhase.front) {
      return _current!.cardType == SM2CardType.typing
          ? _buildTypingActions()
          : _buildFlipShowBtn();
    }
    return _buildRatingButtons();
  }

  Widget _buildFlipShowBtn() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity, height: 56,
        child: ElevatedButton(
          onPressed: _reveal,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary, foregroundColor: theme.colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Hiện đáp án', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildTypingActions() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        OutlinedButton.icon(
          onPressed: _showHint,
          icon: const Icon(Icons.lightbulb_outline, size: 18),
          label: const Text('Gợi ý'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.amber[700],
            side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _reveal,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary, foregroundColor: theme.colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Hiện đáp án', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }

  Widget _buildRatingButtons() {
    int? suggested;
    if (_current!.cardType == SM2CardType.typing) {
      final correct = _backText;
      suggested = _normalize(_userAnswer) == _normalize(correct) ? 4 : 1;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        _rBtn('Lại', SM2Service.formatInterval(_intervals['again']!), const Color(0xFFEF5350), 1, suggested == 1),
        const SizedBox(width: 8),
        _rBtn('Khó', SM2Service.formatInterval(_intervals['hard']!), const Color(0xFFFF9800), 3, suggested == 3),
        const SizedBox(width: 8),
        _rBtn('Tốt', SM2Service.formatInterval(_intervals['good']!), const Color(0xFF4CAF50), 4, suggested == 4),
        const SizedBox(width: 8),
        _rBtn('Dễ', SM2Service.formatInterval(_intervals['easy']!), const Color(0xFF2196F3), 5, suggested == 5),
      ]),
    );
  }

  Widget _rBtn(String label, String sub, Color color, int quality, bool suggested) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _rate(quality),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: suggested ? color.withValues(alpha: 0.25) : color.withValues(alpha: 0.12),
            border: Border.all(color: suggested ? color : color.withValues(alpha: 0.5), width: suggested ? 2.5 : 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(sub, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 15, color: color, fontWeight: FontWeight.w900)),
            if (suggested) Icon(Icons.arrow_upward_rounded, size: 12, color: color),
          ]),
        ),
      ),
    );
  }

  // ─── DONE SCREEN ──────────────────────────────────────────────────────────

  Widget _buildDone() {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_circle_rounded, size: 80, color: Color(0xFF4CAF50)),
              const SizedBox(height: 24),
              Text('Hoàn thành!', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Bạn đã làm $_doneCount thẻ hôm nay',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 32),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _stat('Mới', '$_newCount', Colors.blue),
                _stat('Ôn', '$_dueCount', Colors.green),
                _stat('Lại', '$_againCount', Colors.red),
              ]),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary, foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Quay về', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    final theme = Theme.of(context);
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
      const SizedBox(height: 4),
      Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}

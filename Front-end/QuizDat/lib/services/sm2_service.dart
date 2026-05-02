import '../models/card.dart';
import 'database_helper.dart';

/// Card type enum for the 2-card system (like Anki Note -> 2 Cards)
enum SM2CardType { flip, typing }

extension SM2CardTypeExt on SM2CardType {
  String get value => this == SM2CardType.flip ? 'flip' : 'typing';
  SM2CardType get sibling => this == SM2CardType.flip ? SM2CardType.typing : SM2CardType.flip;
}

/// Result from SM-2 algorithm computation
class SM2Result {
  final int repetitions;
  final double easeFactor;
  final int intervalDays;
  final String nextReview; // ISO date string YYYY-MM-DD

  const SM2Result({
    required this.repetitions,
    required this.easeFactor,
    required this.intervalDays,
    required this.nextReview,
  });
}

/// A single review card (one of the 2 cards per vocabulary item)
class SM2Card {
  final VocabCard card;
  final SM2CardType cardType; // flip or typing
  int repetitions;
  double easeFactor;
  int intervalDays;
  String? nextReview;
  bool isNew; // no SM2Progress record yet for this card type

  SM2Card({
    required this.card,
    required this.cardType,
    required this.repetitions,
    required this.easeFactor,
    required this.intervalDays,
    this.nextReview,
    this.isNew = false,
  });
}

class SM2Service {
  static final SM2Service _instance = SM2Service._internal();
  factory SM2Service() => _instance;
  SM2Service._internal();

  final DatabaseHelper _db = DatabaseHelper();

  // ─── SM-2 ALGORITHM ────────────────────────────────────────────────────────

  /// Compute next SM-2 values. quality: 1=Again, 3=Hard, 4=Good, 5=Easy
  SM2Result computeNext({
    required int quality,
    required int repetitions,
    required double easeFactor,
    required int intervalDays,
  }) {
    int newRep;
    double newEF;
    int newInterval;

    if (quality < 3) {
      newRep = 0;
      newInterval = 1;
      newEF = easeFactor;
    } else {
      newRep = repetitions + 1;
      if (newRep == 1) {
        newInterval = 1;
      } else if (newRep == 2) {
        newInterval = 6;
      } else {
        newInterval = (intervalDays * easeFactor).round();
        if (newInterval < intervalDays + 1) newInterval = intervalDays + 1;
      }
      newEF = easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
      if (newEF < 1.3) newEF = 1.3;
    }

    final nextDate = DateTime.now().add(Duration(days: newInterval));
    final nextReview = nextDate.toIso8601String().substring(0, 10);

    return SM2Result(
      repetitions: newRep,
      easeFactor: newEF,
      intervalDays: newInterval,
      nextReview: nextReview,
    );
  }

  /// Preview interval for 4 rating buttons
  Map<String, int> previewIntervals({
    required int repetitions,
    required double easeFactor,
    required int intervalDays,
  }) {
    return {
      'again': computeNext(quality: 1, repetitions: repetitions, easeFactor: easeFactor, intervalDays: intervalDays).intervalDays,
      'hard':  computeNext(quality: 3, repetitions: repetitions, easeFactor: easeFactor, intervalDays: intervalDays).intervalDays,
      'good':  computeNext(quality: 4, repetitions: repetitions, easeFactor: easeFactor, intervalDays: intervalDays).intervalDays,
      'easy':  computeNext(quality: 5, repetitions: repetitions, easeFactor: easeFactor, intervalDays: intervalDays).intervalDays,
    };
  }

  // ─── QUEUE BUILDING ────────────────────────────────────────────────────────

  /// Load the review queue applying daily limits + bury logic.
  /// Each VocabCard can contribute up to 2 SM2Cards (flip + typing).
  Future<List<SM2Card>> getReviewQueue(List<VocabCard> allCards) async {
    final today = _today();
    final newLimit = await _db.getSm2NewLimit();
    final reviewLimit = await _db.getSm2ReviewLimit();

    final log = await _db.getSm2DailyLog(today);

    int newStudied = log['new_studied'] ?? 0;
    int reviewStudied = log['review_studied'] ?? 0;
    int newRemaining = (newLimit - newStudied).clamp(0, newLimit);
    int reviewRemaining = (reviewLimit - reviewStudied).clamp(0, reviewLimit);

    final queue = <SM2Card>[];

    for (final vocabCard in allCards) {
      if (newRemaining <= 0 && reviewRemaining <= 0) break;

      for (final type in SM2CardType.values) {
        final progress = await _db.getSm2ProgressTyped(vocabCard.cardId, type.value);

        // Check if buried
        if (progress != null) {
          final buriedUntil = progress['buried_until'] as String?;
          if (buriedUntil != null && buriedUntil.compareTo(today) >= 0) continue;
        }

        if (progress == null) {
          // Brand new card (no progress at all for this type)
          if (newRemaining > 0) {
            queue.add(SM2Card(
              card: vocabCard,
              cardType: type,
              repetitions: 0,
              easeFactor: 2.5,
              intervalDays: 1,
              nextReview: null,
              isNew: true,
            ));
            newRemaining--;
          }
        } else {
          final nextReview = progress['next_review'] as String?;
          if (nextReview == null || nextReview.compareTo(today) <= 0) {
            // Due for review
            if (reviewRemaining > 0) {
              queue.add(SM2Card(
                card: vocabCard,
                cardType: type,
                repetitions: progress['repetitions'] as int? ?? 0,
                easeFactor: (progress['ease_factor'] as num?)?.toDouble() ?? 2.5,
                intervalDays: progress['interval_days'] as int? ?? 1,
                nextReview: nextReview,
                isNew: false,
              ));
              reviewRemaining--;
            }
          }
        }
      }
    }

    // Shuffle so flip and typing cards from different notes are interleaved
    queue.shuffle();
    return queue;
  }

  // Count total due cards for display (uses limits)
  Future<int> countDueTodayWithLimits(List<VocabCard> allCards) async {
    final queue = await getReviewQueue(allCards);
    return queue.length;
  }

  // ─── RECORDING ANSWERS ─────────────────────────────────────────────────────

  /// Record answer and optionally bury the sibling card.
  Future<SM2Result> recordAnswer({
    required SM2Card card,
    required int quality,
  }) async {
    final result = computeNext(
      quality: quality,
      repetitions: card.repetitions,
      easeFactor: card.easeFactor,
      intervalDays: card.intervalDays,
    );

    await _db.upsertSm2Progress({
      'card_id': card.card.cardId,
      'card_type': card.cardType.value,
      'repetitions': result.repetitions,
      'ease_factor': result.easeFactor,
      'interval_days': result.intervalDays,
      'next_review': result.nextReview,
      'buried_until': null, // unbury this card itself
    });

    // Increment daily log
    final today = _today();
    if (card.isNew) {
      await _db.incrementSm2DailyNew(today);
    } else {
      await _db.incrementSm2DailyReview(today);
    }

    // Bury sibling card if setting is on
    final buryRelated = await _db.getSm2BuryRelated();
    if (buryRelated) {
      await _db.buryRelatedCard(card.card.cardId, card.cardType.value);
    }

    return result;
  }

  // ─── SETTINGS ──────────────────────────────────────────────────────────────

  Future<({int newLimit, int reviewLimit, bool buryRelated})> getSettings() async {
    final n = await _db.getSm2NewLimit();
    final r = await _db.getSm2ReviewLimit();
    final b = await _db.getSm2BuryRelated();
    return (newLimit: n, reviewLimit: r, buryRelated: b);
  }

  Future<void> saveSettings({
    required int newLimit,
    required int reviewLimit,
    required bool buryRelated,
  }) async {
    await _db.setSm2NewLimit(newLimit);
    await _db.setSm2ReviewLimit(reviewLimit);
    await _db.setSm2BuryRelated(buryRelated);
  }

  // Keep old getLimits/saveLimits for backwards compat with settings_screen
  Future<({int newLimit, int reviewLimit})> getLimits() async {
    final n = await _db.getSm2NewLimit();
    final r = await _db.getSm2ReviewLimit();
    return (newLimit: n, reviewLimit: r);
  }

  Future<void> saveLimits({required int newLimit, required int reviewLimit}) async {
    await _db.setSm2NewLimit(newLimit);
    await _db.setSm2ReviewLimit(reviewLimit);
  }

  Future<bool> getBuryRelated() => _db.getSm2BuryRelated();
  Future<void> setBuryRelated(bool value) => _db.setSm2BuryRelated(value);

  // ─── STATS ─────────────────────────────────────────────────────────────────

  Future<Map<String, int>> getDailyStats() async {
    final today = _today();
    final log = await _db.getSm2DailyLog(today);
    final newLimit = await _db.getSm2NewLimit();
    final reviewLimit = await _db.getSm2ReviewLimit();
    return {
      'new_studied': log['new_studied'] ?? 0,
      'review_studied': log['review_studied'] ?? 0,
      'new_limit': newLimit,
      'review_limit': reviewLimit,
    };
  }

  // ─── RESET ─────────────────────────────────────────────────────────────────

  Future<void> resetProgressForSet(String setId) async {
    await _db.clearSm2ProgressForSet(setId);
  }

  // ─── HELPERS ───────────────────────────────────────────────────────────────

  String _today() => DateTime.now().toIso8601String().substring(0, 10);

  static String formatInterval(int days) {
    if (days < 1) return '<1d';
    if (days == 1) return '1d';
    if (days < 31) return '${days}d';
    if (days < 365) return '${(days / 30).round()}mo';
    return '${(days / 365).round()}y';
  }

  // Keep old methods for backwards compat with vocab_set_library
  Future<({List<SM2Card> newCards, List<SM2Card> dueCards})> getCardsForReviewWithLimits(
      List<VocabCard> allCards) async {
    final queue = await getReviewQueue(allCards);
    final newCards = queue.where((c) => c.isNew).toList();
    final dueCards = queue.where((c) => !c.isNew).toList();
    return (newCards: newCards, dueCards: dueCards);
  }

  // Old recordAnswerWithLog kept for compat (now delegates to recordAnswer)
  Future<SM2Result> recordAnswerWithLog({
    required String cardId,
    required int quality,
    required int repetitions,
    required double easeFactor,
    required int intervalDays,
    required bool isNew,
    String cardType = 'flip',
  }) async {
    final dummyVocabCard = VocabCard(
      cardId: cardId,
      term: '',
      definition: '',
      state: 'new',
      setId: '',
    );
    final sm2Card = SM2Card(
      card: dummyVocabCard,
      cardType: cardType == 'typing' ? SM2CardType.typing : SM2CardType.flip,
      repetitions: repetitions,
      easeFactor: easeFactor,
      intervalDays: intervalDays,
      isNew: isNew,
    );
    return recordAnswer(card: sm2Card, quality: quality);
  }
}

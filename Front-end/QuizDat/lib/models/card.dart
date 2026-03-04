class VocabCard {
  final String cardId;
  final String term;
  final String definition;
  final String state;
  final String setId;

  // Constructor
  VocabCard({
    required this.cardId,
    required this.term,
    required this.definition,
    required this.state,
    required this.setId,
  });

  factory VocabCard.fromJson(Map<String, dynamic> json) {
    return VocabCard(
      cardId: json['card_id']?.toString() ?? '',
      term: json['term'] ?? '',
      definition: json['definition'] ?? '',
      state: json['state'] ?? '',
      setId: json['set_id']?.toString() ?? '',
    );
  }
}

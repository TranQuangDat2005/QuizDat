class SetCard {
  final String setId;
  final String name;
  final String repositoryId;
  final DateTime? lastLearnedTime;
  final String? status;

  // Constructor
  SetCard({
    required this.setId,
    required this.name,
    required this.repositoryId,
    this.lastLearnedTime,
    this.status,
  });

  factory SetCard.fromJson(Map<String, dynamic> json) {
    return SetCard(
      setId: json['set_id']?.toString() ?? '',
      name: json['name'] ?? '',
      repositoryId: json['repository_id']?.toString() ?? '',
      lastLearnedTime:
          json['last_learned_time'] != null &&
              json['last_learned_time'].toString().isNotEmpty
          ? DateTime.tryParse(json['last_learned_time'].toString())
          : null,
      status: json['status'],
    );
  }

  SetCard copyWith({
    String? setId,
    String? name,
    String? repositoryId,
    DateTime? lastLearnedTime,
    String? status,
  }) {
    return SetCard(
      setId: setId ?? this.setId,
      name: name ?? this.name,
      repositoryId: repositoryId ?? this.repositoryId,
      lastLearnedTime: lastLearnedTime ?? this.lastLearnedTime,
      status: status ?? this.status,
    );
  }

  String get formattedDate {
    if (lastLearnedTime == null) {
      return "";
    }
    String day = lastLearnedTime!.day.toString().padLeft(2, '0');
    String month = lastLearnedTime!.month.toString().padLeft(2, '0');
    String year = lastLearnedTime!.year.toString();

    return "$day/$month/$year";
  }

  Map<String, dynamic> toJson() {
    return {
      'set_id': setId,
      'name': name,
      'repository_id': repositoryId,
      'last_learned_time': lastLearnedTime?.toIso8601String(),
      'status': status,
    };
  }
}

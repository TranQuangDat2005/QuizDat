enum CalendarType { exam, study, deadline, meeting, other }

class CalendarEvent {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final CalendarType type;
  bool isDone;

  CalendarEvent({
    required this.id,
    required this.title,
    this.description = '',
    required this.date,
    this.type = CalendarType.study,
    this.isDone = false,
  });

  String get typeName {
    switch (type) {
      case CalendarType.exam:
        return "Thi cử";
      case CalendarType.deadline:
        return "Hạn chót";
      case CalendarType.study:
        return "Học tập";
      case CalendarType.meeting:
        return "Họp";
      default:
        return "Khác";
    }
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['calendar_id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      date: DateTime.parse(json['date']),
      type: CalendarType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => CalendarType.study,
      ),
      isDone: json['is_done'] == true,
    );
  }
}

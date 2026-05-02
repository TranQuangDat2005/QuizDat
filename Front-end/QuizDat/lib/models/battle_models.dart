import 'dart:convert';

/// Represents a player in the battle lobby
class BattlePlayer {
  final String deviceId;
  final String name;
  int score;
  bool isReady;

  BattlePlayer({
    required this.deviceId,
    required this.name,
    this.score = 0,
    this.isReady = false,
  });

  factory BattlePlayer.fromJson(Map<String, dynamic> json) {
    return BattlePlayer(
      deviceId: json['deviceId'] ?? '',
      name: json['name'] ?? '',
      score: json['score'] ?? 0,
      isReady: json['isReady'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'name': name,
      'score': score,
      'isReady': isReady,
    };
  }

  BattlePlayer copyWith({
    String? deviceId,
    String? name,
    int? score,
    bool? isReady,
  }) {
    return BattlePlayer(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      score: score ?? this.score,
      isReady: isReady ?? this.isReady,
    );
  }
}

/// Standardized message format for P2P Socket communication
class BattleMessage {
  final String type;
  final Map<String, dynamic>? payload;

  BattleMessage({
    required this.type,
    this.payload,
  });

  factory BattleMessage.fromJson(Map<String, dynamic> json) {
    return BattleMessage(
      type: json['type'] ?? '',
      payload: json['payload'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'payload': payload,
    };
  }

  String encode() {
    return jsonEncode(toJson());
  }

  static BattleMessage decode(String data) {
    return BattleMessage.fromJson(jsonDecode(data));
  }
}

// Message Types
class BattleMessageTypes {
  static const join = 'JOIN';
  static const lobbyUpdate = 'LOBBY_UPDATE';
  static const quizSelected = 'QUIZ_SELECTED';
  static const ready = 'READY';
  static const start = 'START';
  static const scoreUpdate = 'SCORE_UPDATE';
  static const gameOver = 'GAME_OVER';
  static const kick = 'KICK';
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/battle_models.dart';
import '../models/card.dart';
import '../models/set_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BattleProvider with ChangeNotifier {
  // Network
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  final List<Socket> _clientConnections = [];
  
  String _localIp = '';
  String get localIp => _localIp;

  bool _isHost = false;
  bool get isHost => _isHost;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // Game State
  final List<BattlePlayer> _players = [];
  List<BattlePlayer> get players => _players;

  SetCard? _selectedSet;
  SetCard? get selectedSet => _selectedSet;

  List<VocabCard> _quizCards = [];
  List<VocabCard> get quizCards => _quizCards;

  bool _isStarted = false;
  bool get isStarted => _isStarted;

  // Synchronized question index (driven by host)
  int _currentQuestionIndex = 0;
  int get currentQuestionIndex => _currentQuestionIndex;

  // Whether the current question has been locked (someone answered correctly)
  bool _isQuestionLocked = false;
  bool get isQuestionLocked => _isQuestionLocked;

  // deviceId of the player who answered the current question correctly (null = nobody yet)
  String? _currentQuestionWinner;
  String? get currentQuestionWinner => _currentQuestionWinner;

  // Whether the whole quiz is finished
  bool _isGameOver = false;
  bool get isGameOver => _isGameOver;

  // Timer (seconds remaining for the current question)
  static const int questionTimeLimit = 15; // seconds per question
  int _timerSeconds = questionTimeLimit;
  int get timerSeconds => _timerSeconds;
  Timer? _questionTimer;

  String _myDeviceId = '';
  String _myName = 'Player';
  String get myName => _myName;
  
  BattleProvider() {
    _initDevice();
  }

  Future<void> _initDevice() async {
    final prefs = await SharedPreferences.getInstance();
    _myName = prefs.getString('user_name') ?? 'Player_${Random().nextInt(1000)}';
    _myDeviceId = prefs.getString('device_id') ?? '';
    if (_myDeviceId.isEmpty) {
      _myDeviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
      await prefs.setString('device_id', _myDeviceId);
    }
  }

  /// ALL: Set a custom display name
  Future<void> setPlayerName(String name) async {
    if (name.trim().isEmpty) return;
    _myName = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _myName);

    // Update in players list
    final idx = _players.indexWhere((p) => p.deviceId == _myDeviceId);
    if (idx != -1) {
      _players[idx] = _players[idx].copyWith(name: _myName);
    }

    if (_isHost) {
      _broadcastLobbyUpdate();
    } else if (_clientSocket != null) {
      _sendMessageAsGuest(BattleMessage(
        type: BattleMessageTypes.nameChange,
        payload: {'deviceId': _myDeviceId, 'name': _myName},
      ));
    }
    notifyListeners();
  }

  /// HOST: Start the server
  Future<bool> startHosting() async {
    try {
      try {
        final info = NetworkInfo();
        _localIp = await info.getWifiIP() ?? '127.0.0.1';
      } catch (e) {
        _localIp = '127.0.0.1'; // Fallback for tests
      }
      
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 4040);
      _isHost = true;
      _isConnected = true;
      _players.clear();
      
      // Add self
      _players.add(BattlePlayer(deviceId: _myDeviceId, name: _myName, isReady: true)); // Host is always ready
      
      _serverSocket!.listen(_handleIncomingConnection);
      notifyListeners();
      print('Host started on $_localIp:4040');
      return true;
    } catch (e) {
      print('Error starting host: $e');
      return false;
    }
  }

  void _handleIncomingConnection(Socket socket) {
    if (_players.length >= 8) {
      socket.write(BattleMessage(type: BattleMessageTypes.kick, payload: {'reason': 'Lobby is full'}).encode() + '\n');
      socket.close();
      return;
    }

    _clientConnections.add(socket);
    
    socket.listen(
      (List<int> data) {
        final messages = utf8.decode(data).split('\n');
        for (var msg in messages) {
          if (msg.trim().isNotEmpty) {
            _handleMessageAsHost(msg, socket);
          }
        }
      },
      onDone: () {
        _clientConnections.remove(socket);
        // We don't know exactly which player disconnected here without tracking socket -> deviceId map,
        // but for simplicity, we can just ping or wait for reconnect.
        // A robust implementation would map sockets to players.
      },
      onError: (e) {
        print('Client error: $e');
        _clientConnections.remove(socket);
      },
    );
  }

  void _handleMessageAsHost(String messageStr, Socket socket) {
    try {
      final msg = BattleMessage.decode(messageStr);
      
      if (msg.type == BattleMessageTypes.join) {
        final newPlayer = BattlePlayer.fromJson(msg.payload!);
        // Avoid duplicates
        _players.removeWhere((p) => p.deviceId == newPlayer.deviceId);
        _players.add(newPlayer);
        _broadcastLobbyUpdate();
        
        // If quiz is already selected, send it to the new player
        if (_selectedSet != null) {
          socket.write(BattleMessage(
            type: BattleMessageTypes.quizSelected,
            payload: {
              'set': _selectedSet!.toJson(),
              'cards': _quizCards.map((c) => c.toJson()).toList()
            }
          ).encode() + '\n');
        }
      } else if (msg.type == BattleMessageTypes.ready) {
        final deviceId = msg.payload!['deviceId'];
        final playerIndex = _players.indexWhere((p) => p.deviceId == deviceId);
        if (playerIndex != -1) {
          _players[playerIndex].isReady = true;
          _broadcastLobbyUpdate();
        }
      } else if (msg.type == BattleMessageTypes.nameChange) {
        final deviceId = msg.payload!['deviceId'] as String;
        final newName = msg.payload!['name'] as String;
        final playerIndex = _players.indexWhere((p) => p.deviceId == deviceId);
        if (playerIndex != -1) {
          _players[playerIndex] = _players[playerIndex].copyWith(name: newName);
          _broadcastLobbyUpdate();
        }
      } else if (msg.type == BattleMessageTypes.questionAnswered) {
        // A guest answered the current question
        final deviceId = msg.payload!['deviceId'] as String;
        final isCorrect = msg.payload!['isCorrect'] as bool;
        final questionIndex = msg.payload!['questionIndex'] as int;

        // Ignore if this is for an old question or already locked
        if (questionIndex != _currentQuestionIndex) return;
        if (_isQuestionLocked && isCorrect) return;

        if (isCorrect) {
          // Award points and lock the question
          final playerIndex = _players.indexWhere((p) => p.deviceId == deviceId);
          if (playerIndex != -1) {
            _players[playerIndex].score += 10;
            _broadcastScoreUpdate(deviceId, _players[playerIndex].score);
          }
          _isQuestionLocked = true;
          _currentQuestionWinner = deviceId;
          _questionTimer?.cancel();
          _broadcast(BattleMessage(
            type: BattleMessageTypes.questionLocked,
            payload: {'winnerDeviceId': deviceId, 'questionIndex': questionIndex},
          ));
          notifyListeners();

          // Auto-advance to next question after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            _advanceQuestion();
          });
        }
      }
    } catch (e) {
      print('Error parsing message as host: $e');
    }
  }

  /// HOST: Start the per-question countdown timer
  void _startQuestionTimer() {
    _questionTimer?.cancel();
    _timerSeconds = questionTimeLimit;
    notifyListeners();

    _questionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _timerSeconds--;
      // Broadcast tick to guests
      _broadcast(BattleMessage(
        type: BattleMessageTypes.timerTick,
        payload: {'seconds': _timerSeconds},
      ));
      notifyListeners();

      if (_timerSeconds <= 0) {
        timer.cancel();
        // Time's up — no one got it right, advance
        if (!_isQuestionLocked) {
          _advanceQuestion();
        }
      }
    });
  }

  /// HOST: Move to next question (or end game)
  void _advanceQuestion() {
    if (!_isHost) return;
    _questionTimer?.cancel();
    final nextIndex = _currentQuestionIndex + 1;
    if (nextIndex >= _quizCards.length) {
      // Game over
      _isGameOver = true;
      _broadcast(BattleMessage(
        type: BattleMessageTypes.gameOver,
        payload: {'players': _players.map((p) => p.toJson()).toList()},
      ));
      notifyListeners();
    } else {
      _currentQuestionIndex = nextIndex;
      _isQuestionLocked = false;
      _currentQuestionWinner = null;
      _timerSeconds = questionTimeLimit;
      _broadcast(BattleMessage(
        type: BattleMessageTypes.nextQuestion,
        payload: {'questionIndex': nextIndex},
      ));
      notifyListeners();
      _startQuestionTimer();
    }
  }

  void _broadcastLobbyUpdate() {
    final payload = {'players': _players.map((p) => p.toJson()).toList()};
    _broadcast(BattleMessage(type: BattleMessageTypes.lobbyUpdate, payload: payload));
    notifyListeners();
  }

  void _broadcastScoreUpdate(String deviceId, int score) {
    final payload = {'deviceId': deviceId, 'score': score};
    _broadcast(BattleMessage(type: BattleMessageTypes.scoreUpdate, payload: payload));
    notifyListeners();
  }

  void _broadcast(BattleMessage msg) {
    final data = msg.encode() + '\n';
    for (var socket in _clientConnections) {
      try {
        socket.write(data);
      } catch (e) {
        print('Error broadcasting to a socket: $e');
      }
    }
  }

  /// HOST: Select quiz
  void selectQuiz(SetCard setCard, List<VocabCard> cards) {
    if (!_isHost) return;
    _selectedSet = setCard;
    _quizCards = cards;
    
    // Un-ready everyone except host
    for (var p in _players) {
      if (p.deviceId != _myDeviceId) p.isReady = false;
    }
    
    _broadcast(BattleMessage(
      type: BattleMessageTypes.quizSelected,
      payload: {
        'set': setCard.toJson(),
        'cards': cards.map((c) => c.toJson()).toList()
      }
    ));
    _broadcastLobbyUpdate();
  }

  /// HOST: Start battle
  void startBattle() {
    if (!_isHost) return;
    // Check if everyone is ready
    if (!_players.every((p) => p.isReady)) return;

    _isStarted = true;
    _currentQuestionIndex = 0;
    _isQuestionLocked = false;
    _currentQuestionWinner = null;
    _isGameOver = false;
    _timerSeconds = questionTimeLimit;

    // Reset scores
    for (var p in _players) {
      p.score = 0;
    }

    // Broadcast start with the first question index
    _broadcast(BattleMessage(
      type: BattleMessageTypes.start,
      payload: {'questionIndex': 0},
    ));
    notifyListeners();
    _startQuestionTimer();
  }

  /// GUEST: Join a host
  Future<bool> joinLobby(String ipAddress) async {
    try {
      _clientSocket = await Socket.connect(ipAddress, 4040, timeout: const Duration(seconds: 5));
      _isHost = false;
      _isConnected = true;
      _localIp = ipAddress; // Store host IP here
      
      _clientSocket!.listen(
        (List<int> data) {
          final messages = utf8.decode(data).split('\n');
          for (var msg in messages) {
            if (msg.trim().isNotEmpty) {
              _handleMessageAsGuest(msg);
            }
          }
        },
        onDone: () {
          disconnect();
        },
        onError: (e) {
          print('Client socket error: $e');
          disconnect();
        },
      );

      // Send JOIN message
      _sendMessageAsGuest(BattleMessage(
        type: BattleMessageTypes.join,
        payload: BattlePlayer(deviceId: _myDeviceId, name: _myName).toJson()
      ));

      return true;
    } catch (e) {
      print('Error joining lobby: $e');
      return false;
    }
  }

  void _handleMessageAsGuest(String messageStr) {
    try {
      final msg = BattleMessage.decode(messageStr);
      
      if (msg.type == BattleMessageTypes.lobbyUpdate) {
        _players.clear();
        final list = msg.payload!['players'] as List;
        for (var p in list) {
          _players.add(BattlePlayer.fromJson(p));
        }
        notifyListeners();
      } else if (msg.type == BattleMessageTypes.quizSelected) {
        _selectedSet = SetCard.fromJson(msg.payload!['set']);
        final cardsList = msg.payload!['cards'] as List;
        _quizCards = cardsList.map((c) => VocabCard.fromJson(c)).toList();
        notifyListeners();
      } else if (msg.type == BattleMessageTypes.start) {
        _isStarted = true;
        _currentQuestionIndex = msg.payload?['questionIndex'] ?? 0;
        _isQuestionLocked = false;
        _currentQuestionWinner = null;
        _isGameOver = false;
        _timerSeconds = questionTimeLimit;
        notifyListeners();
      } else if (msg.type == BattleMessageTypes.nextQuestion) {
        _currentQuestionIndex = msg.payload!['questionIndex'] as int;
        _isQuestionLocked = false;
        _currentQuestionWinner = null;
        _timerSeconds = questionTimeLimit;
        notifyListeners();
      } else if (msg.type == BattleMessageTypes.questionLocked) {
        _isQuestionLocked = true;
        _currentQuestionWinner = msg.payload!['winnerDeviceId'] as String;
        notifyListeners();
      } else if (msg.type == BattleMessageTypes.scoreUpdate) {
        final deviceId = msg.payload!['deviceId'];
        final score = msg.payload!['score'];
        final playerIndex = _players.indexWhere((p) => p.deviceId == deviceId);
        if (playerIndex != -1) {
          _players[playerIndex].score = score;
          notifyListeners();
        }
      } else if (msg.type == BattleMessageTypes.timerTick) {
        _timerSeconds = msg.payload!['seconds'] as int;
        notifyListeners();
      } else if (msg.type == BattleMessageTypes.gameOver) {
        _isGameOver = true;
        // Sync final player list from host
        if (msg.payload?['players'] != null) {
          _players.clear();
          final list = msg.payload!['players'] as List;
          for (var p in list) {
            _players.add(BattlePlayer.fromJson(p));
          }
        }
        notifyListeners();
      } else if (msg.type == BattleMessageTypes.kick) {
        disconnect();
      }
    } catch (e) {
      print('Error parsing message as guest: $e');
    }
  }

  void _sendMessageAsGuest(BattleMessage msg) {
    if (_clientSocket != null) {
      _clientSocket!.write(msg.encode() + '\n');
    }
  }

  /// GUEST: Mark as ready
  void setReady() {
    if (_isHost) return;
    _sendMessageAsGuest(BattleMessage(
      type: BattleMessageTypes.ready,
      payload: {'deviceId': _myDeviceId}
    ));
    // Optimistic UI update
    final idx = _players.indexWhere((p) => p.deviceId == _myDeviceId);
    if (idx != -1) {
      _players[idx].isReady = true;
      notifyListeners();
    }
  }

  /// ALL: Submit answer to current question.
  /// [isCorrect] – whether the selected answer was correct.
  void submitAnswer(bool isCorrect) {
    if (_isQuestionLocked) return; // Question already won by someone else

    if (_isHost) {
      // Host answers locally; resolve immediately
      if (isCorrect) {
        final idx = _players.indexWhere((p) => p.deviceId == _myDeviceId);
        if (idx != -1) {
          _players[idx].score += 10;
          _broadcastScoreUpdate(_myDeviceId, _players[idx].score);
        }
        _isQuestionLocked = true;
        _currentQuestionWinner = _myDeviceId;
        _questionTimer?.cancel();
        _broadcast(BattleMessage(
          type: BattleMessageTypes.questionLocked,
          payload: {'winnerDeviceId': _myDeviceId, 'questionIndex': _currentQuestionIndex},
        ));
        notifyListeners();
        Future.delayed(const Duration(seconds: 2), () {
          _advanceQuestion();
        });
      }
    } else {
      // Guest sends answer to host
      _sendMessageAsGuest(BattleMessage(
        type: BattleMessageTypes.questionAnswered,
        payload: {
          'deviceId': _myDeviceId,
          'isCorrect': isCorrect,
          'questionIndex': _currentQuestionIndex,
        },
      ));

      // Optimistic: if wrong, no UI change needed
      // Winner & lock will come back from host via QUESTION_LOCKED
    }
  }

  String get myDeviceId => _myDeviceId;

  /// Disconnect and clean up
  void disconnect() {
    _questionTimer?.cancel();
    _questionTimer = null;

    _serverSocket?.close();
    _serverSocket = null;
    
    for (var s in _clientConnections) {
      s.close();
    }
    _clientConnections.clear();
    
    _clientSocket?.close();
    _clientSocket = null;
    
    _isConnected = false;
    _isStarted = false;
    _isHost = false;
    _players.clear();
    _selectedSet = null;
    _quizCards.clear();
    _currentQuestionIndex = 0;
    _isQuestionLocked = false;
    _currentQuestionWinner = null;
    _isGameOver = false;
    _timerSeconds = questionTimeLimit;

    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

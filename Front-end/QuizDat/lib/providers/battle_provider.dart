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

  String _myDeviceId = '';
  String _myName = 'Player';
  
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

  /// HOST: Start the server
  Future<bool> startHosting() async {
    try {
      final info = NetworkInfo();
      _localIp = await info.getWifiIP() ?? '127.0.0.1';
      
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
      } else if (msg.type == BattleMessageTypes.scoreUpdate) {
        final deviceId = msg.payload!['deviceId'];
        final score = msg.payload!['score'];
        final playerIndex = _players.indexWhere((p) => p.deviceId == deviceId);
        if (playerIndex != -1) {
          _players[playerIndex].score = score;
          _broadcastScoreUpdate(deviceId, score);
        }
      }
    } catch (e) {
      print('Error parsing message as host: $e');
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
    _broadcast(BattleMessage(type: BattleMessageTypes.start));
    notifyListeners();
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
        notifyListeners();
      } else if (msg.type == BattleMessageTypes.scoreUpdate) {
        final deviceId = msg.payload!['deviceId'];
        final score = msg.payload!['score'];
        final playerIndex = _players.indexWhere((p) => p.deviceId == deviceId);
        if (playerIndex != -1) {
          _players[playerIndex].score = score;
          notifyListeners();
        }
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

  /// ALL: Update score
  void updateMyScore(int points) {
    final idx = _players.indexWhere((p) => p.deviceId == _myDeviceId);
    if (idx != -1) {
      _players[idx].score += points;
      
      if (_isHost) {
        _broadcastScoreUpdate(_myDeviceId, _players[idx].score);
      } else {
        _sendMessageAsGuest(BattleMessage(
          type: BattleMessageTypes.scoreUpdate,
          payload: {'deviceId': _myDeviceId, 'score': _players[idx].score}
        ));
      }
      notifyListeners();
    }
  }

  /// Disconnect and clean up
  void disconnect() {
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
    
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

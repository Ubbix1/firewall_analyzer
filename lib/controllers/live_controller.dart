import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/firewall_log.dart';
import '../models/live_packet_record.dart';
import '../services/authenticated_websocket_channel.dart';
import '../services/database_helper.dart';
import '../services/fcm_registration_service.dart';
import '../services/live_packet_parser.dart';
import '../services/log_analysis_service.dart';
import '../services/network_utils.dart';
import '../services/websocket_url_helper.dart';
import '../services/websocket_url_store.dart';

class LiveController extends ChangeNotifier with WidgetsBindingObserver {
  static const _maxPackets = 200;
  static const _retryDelay = Duration(seconds: 10);
  static const _readyTimeout = Duration(seconds: 4);

  final List<LivePacketRecord> _packets = [];
  final Map<String, int> _packetCounts = {};
  final List<LivePacketRecord> _incomingBuffer = [];
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _rateLimitTimer;
  
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _shouldReconnect = false;
  bool _isActive = true;
  String _statusMessage = 'Disconnected';
  int _nextPacketId = 1000000;
  String _lastUrl = '';
  Stopwatch? _connectionStopwatch;
  Timer? _durationTimer;
  String _connectedDuration = '00:00';
  bool _isSniffing = false;

  List<LivePacketRecord> get packets => _packets;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  String get statusMessage => _statusMessage;
  String get connectedDuration => _connectedDuration;
  bool get isSniffing => _isSniffing;
  
  LiveController() {
    WidgetsBinding.instance.addObserver(this);
    _startRateLimitTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _rateLimitTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  void setActive(bool active) {
    if (_isActive == active) return;
    _isActive = active;
    if (_isActive) {
      resume();
    } else {
      pause();
    }
  }

  void pause() {
    debugPrint('LiveController: Pausing processing');
    // We don't disconnect, but we can stop processing incoming packets or close the sub
    // if we want to be aggressive. For now, let's just stop the rate limit timer or 
    // simply let packets accumulate in buffer without UI updates.
    // Actually, user suggested pausing the subscription.
    _subscription?.pause();
  }

  void resume() {
    debugPrint('LiveController: Resuming processing');
    _subscription?.resume();
    if (_shouldReconnect && !_isConnected && !_isConnecting && _lastUrl.isNotEmpty) {
      connect(_lastUrl);
    }
  }

  Future<void> connect(String url) async {
    Uri? uri = parseWebSocketUri(url);
    if (uri == null) return;

    _lastUrl = url;
    _shouldReconnect = true;
    await disconnect(updateStateOnly: true);

    _isConnecting = true;
    _statusMessage = 'Resolving host and checking network...';
    _notify();

    try {
      // 1. Check if it's the same local network (WiFi check)
      final sameNetwork = await isSameLocalNetwork(uri);
      if (!sameNetwork) {
        _statusMessage = 'Warning: Server is on a different network. Connection may fail.';
        _notify();
        // We continue anyway, but the user is notified.
      }

      // 2. Direct Contacting: Use IP of domain if it's a domain
      if (!isIpAddress(uri.host) && uri.host != 'localhost') {
        try {
          final addresses = await InternetAddress.lookup(uri.host);
          if (addresses.isNotEmpty) {
            final ip = addresses.first.address;
            final host = uri?.host ?? '';
            debugPrint('LiveController: Resolved $host to $ip');
            uri = uri?.replace(host: ip);
            _statusMessage = 'Connecting to IP: $ip (resolved from domain)';
          }
        } catch (e) {
          final host = uri?.host ?? 'unknown';
          debugPrint('LiveController: DNS resolution failed for $host: $e');
          // Continue with original URI if resolution fails
        }
      } else {
        _statusMessage = 'Connecting to $url';
      }
      _notify();

      // Fix: Create a non-nullable Uri for the connection
      final targetUri = uri;
      if (targetUri == null) return;

      final channel = await connectAuthenticatedWebSocket(targetUri);
      _subscription = channel.stream.listen(
        (message) => _handleMessage(message),
        onError: (error) => _handleError(error),
        onDone: () => _handleDone(),
        cancelOnError: false,
      );

      await channel.ready.timeout(_readyTimeout);
      
      _channel = channel;
      _isConnected = true;
      _isConnecting = false;
      _statusMessage = 'Active Feed: ${targetUri.host}';
      _connectionStopwatch = Stopwatch()..start();
      _startDurationTimer();
      
      FcmRegistrationService.registerTokenOnChannel(channel);

      // Register
      channel.sink.add(jsonEncode({
        'action': 'get_history',
        'history_type': 'packet',
        'limit': _maxPackets,
      }));
      
      _notify();
      WebSocketUrlStore.save(url);
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      _statusMessage = 'Connection failed: $e';
      _notify();
      _scheduleReconnect();
    }
  }

  Future<void> disconnect({bool updateStateOnly = false}) async {
    _durationTimer?.cancel();
    _connectionStopwatch?.stop();
    _connectionStopwatch = null;
    _connectedDuration = '00:00';
    
    if (!updateStateOnly) {
      _shouldReconnect = false;
    }
    _retryTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _incomingBuffer.clear();
    _isConnected = false;
    _isConnecting = false;
    _isSniffing = false;
    if (!updateStateOnly) _statusMessage = 'Disconnected';
    _notify();
  }

  void _handleMessage(dynamic message) {
    final msgString = message.toString();
    
    // History sync
    if (msgString.contains('"history_response"')) {
      _handleHistoryResponse(msgString);
      return;
    }
    
    if (msgString.contains('"sniffing_status"')) {
      try {
        final decoded = jsonDecode(msgString);
        _isSniffing = decoded['running'] ?? false;
        _notify();
      } catch (_) {}
      return;
    }

    // Packet
    final packet = LivePacketParser.tryParse(message: msgString, id: _nextPacketId++);
    if (packet != null) {
      _incomingBuffer.add(packet);
      
      // Memory guard: If the buffer grows too large, flush immediately.
      // 1000 packets is a safe threshold before memory pressure becomes an issue.
      if (_incomingBuffer.length >= 1000) {
        _flushBuffer();
      }
    }
  }

  void _flushBuffer() {
    if (_incomingBuffer.isEmpty) return;
    
    final logsToInsert = <FirewallLog>[];
    while (_incomingBuffer.isNotEmpty) {
      final packet = _incomingBuffer.removeAt(0);
      _applyDeduplication(packet, _packets);
      logsToInsert.add(packet.log);
    }
    
    if (logsToInsert.isNotEmpty) {
      unawaited(_databaseHelper.upsertLogsBatch(logsToInsert));
    }
    
    if (_packets.length > _maxPackets) {
      _packets.removeRange(_maxPackets, _packets.length);
    }
    _notify();
  }

  void _handleHistoryResponse(String msgString) {
    try {
      final decoded = jsonDecode(msgString);
      if (decoded['type'] == 'history_response' && decoded['data'] != null) {
        final List<dynamic> historyData = decoded['data'];
        for (var item in historyData) {
          final packet = LivePacketParser.tryParse(message: jsonEncode(item), id: _nextPacketId++);
          if (packet != null) {
            _applyDeduplication(packet, _packets);
          }
        }
        _notify();
      }
    } catch (_) {}
  }

  void _handleError(dynamic error) {
    _isConnected = false;
    _isConnecting = false;
    _statusMessage = 'WebSocket error';
    _notify();
    _scheduleReconnect();
  }

  void _handleDone() {
    _isConnected = false;
    _isConnecting = false;
    _statusMessage = 'Connection closed';
    _notify();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _isConnected || _isConnecting) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      if (_shouldReconnect) connect(_lastUrl);
    });
  }

  void _startRateLimitTimer() {
    _rateLimitTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (!_isActive) return;
      _flushBuffer();
    });
  }

  void _applyDeduplication(LivePacketRecord packet, List<LivePacketRecord> list) {
    final analysis = LogAnalysisService.analyze(packet.log);
    if (analysis.riskLevel != 'Low') {
      list.insert(0, packet);
      return;
    }

    final ipKey = packet.log.ipAddress;
    final existingIndex = list.indexWhere((p) => p.log.ipAddress == ipKey && LogAnalysisService.analyze(p.log).riskLevel == 'Low');

    if (existingIndex != -1) {
      final existing = list.removeAt(existingIndex);
      list.insert(0, existing.copyWith(receivedAt: packet.receivedAt));
    } else {
      list.insert(0, packet);
    }
  }

  void clearPackets() {
    _packets.clear();
    _incomingBuffer.clear();
    _notify();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_connectionStopwatch != null) {
        final duration = _connectionStopwatch!.elapsed;
        final minutes = duration.inMinutes.toString().padLeft(2, '0');
        final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
        _connectedDuration = '$minutes:$seconds';
        _notify();
      }
    });
  }

  void startSniffing() {
    if (!_isConnected) return;
    _channel?.sink.add(jsonEncode({'action': 'start_sniffing'}));
  }

  void stopSniffing() {
    if (!_isConnected) return;
    _channel?.sink.add(jsonEncode({'action': 'stop_sniffing'}));
  }

  void _notify() {
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      pause();
    } else if (state == AppLifecycleState.resumed) {
      resume();
    }
  }
}

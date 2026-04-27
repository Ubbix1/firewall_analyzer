import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/server_status_snapshot.dart';
import '../services/authenticated_websocket_channel.dart';
import '../services/device_id_service.dart';
import '../services/network_utils.dart';
import '../services/server_status_parser.dart';
import '../services/server_status_service.dart';
import '../services/websocket_url_helper.dart';
import '../services/websocket_url_store.dart';

class ServerStatusController extends ChangeNotifier with WidgetsBindingObserver {
  static const _retryDelay = Duration(seconds: 10);
  static const _statusRequestInterval = Duration(seconds: 5);
  static const _defaultUrlOptions = <String>[defaultWebSocketUrl];
  static const _readyTimeout = Duration(seconds: 4);

  ServerStatusController({
    String initialWebSocketUrl = '',
    ServerStatusService? statusService,
  })  : _initialWebSocketUrl = initialWebSocketUrl,
        _statusService = statusService ?? ServerStatusService(),
        urlController = TextEditingController(text: initialWebSocketUrl) {
    urlController.addListener(_handleUrlChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadSavedUrl());
  }

  final String _initialWebSocketUrl;
  final ServerStatusService _statusService;
  final TextEditingController urlController;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _statusRequestTimer;

  List<String> _urlOptions = const [];
  ServerStatusSnapshot? _snapshot;
  bool _isDisposed = false;
  bool _isLoading = false;
  bool _isConnectingSocket = false;
  bool _isSocketConnected = false;
  bool _shouldReconnect = false;
  String _statusMessage = 'Idle';

  bool _isMemoryCritical = false;
  String? _serverMemoryWarning;

  List<String> get urlOptions => _urlOptions;
  ServerStatusSnapshot? get snapshot => _snapshot;
  bool get isLoading => _isLoading;
  bool get isConnectingSocket => _isConnectingSocket;
  bool get isSocketConnected => _isSocketConnected;
  String get statusMessage => _statusMessage;
  bool get isMemoryCritical => _isMemoryCritical;
  String? get serverMemoryWarning => _serverMemoryWarning;
  Uri? get currentUri => parseWebSocketUri(urlController.text.trim());
  Uri? get statusUri =>
      currentUri == null ? null : statusUriForWebSocketUri(currentUri!);

  bool isRemovableUrl(String url) {
    final trimmed = url.trim();
    return trimmed.isNotEmpty && trimmed != defaultWebSocketUrl;
  }

  Future<void> connectAndSync({ValueChanged<String>? onMessage}) async {
    final input = urlController.text.trim();
    if (input.isEmpty) {
      onMessage?.call('Enter the shared server URL first.');
      return;
    }

    final websocketUri = parseWebSocketUri(input);
    if (websocketUri == null) {
      onMessage?.call(
        'Invalid shared server URL. Example: wss://analyzer.plexaur.com',
      );
      return;
    }

    if (isPrivateNetworkWebSocketHost(websocketUri) ||
        isLocalOnlyWebSocketHost(websocketUri)) {
      onMessage?.call(
        'Shared server URL must be a public domain, not a local IP address.',
      );
      return;
    }

    final websocketUrl = websocketUri.toString();
    final nextStatusUri = statusUriForWebSocketUri(websocketUri);
    final nextStatusUrl = nextStatusUri.toString();

    _shouldReconnect = true;
    await disconnect(updateStateOnly: true);
    await WebSocketUrlStore.save(websocketUrl);
    final recentUrls = await WebSocketUrlStore.loadRecent();

    if (_isDisposed) {
      return;
    }

    _isLoading = true;
    _isConnectingSocket = true;
    _statusMessage = 'Syncing $nextStatusUrl and opening live status feed';
    urlController.text = websocketUrl;
    _urlOptions = _buildUrlOptions(
      savedUrl: websocketUrl,
      recentUrls: recentUrls,
      currentUrl: websocketUrl,
    );
    _notifySafely();

    final phoneHint = webSocketPhoneAccessHint(websocketUri);
    if (phoneHint.isNotEmpty) {
      onMessage?.call(phoneHint);
    }

    await _connectStatusWebSocket(websocketUri);

    if (!_isSocketConnected && !_isDisposed) {
      await _loadStatusSnapshot(nextStatusUri, onMessage: onMessage);
    }
  }

  Future<void> loadHttpSnapshot({ValueChanged<String>? onMessage}) async {
    final nextStatusUri = statusUri;
    if (nextStatusUri == null) {
      onMessage?.call('Enter a valid WebSocket URL first.');
      return;
    }

    if (_isSocketConnected && _channel != null) {
      _statusMessage = 'Requesting live refresh via WebSocket';
      _notifySafely();
      _requestStatusRefresh();
      return;
    }

    _isLoading = true;
    _statusMessage = 'Refreshing ${nextStatusUri.toString()}';
    _notifySafely();
    await _loadStatusSnapshot(nextStatusUri, onMessage: onMessage);
  }

  Future<void> disconnect({bool updateStateOnly = false}) async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _statusRequestTimer?.cancel();
    _statusRequestTimer = null;
    await _subscription?.cancel();
    await _channel?.sink.close();

    if (_isDisposed) {
      return;
    }

    _subscription = null;
    _channel = null;
    _isSocketConnected = false;
    _isConnectingSocket = false;
    _isLoading = false;
    if (!updateStateOnly) {
      _shouldReconnect = false;
      _statusMessage = 'Disconnected';
      _isMemoryCritical = false;
      _serverMemoryWarning = null;
    }
    _notifySafely();
  }

  Future<void> removeSelectedUrl({ValueChanged<String>? onMessage}) async {
    final selectedUrl = urlController.text.trim();
    if (!isRemovableUrl(selectedUrl)) {
      onMessage?.call('Only custom saved endpoints can be deleted.');
      return;
    }

    await WebSocketUrlStore.remove(selectedUrl);
    final fallbackUrl = await WebSocketUrlStore.load();
    final recentUrls = await WebSocketUrlStore.loadRecent();

    if (_isDisposed) {
      return;
    }

    urlController.text = fallbackUrl;
    _urlOptions = _buildUrlOptions(
      savedUrl: fallbackUrl,
      recentUrls: recentUrls,
      currentUrl: fallbackUrl,
    );
    _notifySafely();
    onMessage?.call('Removed saved endpoint.');
  }

  void selectSavedUrl(String? url) {
    if (url == null || url.isEmpty) {
      return;
    }
    urlController.text = url;
    _notifySafely();
  }

  List<String> _buildUrlOptions({
    String? savedUrl,
    List<String> recentUrls = const <String>[],
    String? currentUrl,
  }) {
    final urls = <String>{};
    if (currentUrl != null && currentUrl.isNotEmpty) {
      urls.add(currentUrl);
    }
    if (savedUrl != null && savedUrl.isNotEmpty) {
      urls.add(savedUrl);
    }
    urls.addAll(recentUrls.where((url) => url.trim().isNotEmpty));
    urls.addAll(_defaultUrlOptions);
    return urls.toList(growable: false);
  }

  Future<void> _loadSavedUrl() async {
    final initialUrl = _initialWebSocketUrl.trim();
    if (initialUrl.isNotEmpty) {
      await WebSocketUrlStore.save(initialUrl);
    }

    final savedUrl =
        initialUrl.isNotEmpty ? initialUrl : await WebSocketUrlStore.load();
    final validSavedUrl = () {
      final parsed = parseWebSocketUri(savedUrl);
      return parsed != null &&
              !isPrivateNetworkWebSocketHost(parsed) &&
              !isLocalOnlyWebSocketHost(parsed)
          ? savedUrl
          : defaultWebSocketUrl;
    }();
    final recentUrls = await WebSocketUrlStore.loadRecent();
    if (_isDisposed) {
      return;
    }

    if (urlController.text.trim().isEmpty && validSavedUrl.isNotEmpty) {
      urlController.text = validSavedUrl;
    }
    _urlOptions = _buildUrlOptions(
      savedUrl: validSavedUrl,
      recentUrls: recentUrls,
      currentUrl: urlController.text.trim(),
    );
    _notifySafely();

    if (!_isLoading && urlController.text.trim().isNotEmpty) {
      unawaited(connectAndSync());
    }
  }

  Future<void> _loadStatusSnapshot(
    Uri nextStatusUri, {
    ValueChanged<String>? onMessage,
  }) async {
    final nextStatusUrl = nextStatusUri.toString();

    try {
      final nextSnapshot = await _statusService.fetch(nextStatusUri);
      if (_isDisposed) {
        return;
      }

      _snapshot = nextSnapshot;
      _isLoading = false;
      _statusMessage = _isSocketConnected
          ? 'Live sync active on ${urlController.text.trim()}'
          : 'Loaded snapshot from $nextStatusUrl';
      _notifySafely();
    } catch (error) {
      if (_isDisposed) {
        return;
      }

      _isLoading = false;
      _statusMessage = _isSocketConnected
          ? 'Live sync active. HTTP refresh failed: $error'
          : 'Status request failed: $error';
      _notifySafely();
      onMessage?.call('Unable to load server status from $nextStatusUrl');
    }
  }

  Future<void> _connectStatusWebSocket(Uri websocketUri) async {
    final websocketUrl = websocketUri.toString();

    try {
      final channel = await connectAuthenticatedWebSocket(websocketUri);
      final subscription = channel.stream.listen(
        (message) {
          final decoded = jsonDecode(message.toString());
          if (decoded is! Map<String, dynamic>) return;

          if (decoded['type'] == 'server_warning') {
            final isWarning = decoded['is_warning'] ?? false;
            final isCritical = decoded['is_critical'] ?? false;
            
            if (!isWarning && !isCritical) {
              _serverMemoryWarning = null;
              _isMemoryCritical = false;
            } else {
              _serverMemoryWarning = decoded['message'];
              _isMemoryCritical = isCritical;
            }
            _notifySafely();
            return;
          }

          final nextSnapshot = ServerStatusParser.parse(message);
          if (nextSnapshot == null || _isDisposed) {
            return;
          }
          _snapshot = nextSnapshot;
          _statusMessage = 'Live sync active on $websocketUrl';
          _notifySafely();
        },
        onError: (error) {
          if (_isDisposed) {
            return;
          }
          _isSocketConnected = false;
          _isConnectingSocket = false;
          _statusMessage = 'Live status socket error: $error';
          _notifySafely();
          _scheduleReconnect();
        },
        onDone: () {
          if (_isDisposed) {
            return;
          }
          _isSocketConnected = false;
          _isConnectingSocket = false;
          _statusMessage = 'Live status socket closed';
          _notifySafely();
          _scheduleReconnect();
        },
        cancelOnError: false,
      );

      try {
        await channel.ready.timeout(_readyTimeout);
      } catch (_) {
        unawaited(subscription.cancel());
        unawaited(channel.sink.close());
        rethrow;
      }

      if (_isDisposed) {
        await subscription.cancel();
        await channel.sink.close();
        return;
      }

      _channel = channel;
      _subscription = subscription;
      _isSocketConnected = true;
      _isConnectingSocket = false;
      _isLoading = false;
      _statusMessage = 'Live sync active on $websocketUrl';
      _notifySafely();

      // Register device info
      unawaited(_registerDevice(channel));

      _startStatusRequests();
      _requestStatusRefresh();
    } catch (error) {
      if (_isDisposed) {
        return;
      }
      _isSocketConnected = false;
      _isConnectingSocket = false;
      _isLoading = false;
      _statusMessage = 'Live status connection failed: $error';
      _notifySafely();
      _scheduleReconnect();
    }
  }

  void _startStatusRequests() {
    _statusRequestTimer?.cancel();
    _statusRequestTimer = Timer.periodic(_statusRequestInterval, (_) {
      _requestStatusRefresh();
    });
  }

  void _requestStatusRefresh() {
    try {
      _channel?.sink.add(jsonEncode(const {'action': 'get_status'}));
    } catch (_) {}
  }

  Future<void> _registerDevice(WebSocketChannel channel) async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      Map<String, dynamic> deviceData = {};

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceData = {
          'name': androidInfo.model ?? 'Android Device',
          'model': androidInfo.model ?? 'Unknown',
          'manufacturer': androidInfo.manufacturer ?? 'Unknown',
          'androidVersion': androidInfo.version.release ?? 'Unknown',
          'sdkVersion': androidInfo.version.sdkInt?.toString() ?? 'Unknown',
          'brand': androidInfo.brand ?? 'Unknown',
          'device': androidInfo.device ?? 'Unknown',
          'hardware': androidInfo.hardware ?? 'Unknown',
          'platform': 'Android',
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceData = {
          'name': iosInfo.name ?? 'iOS Device',
          'model': iosInfo.model ?? 'Unknown',
          'systemVersion': iosInfo.systemVersion ?? 'Unknown',
          'platform': 'iOS',
        };
      }

      // Try to get MAC address (may not be available on all devices)
      try {
        // Note: Getting MAC address is restricted on modern Android/iOS
        // This might return null or throw an exception
        deviceData['macAddress'] = 'Not Available';
      } catch (e) {
        deviceData['macAddress'] = 'Not Available';
      }

      // Get unique device ID to ensure proper identification on same network
      final uniqueDeviceId = await DeviceIdService.getDeviceId();
      deviceData['deviceId'] = uniqueDeviceId;
      
      // Get the device's local network IP address
      final localIp = await getLocalNetworkIp();
      deviceData['localIp'] = localIp;
      
      debugPrint('Registering device with unique ID: $uniqueDeviceId, Local IP: $localIp');

      channel.sink.add(jsonEncode({
        'action': 'register_device',
        'device': deviceData,
      }));
    } catch (e) {
      // Ignore errors in device registration
      debugPrint('Error in device registration: $e');
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _isSocketConnected || _isConnectingSocket) {
      return;
    }

    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      if (_isDisposed || !_shouldReconnect) {
        return;
      }
      connectAndSync();
    });
  }

  void _handleUrlChanged() {
    _notifySafely();
  }

  void _notifySafely() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isDisposed = true;
    _retryTimer?.cancel();
    _statusRequestTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_channel?.sink.close());
    urlController.removeListener(_handleUrlChanged);
    urlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.hidden) {
      // Cleanly say goodbye to the server when closing or backgrounding
      unawaited(_subscription?.cancel());
      unawaited(_channel?.sink.close());
      _statusRequestTimer?.cancel();
      _retryTimer?.cancel();
      _isSocketConnected = false;
      _isConnectingSocket = false;
      _statusMessage = 'App backgrounded, socket closed';
      _notifySafely();
    } else if (state == AppLifecycleState.resumed) {
      // Reconnect instantly when returning to the app!
      if (_shouldReconnect && !_isSocketConnected && !_isConnectingSocket) {
        connectAndSync();
      }
    }
  }
}

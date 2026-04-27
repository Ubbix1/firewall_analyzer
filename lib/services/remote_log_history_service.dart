import 'dart:async';
import 'dart:convert';

import '../models/firewall_log.dart';
import 'authenticated_websocket_channel.dart';
import 'websocket_url_helper.dart';
import 'websocket_url_store.dart';

import '../constants/server_log_sources.dart';


class RemoteLogHistoryService {
  static const Duration _connectTimeout = Duration(seconds: 4);
  static const Duration _responseTimeout = Duration(seconds: 8);
  static const Duration _closeTimeout = Duration(seconds: 1);

  Future<List<FirewallLog>> fetchRecentLogs({
    required String source,
    int limit = 50,
    int offset = 0,
    void Function(FirewallLog? log, double progress)? onProgress,
  }) async {
    final uri = await _resolveRemoteUri();
    if (uri == null) {
      throw const FormatException('Saved WebSocket URL is invalid.');
    }

    final channel = await connectAuthenticatedWebSocket(uri);
    StreamSubscription<dynamic>? subscription;
    final completer = Completer<List<FirewallLog>>();

    try {
      await channel.ready.timeout(_connectTimeout);

      subscription = channel.stream.listen(
        (message) {
          if (completer.isCompleted) {
            return;
          }

          try {
            final decoded = jsonDecode(message.toString());
            if (decoded is! Map<String, dynamic>) {
              return;
            }

            if (decoded['type'] == 'history_progress') {
              final progress = decoded['progress']?.toDouble() ?? 0.0;
              final logData = decoded['log'];
              FirewallLog? log;
              if (logData != null) {
                log = FirewallLog.fromJson(Map<String, dynamic>.from(logData));
              }
              onProgress?.call(log, progress);
              return;
            }

            if (decoded['type'] != 'history_response' ||
                decoded['history_type'] != 'log') {
              return;
            }
            final responseSource = decoded['source']?.toString().trim() ?? '';
            if (responseSource != source) {
              return;
            }

            final rawData = decoded['data'];
            if (rawData is! List) {
              completer.complete(const <FirewallLog>[]);
              return;
            }

            final logs = rawData
                .whereType<Map>()
                .map(
                  (item) =>
                      FirewallLog.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false);
            completer.complete(logs);
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
        cancelOnError: false,
      );

      channel.sink.add(
        jsonEncode({
          'action': 'get_history',
          'history_type': 'log',
          'source': source,
          'limit': limit,
          'offset': offset,
        }),
      );

      return await completer.future.timeout(_responseTimeout);
    } finally {
      await subscription?.cancel();
      try {
        await channel.sink.close().timeout(_closeTimeout);
      } catch (_) {}
    }
  }

  Future<Uri?> _resolveRemoteUri() async {
    final savedUrl = await WebSocketUrlStore.load();
    final savedUri = parseWebSocketUri(savedUrl);
    if (savedUri != null && !isPrivateNetworkWebSocketHost(savedUri)) {
      return savedUri;
    }

    return parseWebSocketUri(defaultWebSocketUrl);
  }
}

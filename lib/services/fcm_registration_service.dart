import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'authenticated_websocket_channel.dart';
import 'websocket_url_helper.dart';
import 'websocket_url_store.dart';

class FcmRegistrationService {
  static const Duration _connectTimeout = Duration(seconds: 3);
  static const Duration _closeTimeout = Duration(seconds: 1);

  static Future<void> registerCurrentTokenWithSavedServer() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('FCM token unavailable; skipping server registration.');
      return;
    }

    await registerTokenWithSavedServer(token);
  }

  static Future<void> registerTokenWithSavedServer(String token) async {
    final websocketUrl = await WebSocketUrlStore.load();
    await registerTokenWithUrl(token: token, websocketUrl: websocketUrl);
  }

  static Future<void> registerTokenWithUrl({
    required String token,
    required String websocketUrl,
  }) async {
    final trimmedUrl = websocketUrl.trim();
    if (trimmedUrl.isEmpty) {
      debugPrint('No saved WebSocket URL; skipping token sync.');
      return;
    }

    final uri = parseWebSocketUri(trimmedUrl);
    if (uri == null) {
      debugPrint('Saved WebSocket URL is invalid; skipping token sync.');
      return;
    }

    final channel = await connectAuthenticatedWebSocket(uri);
    try {
      await channel.ready.timeout(_connectTimeout);
      channel.sink.add(jsonEncode({
        'action': 'register_fcm',
        'fcm_token': token,
      }));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      debugPrint('FCM token synced with server $trimmedUrl');
    } catch (error) {
      debugPrint('FCM token sync failed: $error');
    } finally {
      try {
        await channel.sink.close().timeout(_closeTimeout);
      } catch (_) {}
    }
  }

  static Future<void> registerTokenOnChannel(WebSocketChannel channel) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('FCM token unavailable; skipping channel registration.');
      return;
    }

    try {
      channel.sink.add(jsonEncode({
        'action': 'register_fcm',
        'fcm_token': token,
      }));
      debugPrint('FCM token registered on active channel.');
    } catch (error) {
      debugPrint('Failed to register FCM token on active channel: $error');
    }
  }
}

import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'websocket_url_helper.dart';
import 'device_id_service.dart';

Future<WebSocketChannel> connectAuthenticatedWebSocket(Uri uri) async {
  final deviceId = await DeviceIdService.getDeviceId();
  final authUri = authenticatedWebSocketUri(uri);
  final headers = generateAppAuthHeaders(
    'GET', 
    authUri.path, 
    '',
    deviceId: deviceId,
  );
  
  // Add a standard User-Agent to help with server-side filtering/identification
  headers['User-Agent'] = 'FirewallLogAnalyzer/3.5.0 (Mobile)';
  
  try {
    // Using WebSocket.connect directly gives us more control on Windows
    final ws = await WebSocket.connect(
      authUri.toString(),
      headers: headers,
    ).timeout(const Duration(seconds: 15));
    
    return IOWebSocketChannel(ws);
  } catch (e) {
    // Fallback to standard IOWebSocketChannel if direct connect fails
    return IOWebSocketChannel.connect(
      authUri,
      headers: headers,
    );
  }
}

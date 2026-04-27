import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'websocket_url_helper.dart';

import 'device_id_service.dart';

Future<WebSocketChannel> connectAuthenticatedWebSocket(Uri uri) async {
  final deviceId = await DeviceIdService.getDeviceId();
  return IOWebSocketChannel.connect(
    authenticatedWebSocketUri(uri),
    headers: generateAppAuthHeaders(
      'GET', 
      authenticatedWebSocketUri(uri).path, 
      '',
      deviceId: deviceId,
    ),
  );
}

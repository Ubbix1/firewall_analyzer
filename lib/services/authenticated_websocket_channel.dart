import 'package:web_socket_channel/web_socket_channel.dart';

import 'authenticated_websocket_channel_stub.dart'
    if (dart.library.io) 'authenticated_websocket_channel_io.dart'
    if (dart.library.html) 'authenticated_websocket_channel_web.dart'
    as connector;

Future<WebSocketChannel> connectAuthenticatedWebSocket(Uri uri) async {
  return await connector.connectAuthenticatedWebSocket(uri);
}

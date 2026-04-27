import 'package:web_socket_channel/web_socket_channel.dart';

import 'websocket_url_helper.dart';

WebSocketChannel connectAuthenticatedWebSocket(Uri uri) {
  return WebSocketChannel.connect(authenticatedWebSocketUri(uri));
}

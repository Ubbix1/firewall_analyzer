import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectAuthenticatedWebSocket(Uri uri) {
  throw UnsupportedError(
    'WebSocket access is only supported on the mobile app because '
    'analyzer.plexaur.com requires the X-App-Token header.',
  );
}

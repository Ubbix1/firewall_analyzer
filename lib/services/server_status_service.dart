import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/server_status_snapshot.dart';
import 'server_status_parser.dart';
import 'websocket_url_helper.dart';

import 'device_id_service.dart';

class ServerStatusService {
  static const Duration _timeout = Duration(seconds: 5);

  Future<ServerStatusSnapshot> fetch(Uri uri) async {
    final deviceId = await DeviceIdService.getDeviceId();
    final response = await http
        .get(
          authenticatedHttpUri(uri),
          headers: generateAppAuthHeaders(
            'GET', 
            authenticatedHttpUri(uri).path, 
            '',
            deviceId: deviceId,
          ),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }

    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    final snapshot = ServerStatusParser.parse(payload);
    if (snapshot == null) {
      throw const FormatException('Unexpected server status payload.');
    }

    return snapshot;
  }
}

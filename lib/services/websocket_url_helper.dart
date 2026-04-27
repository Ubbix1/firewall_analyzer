import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const String defaultWebSocketUrl = 'wss://analyzer.plexaur.com';
const String defaultServerIp = '192.168.29.77';
const String defaultStatusUrl = 'https://analyzer.plexaur.com/status';
const String _appAccessToken = String.fromEnvironment('APP_ACCESS_TOKEN', defaultValue: '');

String get appAccessToken => _appAccessToken.trim();

bool get hasAppAccessToken => appAccessToken.isNotEmpty;

final _random = Random.secure();

Map<String, String> generateAppAuthHeaders(String method, String path, String body, {String? deviceId}) {
  if (!hasAppAccessToken) {
    return const <String, String>{};
  }

  final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final nonceBytes = List<int>.generate(16, (_) => _random.nextInt(256));
  final nonce = nonceBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // Normalize path: server expects empty string for root '/'
  final normalizedPath = path == '/' ? '' : path;

  // Include deviceId in the signature payload to bind the connection to a specific device
  final payload = '$method:$normalizedPath:$body:$timestamp:$nonce${deviceId != null ? ":$deviceId" : ""}';
  final hmac = Hmac(sha256, utf8.encode(appAccessToken));
  final signature = hmac.convert(utf8.encode(payload)).toString();

  final headers = {
    'X-App-Timestamp': timestamp,
    'X-App-Nonce': nonce,
    'X-App-Signature': signature,
  };

  if (deviceId != null) {
    headers['X-Device-Id'] = deviceId;
  }

  return headers;
}

Uri authenticatedWebSocketUri(Uri uri) => normalizeWebSocketEndpointUri(uri);

Uri authenticatedHttpUri(Uri uri) => uri;

Uri normalizeWebSocketEndpointUri(Uri uri) {
  final normalizedScheme = switch (uri.scheme.toLowerCase()) {
    'https' => 'wss',
    'http' => 'ws',
    'wss' => 'wss',
    _ => 'ws',
  };
  final fromStatusEndpoint = _isStatusPath(uri.path);
  final port = _webSocketPortForUri(
    uri,
    normalizedScheme,
    fromStatusEndpoint: fromStatusEndpoint,
  );
  final effectivePort = port == 0 ? (normalizedScheme == 'wss' ? 443 : 80) : port;
  final path = _normalizeWebSocketPath(uri.path);

  return Uri(
    scheme: normalizedScheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: effectivePort,
    path: path,
  );
}

Uri statusUriForWebSocketUri(Uri uri) {
  final normalizedUri = normalizeWebSocketEndpointUri(uri);
  final scheme = switch (normalizedUri.scheme.toLowerCase()) {
    'wss' => 'https',
    'ws' => 'http',
    'https' => 'https',
    _ => 'http',
  };
  final port = _statusPortForWebSocketUri(normalizedUri, scheme);
  final path = _statusPathForWebSocketPath(normalizedUri.path);

  return authenticatedHttpUri(
    Uri(
      scheme: scheme,
      userInfo: normalizedUri.userInfo,
      host: normalizedUri.host,
      port: port,
      path: path,
    ),
  );
}

int _webSocketPortForUri(
  Uri uri,
  String scheme, {
  bool fromStatusEndpoint = false,
}) {
  if (!uri.hasPort) {
    return 0;
  }

  if (fromStatusEndpoint && uri.port == 5000) {
    return 8765;
  }

  final isDefaultWsPort = scheme == 'ws' && uri.port == 80;
  final isDefaultWssPort = scheme == 'wss' && uri.port == 443;
  if (isDefaultWsPort || isDefaultWssPort) {
    return 0;
  }

  return uri.port;
}

String _normalizeWebSocketPath(String path) {
  final normalizedPath = path.trim();
  if (normalizedPath.isEmpty || normalizedPath == '/') {
    return '';
  }

  if (_isStatusPath(normalizedPath)) {
    final strippedStatusPath = normalizedPath.replaceFirst(
      RegExp(r'/status/?$', caseSensitive: false),
      '',
    );
    if (strippedStatusPath.isEmpty || strippedStatusPath == '/') {
      return '';
    }
    return _trimTrailingSlash(strippedStatusPath);
  }

  return _trimTrailingSlash(normalizedPath);
}

String _statusPathForWebSocketPath(String path) {
  final normalizedPath = _normalizeWebSocketPath(path);
  if (normalizedPath.isEmpty) {
    return '/status';
  }
  return '${_trimTrailingSlash(normalizedPath)}/status';
}

String _trimTrailingSlash(String value) {
  if (value.length <= 1) {
    return value;
  }
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

bool _isStatusPath(String path) {
  final normalized = path.trim().toLowerCase();
  return normalized == '/status' || normalized.endsWith('/status');
}

int _statusPortForWebSocketUri(Uri uri, String scheme) {
  if (!uri.hasPort) {
    return 0;
  }

  if (uri.port == 8765) {
    return 5000;
  }

  final isDefaultHttpPort = scheme == 'http' && uri.port == 80;
  final isDefaultHttpsPort = scheme == 'https' && uri.port == 443;
  if (isDefaultHttpPort || isDefaultHttpsPort) {
    return 0;
  }

  return uri.port;
}

Uri? parseWebSocketUri(String rawInput) {
  final trimmed = rawInput.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final withScheme = trimmed.contains('://') ? trimmed : 'ws://$trimmed';

  Uri parsed;
  try {
    parsed = Uri.parse(withScheme);
  } catch (_) {
    return null;
  }

  parsed = parsed.removeFragment();

  final scheme = parsed.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    parsed = parsed.replace(scheme: scheme == 'https' ? 'wss' : 'ws');
  } else if (scheme != 'ws' && scheme != 'wss') {
    return null;
  }

  if (parsed.host.isEmpty) {
    return null;
  }

  return normalizeWebSocketEndpointUri(parsed);
}

bool isLocalOnlyWebSocketHost(Uri uri) {
  final host = uri.host.toLowerCase();
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '0.0.0.0' ||
      host == defaultServerIp;
}

bool isIpAddress(String host) {
  final regExp = RegExp(
    r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$',
  );
  return regExp.hasMatch(host);
}

bool isPrivateNetworkWebSocketHost(Uri uri) {
  if (isLocalOnlyWebSocketHost(uri)) {
    return true;
  }

  final host = uri.host.trim().toLowerCase();
  final parts = host.split('.');
  if (parts.length != 4) {
    return false;
  }

  final octets = parts.map(int.tryParse).toList(growable: false);
  if (octets.any((octet) => octet == null)) {
    return false;
  }

  final first = octets[0]!;
  final second = octets[1]!;
  if (first == 10 || first == 127) {
    return true;
  }
  if (first == 192 && second == 168) {
    return true;
  }
  if (first == 172 && second >= 16 && second <= 31) {
    return true;
  }
  return false;
}

String webSocketPhoneAccessHint(Uri uri) {
  if (!isLocalOnlyWebSocketHost(uri)) {
    return '';
  }
  return 'Use your computer\'s LAN IP, for example ws://192.168.1.10:8765, instead of ${uri.host}.';
}

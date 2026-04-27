import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'websocket_url_helper.dart';

class WebSocketUrlStore {
  static const _key = 'websocket_url';
  static const _recentKey = 'websocket_recent_urls';
  static const _maxRecentUrls = 6;
  static const _expirationDays = 30;

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_key)?.trim() ?? '';
    if (savedUrl.isNotEmpty) {
      final parsed = parseWebSocketUri(savedUrl);
      if (parsed != null) {
        return savedUrl;
      }
    }

    final defaultUrl = 'ws://$defaultServerIp:8765';
    await save(defaultUrl);
    return defaultUrl;
  }

  static Future<void> save(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, url);

    final recentUrlsJson = prefs.getStringList(_recentKey) ?? const <String>[];
    final now = DateTime.now().toIso8601String();
    final newEntry = jsonEncode({'url': url, 'timestamp': now});
    final updatedUrls = <String>[
      newEntry,
      ...recentUrlsJson.where((candidate) {
        try {
          final decoded = jsonDecode(candidate) as Map<String, dynamic>;
          return decoded['url'] != url;
        } catch (_) {
          return false;
        }
      }),
    ];
    if (updatedUrls.length > _maxRecentUrls) {
      updatedUrls.removeRange(_maxRecentUrls, updatedUrls.length);
    }
    await prefs.setStringList(_recentKey, updatedUrls);
  }

  static Future<List<String>> loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final recentUrlsJson = prefs.getStringList(_recentKey) ?? <String>[];
    final cutoff = DateTime.now().subtract(Duration(days: _expirationDays));
    final validUrls = <String>[];
    for (final jsonStr in recentUrlsJson) {
      try {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final timestamp = DateTime.parse(decoded['timestamp'] as String);
        if (timestamp.isAfter(cutoff)) {
          validUrls.add(decoded['url'] as String);
        }
      } catch (_) {
        // Skip invalid entries
      }
    }
    return validUrls;
  }

  static Future<void> remove(String url) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final recentUrlsJson = prefs.getStringList(_recentKey) ?? const <String>[];
    final updatedUrls = recentUrlsJson
        .where((candidate) {
          try {
            final decoded = jsonDecode(candidate) as Map<String, dynamic>;
            return decoded['url'] != trimmedUrl;
          } catch (_) {
            return false;
          }
        })
        .toList(growable: false);

    await prefs.setStringList(_recentKey, updatedUrls);

    final savedUrl = prefs.getString(_key)?.trim() ?? '';
    if (savedUrl == trimmedUrl) {
      if (updatedUrls.isEmpty) {
        await prefs.remove(_key);
      } else {
        try {
          final decoded = jsonDecode(updatedUrls.first) as Map<String, dynamic>;
          await prefs.setString(_key, decoded['url'] as String);
        } catch (_) {
          await prefs.remove(_key);
        }
      }
    }
  }
}

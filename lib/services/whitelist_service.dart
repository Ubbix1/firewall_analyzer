import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WhitelistService {
  static const String _whitelistKey = 'firewall_whitelist_ips';
  static const String _whitelistDescriptionsKey = 'firewall_whitelist_descriptions';

  /// Get all whitelisted IPs
  static Future<Set<String>> getWhitelistedIps() async {
    final prefs = await SharedPreferences.getInstance();
    final whitelisted = prefs.getStringList(_whitelistKey) ?? [];
    return whitelisted.toSet();
  }

  /// Get description for a whitelisted IP
  static Future<String?> getWhitelistDescription(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    final descriptions = prefs.getStringList(_whitelistDescriptionsKey) ?? [];
    // Descriptions are stored as "ip:description" pairs
    for (final item in descriptions) {
      if (item.startsWith('$ip:')) {
        return item.substring(ip.length + 1);
      }
    }
    return null;
  }

  /// Add IP to whitelist with optional description
  static Future<void> addToWhitelist(
    String ip, {
    String? description,
  }) async {
    if (ip.trim().isEmpty) {
      throw ArgumentError('IP address cannot be empty');
    }

    final prefs = await SharedPreferences.getInstance();
    final whitelisted = prefs.getStringList(_whitelistKey) ?? [];
    final descriptions = prefs.getStringList(_whitelistDescriptionsKey) ?? [];

    final trimmedIp = ip.trim();

    // Add IP if not already present
    if (!whitelisted.contains(trimmedIp)) {
      whitelisted.add(trimmedIp);
      await prefs.setStringList(_whitelistKey, whitelisted);
      debugPrint('Added $trimmedIp to whitelist');
    }

    // Add or update description
    if (description != null && description.trim().isNotEmpty) {
      descriptions.removeWhere((item) => item.startsWith('$trimmedIp:'));
      descriptions.add('$trimmedIp:${description.trim()}');
      await prefs.setStringList(_whitelistDescriptionsKey, descriptions);
    }
  }

  /// Remove IP from whitelist
  static Future<void> removeFromWhitelist(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    final whitelisted = prefs.getStringList(_whitelistKey) ?? [];
    final descriptions = prefs.getStringList(_whitelistDescriptionsKey) ?? [];

    whitelisted.remove(ip.trim());
    descriptions.removeWhere((item) => item.startsWith('${ip.trim()}:'));

    await prefs.setStringList(_whitelistKey, whitelisted);
    await prefs.setStringList(_whitelistDescriptionsKey, descriptions);
    debugPrint('Removed ${ip.trim()} from whitelist');
  }

  /// Check if IP is whitelisted
  static Future<bool> isWhitelisted(String ip) async {
    final whitelisted = await getWhitelistedIps();
    return whitelisted.contains(ip.trim());
  }

  /// Get all whitelisted IPs with descriptions
  static Future<Map<String, String?>> getAllWhitelist() async {
    final whitelisted = await getWhitelistedIps();
    final result = <String, String?>{};

    for (final ip in whitelisted) {
      final description = await getWhitelistDescription(ip);
      result[ip] = description;
    }

    return result;
  }

  /// Clear all whitelisted IPs
  static Future<void> clearWhitelist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_whitelistKey);
    await prefs.remove(_whitelistDescriptionsKey);
    debugPrint('Cleared whitelist');
  }

  /// Add common local network ranges to whitelist
  static Future<void> addCommonInternalRanges() async {
    final commonRanges = {
      '127.0.0.1': 'Localhost',
      '192.168.0.0': 'Private Network (192.168.x.x)',
      '10.0.0.0': 'Private Network (10.x.x.x)',
      '172.16.0.0': 'Private Network (172.16-31.x.x)',
    };

    for (final entry in commonRanges.entries) {
      await addToWhitelist(entry.key, description: entry.value);
    }

    debugPrint('Added common internal ranges to whitelist');
  }
}

import 'package:flutter/foundation.dart';
import '../models/firewall_log.dart';
import '../models/geo_data.dart';

class GeoIpService {
  // Singleton so the in-memory local-classification cache is shared across all
  // callers. Public GeoIP enrichment is owned by packet_server.py.
  static final GeoIpService _instance = GeoIpService._internal();
  factory GeoIpService() => _instance;
  GeoIpService._internal();

  final Map<String, GeoData> _countryCache = {};

  Future<List<FirewallLog>> enrichLogs(List<FirewallLog> logs) async {
    if (logs.isEmpty) return logs;
    
    // Batch processing logs in a background isolate to keep UI responsive.
    // For very large sets (1000+), compute handles serialization/deserialization 
    // which has its own cost, but it's still better than blocking the main loop.
    return await compute(_enrichLogsIsolate, logs);
  }

  static List<FirewallLog> _enrichLogsIsolate(List<FirewallLog> logs) {
    final service = GeoIpService._internal();
    final enrichedLogs = <FirewallLog>[];
    for (final log in logs) {
      enrichedLogs.add(service._enrichLogSync(log));
    }
    return enrichedLogs;
  }

  FirewallLog _enrichLogSync(FirewallLog log) {
    final currentCountry = log.country.trim();
    if (currentCountry.isNotEmpty &&
        currentCountry.toLowerCase() != 'unknown') {
      return log;
    }

    final geoData = lookupCountry(log.ipAddress);
    if (geoData.country.toLowerCase() == 'unknown') {
      return log;
    }

    if (geoData.country == log.country &&
        log.latitude == geoData.latitude &&
        log.longitude == geoData.longitude) {
      return log;
    }

    return log.copyWith(
      country: geoData.country,
      latitude: geoData.latitude,
      longitude: geoData.longitude,
    );
  }

  Future<FirewallLog> enrichLog(FirewallLog log) async {
    final currentCountry = log.country.trim();
    if (currentCountry.isNotEmpty &&
        currentCountry.toLowerCase() != 'unknown') {
      return log;
    }

    final geoData = lookupCountry(log.ipAddress);
    if (geoData.country.toLowerCase() == 'unknown') {
      return log;
    }

    if (geoData.country == log.country &&
        log.latitude == geoData.latitude &&
        log.longitude == geoData.longitude) {
      return log;
    }

    return log.copyWith(
      country: geoData.country,
      latitude: geoData.latitude,
      longitude: geoData.longitude,
    );
  }

  GeoData lookupCountry(String ipAddress) {
    final normalizedIp = ipAddress.trim();
    if (normalizedIp.isEmpty) {
      return GeoData.unknown();
    }

    if (_countryCache.containsKey(normalizedIp)) {
      return _countryCache[normalizedIp]!;
    }

    final localClassification = _localClassification(normalizedIp);
    if (localClassification != null) {
      final geoData = GeoData(country: localClassification);
      _countryCache[normalizedIp] = geoData;
      return geoData;
    }

    final geoData = GeoData.unknown();
    _countryCache[normalizedIp] = geoData;
    return geoData;
  }

  String? _localClassification(String ipAddress) {
    if (ipAddress == '127.0.0.1' || ipAddress == '::1') {
      return 'Loopback';
    }

    if (_isPrivateIpv4(ipAddress) || _isPrivateIpv6(ipAddress)) {
      return 'Private Network';
    }

    if (ipAddress.startsWith('169.254.') ||
        ipAddress.toLowerCase().startsWith('fe80:')) {
      return 'Link Local';
    }

    if (ipAddress.startsWith('192.0.2.') ||
        ipAddress.startsWith('198.51.100.') ||
        ipAddress.startsWith('203.0.113.')) {
      return 'Reserved Range';
    }

    return null;
  }

  bool _isPrivateIpv4(String ipAddress) {
    return ipAddress.startsWith('10.') ||
        ipAddress.startsWith('192.168.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(ipAddress);
  }

  bool _isPrivateIpv6(String ipAddress) {
    final normalized = ipAddress.toLowerCase();
    return normalized.startsWith('fc') || normalized.startsWith('fd');
  }
}

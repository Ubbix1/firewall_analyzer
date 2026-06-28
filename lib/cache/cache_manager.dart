import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/server_status_snapshot.dart';

class CacheManager {
  static const String serverStatusBoxName = 'server_status_cache';
  static const String devicesBoxName = 'devices_cache';
  static const String scloudBoxName = 'scloud_cache';
  static const String metadataBoxName = 'cache_metadata';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(serverStatusBoxName);
    await Hive.openBox(devicesBoxName);
    await Hive.openBox(scloudBoxName);
    await Hive.openBox(metadataBoxName);
  }

  // --- Server Status ---
  
  static Future<void> saveServerStatus(Map<String, dynamic> data) async {
    final box = Hive.box(serverStatusBoxName);
    // Store as JSON string for maximum reliability on Android
    await box.put('latest', jsonEncode(data));
    await _updateMetadata(serverStatusBoxName);
    await box.flush(); // Force write to disk
  }

  static Map<String, dynamic>? getServerStatus() {
    final box = Hive.box(serverStatusBoxName);
    final rawData = box.get('latest');
    if (rawData == null) return null;
    
    try {
      if (rawData is String) {
        return jsonDecode(rawData) as Map<String, dynamic>;
      }
      return (rawData as Map).cast<String, dynamic>();
    } catch (e) {
      debugPrint('Error decoding cached server status: $e');
      return null;
    }
  }

  // --- Registered Devices ---

  // --- Registered Devices ---

  static Future<void> saveDevices(List<dynamic> devices) async {
    final box = Hive.box(devicesBoxName);
    await box.put('list', jsonEncode(devices));
    await _updateMetadata(devicesBoxName);
    await box.flush();
  }

  static List<dynamic>? getDevices() {
    final box = Hive.box(devicesBoxName);
    final rawData = box.get('list');
    if (rawData == null) return null;
    try {
      if (rawData is String) {
        return jsonDecode(rawData) as List<dynamic>;
      }
      return rawData as List<dynamic>;
    } catch (e) {
      return null;
    }
  }

  // --- SCloud Status ---

  static Future<void> saveSCloudStatus(Map<String, dynamic> data) async {
    final box = Hive.box(scloudBoxName);
    await box.put('latest', jsonEncode(data));
    await _updateMetadata(scloudBoxName);
    await box.flush();
  }

  static Map<String, dynamic>? getSCloudStatus() {
    final box = Hive.box(scloudBoxName);
    final rawData = box.get('latest');
    if (rawData == null) return null;
    try {
      if (rawData is String) {
        return jsonDecode(rawData) as Map<String, dynamic>;
      }
      return (rawData as Map).cast<String, dynamic>();
    } catch (e) {
      return null;
    }
  }

  // --- Metadata ---

  static Future<void> _updateMetadata(String key) async {
    final box = Hive.box(metadataBoxName);
    await box.put(key, DateTime.now().toIso8601String());
  }

  static DateTime? getCacheTime(String key) {
    final box = Hive.box(metadataBoxName);
    final timeStr = box.get(key);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  static bool isStale(String key, Duration expiry) {
    final cacheTime = getCacheTime(key);
    if (cacheTime == null) return true;
    return DateTime.now().difference(cacheTime) > expiry;
  }
}

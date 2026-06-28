import 'dart:async';
import '../cache/cache_manager.dart';
import 'package:flutter/foundation.dart';

class DevicesRepository {
  List<Map<String, dynamic>> _cachedDevices = [];
  List<Map<String, dynamic>> get cachedDevices => _cachedDevices;

  Stream<List<Map<String, dynamic>>> getDevices() async* {
    final cached = CacheManager.getDevices();
    if (cached != null) {
      _cachedDevices = List<Map<String, dynamic>>.from(cached);
      yield _cachedDevices;
    }
  }

  Future<void> updateCache(List<Map<String, dynamic>> devices) async {
    _cachedDevices = devices;
    await CacheManager.saveDevices(devices);
  }

  DateTime? get lastUpdated => CacheManager.getCacheTime(CacheManager.devicesBoxName);
}

class SCloudRepository {
  Map<String, String> _cachedStatus = {};
  Map<String, String> get cachedStatus => _cachedStatus;

  Stream<Map<String, String>> getCloudStatus() async* {
    final cached = CacheManager.getSCloudStatus();
    if (cached != null) {
      _cachedStatus = Map<String, String>.from(cached);
      yield _cachedStatus;
    }
  }

  Future<void> updateCache(Map<String, String> status) async {
    _cachedStatus = status;
    await CacheManager.saveSCloudStatus(status);
  }

  DateTime? get lastUpdated => CacheManager.getCacheTime(CacheManager.scloudBoxName);
}

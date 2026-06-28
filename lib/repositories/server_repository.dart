import 'dart:async';
import '../cache/cache_manager.dart';
import '../models/server_status_snapshot.dart';
import '../services/server_status_service.dart';
import 'package:flutter/foundation.dart';

class ServerRepository {
  final ServerStatusService _service;
  
  ServerRepository({ServerStatusService? service}) : _service = service ?? ServerStatusService();

  // Observable state for listeners
  ServerStatusSnapshot? _latestSnapshot;
  ServerStatusSnapshot? get latestSnapshot => _latestSnapshot;

  /// Loads cached status immediately, then attempts to fetch live data
  Stream<ServerStatusSnapshot> getServerStatus(Uri uri) async* {
    // 1. Emit cached data if available
    final cachedData = CacheManager.getServerStatus();
    if (cachedData != null) {
      try {
        _latestSnapshot = ServerStatusSnapshot.fromJson(cachedData);
        yield _latestSnapshot!;
      } catch (e) {
        debugPrint('Error parsing cached server status: $e');
      }
    }

    // 2. Fetch live data
    try {
      final liveSnapshot = await _service.fetch(uri);
      
      // 3. Save to cache
      await CacheManager.saveServerStatus(liveSnapshot.toJson());
      
      _latestSnapshot = liveSnapshot;
      yield liveSnapshot;
    } catch (e) {
      debugPrint('Error fetching live server status: $e');
      // If live fetch fails, we've already yielded the cache (if any)
    }
  }

  /// Updates cache from a WebSocket message
  Future<void> updateFromLive(ServerStatusSnapshot snapshot) async {
    _latestSnapshot = snapshot;
    await CacheManager.saveServerStatus(snapshot.toJson());
  }

  /// Helper to get cache metadata
  DateTime? get lastUpdated => CacheManager.getCacheTime(CacheManager.serverStatusBoxName);
}

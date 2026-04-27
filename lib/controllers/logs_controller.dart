import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/firewall_log.dart';
import '../models/recent_file_entry.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/geo_ip_service.dart';
import '../services/log_analysis_service.dart';
import '../services/log_parser.dart';
import '../services/remote_log_history_service.dart';
import '../constants/server_log_sources.dart';

class LogsController extends ChangeNotifier {
  static const _pageSize = 50;
  static const _maxLogsCount = 5000; // Memory guard

  static const logViewOptions = [
    'All saved logs',
    'Firewall logs',
    'System logs',
    'Auth logs',
    'Error logs',
    'Main logs',
    'High threats only',
  ];

  final DatabaseHelper _databaseHelper;
  final GeoIpService _geoIpService;
  final ExportService _exportService;
  final RemoteLogHistoryService _remoteLogHistoryService;

  final TextEditingController searchController = TextEditingController();

  List<FirewallLog> logs = [];
  List<RecentFileEntry> recentFiles = [];
  String? currentAttackStatus;
  String? activeFilePath;
  String? activeServerLogSourceId;

  String? statusFilter;
  String sortBy = 'timestamp';
  bool ascending = false;
  String logViewFilter = 'All saved logs';

  bool isLoading = false;
  bool isEnriching = false;
  bool isLoadingMoreRemoteLogs = false;
  bool hasMoreRemoteLogs = false;
  int _remoteLogOffset = 0;
  double loadingProgress = 0.0;
  String? loadingStatusMessage;

  int _visibleLogCount = _pageSize;
  List<FirewallLog>? _cachedFilteredLogs;
  String _lastSearchQuery = '';

  bool _isOperationCancelled = false;
  bool _disposed = false;

  LogsController({
    DatabaseHelper? databaseHelper,
    GeoIpService? geoIpService,
    ExportService? exportService,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper(),
        _geoIpService = geoIpService ?? GeoIpService(),
        _exportService = exportService ?? ExportService(),
        _remoteLogHistoryService = RemoteLogHistoryService() {
    searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    searchController.removeListener(_handleSearchChanged);
    searchController.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  List<FirewallLog> get filteredLogs {
    final query = searchController.text.trim().toLowerCase();
    if (_cachedFilteredLogs == null || query != _lastSearchQuery) {
      _cachedFilteredLogs = _buildFilteredLogs(query);
      _lastSearchQuery = query;
    }
    return _cachedFilteredLogs!;
  }

  void _invalidateFilterCache() {
    _cachedFilteredLogs = null;
  }

  List<FirewallLog> _buildFilteredLogs(String query) {
    var result = List<FirewallLog>.from(logs);
    result = result.where(_matchesLogViewFilter).toList();

    if (query.isNotEmpty) {
      result = result.where((log) {
        return log.ipAddress.toLowerCase().contains(query) ||
            log.url.toLowerCase().contains(query) ||
            log.userAgent.toLowerCase().contains(query) ||
            log.request.toLowerCase().contains(query) ||
            log.country.toLowerCase().contains(query);
      }).toList();
    }

    if (statusFilter != null) {
      result = result.where((log) => log.responseCode.toString() == statusFilter).toList();
    }

    result.sort((a, b) {
      int compare;
      switch (sortBy) {
        case 'ipAddress':
          compare = a.ipAddress.compareTo(b.ipAddress);
          break;
        case 'responseCode':
          compare = a.responseCode.compareTo(b.responseCode);
          break;
        case 'risk':
          // Uses the cached score for O(n log n) primitive sorting
          compare = LogAnalysisService.analyze(a).severityScore.compareTo(
                LogAnalysisService.analyze(b).severityScore,
              );
          break;
        case 'url':
          compare = a.url.compareTo(b.url);
          break;
        case 'timestamp':
        default:
          compare = a.timestamp.compareTo(b.timestamp);
      }
      return ascending ? compare : -compare;
    });

    return result;
  }

  List<FirewallLog> get visibleLogs {
    if (activeServerLogSourceId != null) return filteredLogs;
    final filtered = filteredLogs;
    final end = _visibleLogCount > filtered.length ? filtered.length : _visibleLogCount;
    return filtered.sublist(0, end);
  }

  bool get hasMoreLogs {
    if (activeServerLogSourceId != null) {
      return hasMoreRemoteLogs || isLoadingMoreRemoteLogs;
    }
    return visibleLogs.length < filteredLogs.length;
  }

  void loadMoreLocalLogs() {
    _visibleLogCount += _pageSize;
    _notify();
  }

  void _handleSearchChanged() {
    _invalidateFilterCache();
    _visibleLogCount = _pageSize;
    _notify();
  }

  void setStatusFilter(String? value) {
    statusFilter = value;
    _invalidateFilterCache();
    _visibleLogCount = _pageSize;
    _notify();
  }

  void setSortBy(String value) {
    sortBy = value;
    _invalidateFilterCache();
    _visibleLogCount = _pageSize;
    _notify();
  }

  void setAscending(bool value) {
    ascending = value;
    _invalidateFilterCache();
    _notify();
  }

  void setLogViewFilter(String value) {
    logViewFilter = value;
    _invalidateFilterCache();
    _visibleLogCount = _pageSize;
    _notify();
  }

  Future<void> refreshData() async {
    final storedLogs = await _databaseHelper.getLogs();
    final storedRecentFiles = await _databaseHelper.getRecentFiles();

    if (_disposed) return;

    // Memory guard
    if (storedLogs.length > _maxLogsCount) {
      logs = storedLogs.sublist(0, _maxLogsCount);
    } else {
      logs = storedLogs;
    }

    recentFiles = storedRecentFiles;
    currentAttackStatus = LogAnalysisService.overview(logs);
    _invalidateFilterCache();
    _visibleLogCount = _pageSize;
    _notify();
  }

  void stopLoading() {
    _isOperationCancelled = true;
    isLoading = false;
    isLoadingMoreRemoteLogs = false;
    loadingStatusMessage = 'Loading stopped';
    loadingProgress = 0.0;
    _notify();
  }

  Future<void> clearLogs() async {
    await _databaseHelper.clearLogs();
    logs = [];
    currentAttackStatus = null;
    activeFilePath = null;
    activeServerLogSourceId = null;
    _remoteLogOffset = 0;
    hasMoreRemoteLogs = false;
    _invalidateFilterCache();
    _visibleLogCount = _pageSize;
    _notify();
  }

  Future<void> uploadLogs() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'log', 'csv'],
    );
    final selectedPath = result?.files.single.path;
    if (selectedPath == null) return;
    await openLogFile(selectedPath);
  }

  Future<String?> openLogFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return 'File not found: $filePath';

    isLoading = true;
    _notify();

    try {
      final bytes = await file.readAsBytes();
      final logData = utf8.decode(bytes, allowMalformed: true);
      final parsedLogs = parseLogs(logData);
      final savedLogs = await _databaseHelper.replaceAllLogs(parsedLogs);
      
      await _databaseHelper.upsertRecentFile(
        RecentFileEntry(
          path: filePath,
          fileName: path.basename(filePath),
          lastOpened: DateTime.now().toIso8601String(),
          logCount: savedLogs.length,
        ),
      );

      if (_disposed) return null;

      logs = savedLogs.length > _maxLogsCount ? savedLogs.sublist(0, _maxLogsCount) : savedLogs;
      currentAttackStatus = LogAnalysisService.overview(logs);
      activeFilePath = filePath;
      activeServerLogSourceId = null;
      _remoteLogOffset = 0;
      hasMoreRemoteLogs = false;
      isLoadingMoreRemoteLogs = false;
      _invalidateFilterCache();
      _visibleLogCount = _pageSize;

      final updatedRecentFiles = await _databaseHelper.getRecentFiles();
      if (!_disposed) {
        recentFiles = updatedRecentFiles;
        _notify();
      }

      unawaited(_enrichCountriesInBackground(savedLogs));
      return null;
    } catch (error) {
      return 'Unable to load logs: $error';
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  Future<String?> loadServerLogSource(ServerLogSource source) async {
    isLoading = true;
    _isOperationCancelled = false;
    logs = [];
    _notify();

    try {
      loadingProgress = 0.0;
      loadingStatusMessage = 'Fetching ${source.label}...';
      _notify();

      final tempLogs = <FirewallLog>[];
      final remoteLogs = await _remoteLogHistoryService.fetchRecentLogs(
        source: source.id,
        limit: _pageSize,
        offset: 0,
        onProgress: (log, progress) {
          if (_isOperationCancelled) return;
          if (log != null) {
            tempLogs.add(log);
            logs = List.from(tempLogs);
            _notify();
          }
          loadingProgress = progress;
          _notify();
        },
      );
      final savedLogs = await _databaseHelper.replaceAllLogs(remoteLogs);

      if (_disposed) return null;

      logs = savedLogs;
      currentAttackStatus = LogAnalysisService.overview(savedLogs);
      activeFilePath = source.virtualPath;
      activeServerLogSourceId = source.id;
      _remoteLogOffset = remoteLogs.length;
      hasMoreRemoteLogs = remoteLogs.length == _pageSize;
      isLoadingMoreRemoteLogs = false;
      loadingProgress = 1.0;
      loadingStatusMessage = '${source.label} loaded successfully';
      _invalidateFilterCache();
      _visibleLogCount = _pageSize;
      _notify();

      Future.delayed(const Duration(seconds: 2), () {
        if (!_disposed) {
          loadingStatusMessage = null;
          loadingProgress = 0.0;
          _notify();
        }
      });

      if (savedLogs.isNotEmpty) {
        unawaited(_enrichCountriesInBackground(savedLogs));
      }
      return null;
    } catch (error) {
      return 'Unable to load ${source.label}: $error';
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  Future<void> loadMoreServerLogs() async {
    final sourceId = activeServerLogSourceId;
    if (sourceId == null || isLoadingMoreRemoteLogs || !hasMoreRemoteLogs) return;

    final sourceLabel = currentSourceLabel;
    isLoadingMoreRemoteLogs = true;
    _notify();

    loadingProgress = 0.0;
    loadingStatusMessage = 'Fetching more $sourceLabel...';
    _notify();

    try {
      final remoteLogs = await _remoteLogHistoryService.fetchRecentLogs(
        source: sourceId,
        limit: _pageSize,
        offset: _remoteLogOffset,
        onProgress: (log, progress) {
          if (log != null) {
            logs = [...logs, log];
            _notify();
          }
          loadingProgress = progress;
          _notify();
        },
      );
      await _databaseHelper.replaceAllLogs(logs);

      if (_disposed) return;

      currentAttackStatus = LogAnalysisService.overview(logs);
      _remoteLogOffset += remoteLogs.length;
      hasMoreRemoteLogs = remoteLogs.length == _pageSize;
      isLoadingMoreRemoteLogs = false;
      loadingProgress = 1.0;
      loadingStatusMessage = 'Loaded more $sourceLabel';
      _invalidateFilterCache();
      _notify();

      Future.delayed(const Duration(seconds: 2), () {
        if (!_disposed) {
          loadingStatusMessage = null;
          loadingProgress = 0.0;
          _notify();
        }
      });

      if (remoteLogs.isNotEmpty) {
        unawaited(_enrichCountriesInBackground(remoteLogs));
      }
    } catch (error) {
      if (!_disposed) {
        isLoadingMoreRemoteLogs = false;
        _notify();
      }
      rethrow;
    }
  }

  Future<void> _enrichCountriesInBackground(List<FirewallLog> sourceLogs) async {
    if (isEnriching || sourceLogs.isEmpty) return;
    isEnriching = true;
    _notify();

    try {
      final enrichedLogs = await _geoIpService.enrichLogs(sourceLogs);
      final enrichedCountryById = <int, String>{};

      for (final log in enrichedLogs) {
        if (log.id == null || !_shouldReplaceCountry('', log.country)) continue;
        enrichedCountryById[log.id!] = log.country;
      }

      if (enrichedCountryById.isEmpty) return;

      final latestLogs = await _databaseHelper.getLogs();
      final updates = <FirewallLog>[];
      
      for (final log in latestLogs) {
        final updatedCountry = log.id == null ? null : enrichedCountryById[log.id!];
        if (updatedCountry == null || !_shouldReplaceCountry(log.country, updatedCountry)) continue;
        updates.add(log.copyWith(country: updatedCountry));
      }

      if (updates.isNotEmpty) {
        await _databaseHelper.upsertLogsBatch(updates);
        await refreshData();
      }
    } finally {
      if (!_disposed) {
        isEnriching = false;
        _notify();
      }
    }
  }

  bool _shouldReplaceCountry(String currentCountry, String nextCountry) {
    final current = currentCountry.trim().toLowerCase();
    final next = nextCountry.trim();
    if (next.isEmpty || next.toLowerCase() == 'unknown') return false;
    return current.isEmpty || current == 'unknown';
  }

  Future<void> removeLog(int id) async {
    await _databaseHelper.deleteLog(id);
    await refreshData();
  }

  Future<void> updateLog(FirewallLog updatedLog) async {
    await _databaseHelper.updateLog(updatedLog);
    await refreshData();
    if (updatedLog.country.trim().isEmpty || updatedLog.country.trim().toLowerCase() == 'unknown') {
      unawaited(_enrichCountriesInBackground([updatedLog]));
    }
  }

  Future<void> deleteRecentFile(String filePath) async {
    await _databaseHelper.deleteRecentFile(filePath);
    await refreshData();
  }

  Future<ExportResult?> exportLogs({required bool asPdf}) async {
    final logsToExport = filteredLogs;
    if (logsToExport.isEmpty) return null;

    isLoading = true;
    _notify();

    try {
      return asPdf ? await _exportService.exportPdf(logsToExport) : await _exportService.exportCsv(logsToExport);
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  String get currentSourceLabel {
    if (activeServerLogSourceId != null) {
      for (final source in serverLogSources) {
        if (source.id == activeServerLogSourceId) return source.label;
      }
    }
    final activePath = activeFilePath?.trim() ?? '';
    if (activePath.isNotEmpty) return path.basename(activePath);
    return 'Logs';
  }

  bool _matchesLogViewFilter(FirewallLog log) {
    switch (logViewFilter) {
      case 'Firewall logs': return _categorizeLog(log) == 'firewall';
      case 'System logs': return _categorizeLog(log) == 'system';
      case 'Auth logs': return _categorizeLog(log) == 'auth';
      case 'Error logs': return _categorizeLog(log) == 'error';
      case 'Main logs': return _categorizeLog(log) == 'main';
      case 'High threats only':
        final risk = LogAnalysisService.analyze(log).riskLevel;
        return risk == 'Critical' || risk == 'High';
      default: return true;
    }
  }

  String _categorizeLog(FirewallLog log) {
    final content = [log.method, log.requestMethod, log.request, log.status, log.url, log.userAgent, log.parameters].join(' ').toLowerCase();
    if (_containsAny(content, const ['firewall', 'ufw', 'iptables', 'nft', 'nginx', 'apache', 'http', 'tcp', 'udp', 'packet', 'access.log'])) return 'firewall';
    if (_containsAny(content, const ['auth', 'authentication', 'failed password', 'accepted password', 'sudo', 'pam_', 'sshd', 'login', 'session opened', 'session closed', 'su:'])) return 'auth';
    if (_containsAny(content, const ['error', 'failed', 'exception', 'fatal', 'critical', 'warning', 'denied', 'refused', 'traceback'])) return 'error';
    final fileCategory = _categorizeFilePath(activeFilePath);
    if (fileCategory != null) return fileCategory;
    return 'main';
  }

  String? _categorizeFilePath(String? filePath) {
    if (filePath == null || filePath.trim().isEmpty) return null;
    final normalizedPath = filePath.toLowerCase();
    final fileName = path.basename(normalizedPath);
    if (_containsAny(fileName, const ['auth.log', 'secure', 'faillog'])) return 'auth';
    if (_containsAny(fileName, const ['error', 'err.log'])) return 'error';
    if (_containsAny(normalizedPath, const ['firewall', 'ufw', 'iptables', 'access.log', 'nginx', 'apache'])) return 'firewall';
    if (_containsAny(fileName, const ['syslog', 'messages', 'kern.log', 'kernel.log', 'daemon.log', 'journal', 'history.log', 'alternatives.log'])) return 'system';
    if (_containsAny(fileName, const ['main.log', 'app.log', 'application'])) return 'main';
    return null;
  }

  bool _containsAny(String value, List<String> candidates) {
    for (final candidate in candidates) {
      if (value.contains(candidate)) return true;
    }
    return false;
  }
}

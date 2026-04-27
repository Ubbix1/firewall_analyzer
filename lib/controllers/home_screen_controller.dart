import 'dart:async';
import 'package:flutter/material.dart';

import '../models/firewall_log.dart';
import '../models/recent_file_entry.dart';
import '../models/saved_suspicious_log_entry.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/geo_ip_service.dart';
import '../services/log_analysis_service.dart';
import '../constants/server_log_sources.dart';
import 'logs_controller.dart';
import 'saved_logs_controller.dart';
import 'server_status_controller.dart';

class HomeScreenController extends ChangeNotifier {
  final LogsController logsController;
  final SavedLogsController savedLogsController;
  final ServerStatusController serverStatusController;

  static const logViewOptions = LogsController.logViewOptions;

  bool _isInitialized = false;
  bool _disposed = false;

  HomeScreenController({
    DatabaseHelper? databaseHelper,
    GeoIpService? geoIpService,
    ExportService? exportService,
    required this.serverStatusController,
    bool skipInitialLoad = false,
  })  : logsController = LogsController(
          databaseHelper: databaseHelper,
          geoIpService: geoIpService,
          exportService: exportService,
        ),
        savedLogsController = SavedLogsController(
          databaseHelper: databaseHelper,
        ) {
    logsController.addListener(_notify);
    savedLogsController.addListener(_notify);
    serverStatusController.addListener(_notify);
  }

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await logsController.refreshData();
    await savedLogsController.refreshData();
  }

  @override
  void dispose() {
    _disposed = true;
    logsController.removeListener(_notify);
    savedLogsController.removeListener(_notify);
    serverStatusController.removeListener(_notify);
    logsController.dispose();
    savedLogsController.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Proxied Properties (for UI compatibility) ──────────────────────────────
  List<FirewallLog> get logs => logsController.logs;
  List<RecentFileEntry> get recentFiles => logsController.recentFiles;
  List<SavedSuspiciousLogEntry> get savedSuspiciousLogs => savedLogsController.savedSuspiciousLogs;
  String? get currentAttackStatus => logsController.currentAttackStatus;
  String? get activeFilePath => logsController.activeFilePath;
  String? get activeServerLogSourceId => logsController.activeServerLogSourceId;

  bool get isLoading => logsController.isLoading;
  bool get isEnriching => logsController.isEnriching;
  bool get isLoadingMoreRemoteLogs => logsController.isLoadingMoreRemoteLogs;
  bool get hasMoreRemoteLogs => logsController.hasMoreRemoteLogs;
  double get loadingProgress => logsController.loadingProgress;
  String? get loadingStatusMessage => logsController.loadingStatusMessage;
  
  bool get isMemoryCritical => serverStatusController.isMemoryCritical;
  String? get serverMemoryWarning => serverStatusController.serverMemoryWarning;

  TextEditingController get searchController => logsController.searchController;
  bool isSearching = false;
  void toggleSearch() {
    isSearching = !isSearching;
    if (!isSearching) logsController.searchController.clear();
    _notify();
  }

  List<FirewallLog> get filteredLogs => logsController.filteredLogs;
  List<FirewallLog> get visibleLogs => logsController.visibleLogs;
  bool get hasMoreLogs => logsController.hasMoreLogs;

  String get sortBy => logsController.sortBy;
  bool get ascending => logsController.ascending;
  String? get statusFilter => logsController.statusFilter;
  String get logViewFilter => logsController.logViewFilter;

  // ── Proxied Methods ────────────────────────────────────────────────────────
  void loadMoreLocalLogs() => logsController.loadMoreLocalLogs();
  void setStatusFilter(String? v) => logsController.setStatusFilter(v);
  void setSortBy(String v) => logsController.setSortBy(v);
  void setAscending(bool v) => logsController.setAscending(v);
  void setLogViewFilter(String v) => logsController.setLogViewFilter(v);
  
  Future<void> uploadLogs() => logsController.uploadLogs();
  Future<String?> openLogFile(String p) => logsController.openLogFile(p);
  Future<String?> loadServerLogSource(ServerLogSource s) => logsController.loadServerLogSource(s);
  Future<void> loadMoreServerLogs() => logsController.loadMoreServerLogs();
  
  Future<void> removeLog(int id) => logsController.removeLog(id);
  Future<void> updateLog(FirewallLog l) => logsController.updateLog(l);
  Future<void> deleteRecentFile(String p) => logsController.deleteRecentFile(p);
  Future<ExportResult?> exportLogs({required bool asPdf}) => logsController.exportLogs(asPdf: asPdf);

  // ── Saved Logs Logic ───────────────────────────────────────────────────────
  Future<void> saveSuspiciousLog(FirewallLog log) async {
    await savedLogsController.saveSuspiciousLog(log, logsController.currentSourceLabel);
  }

  Future<void> removeSavedSuspiciousLog(String sig) => savedLogsController.removeSavedSuspiciousLog(sig);
  bool isSuspiciousSaved(FirewallLog log) => savedLogsController.isSuspiciousSaved(log);
  Future<void> copySuspiciousLog(SavedSuspiciousLogEntry entry) => savedLogsController.copySuspiciousLog(entry);

  void loadSavedSuspiciousLogIntoLogs(SavedSuspiciousLogEntry entry) {
    logsController.logs = [entry.log];
    logsController.currentAttackStatus = LogAnalysisService.overview(logsController.logs);
    logsController.activeFilePath = entry.sourceLabel;
    logsController.activeServerLogSourceId = null;
    logsController.refreshData(); // Triggers re-cache and UI update
  }

  void stopLoading() => logsController.stopLoading();
  Future<void> clearLogs() => logsController.clearLogs();

  String get currentSourceLabel => logsController.currentSourceLabel;
}

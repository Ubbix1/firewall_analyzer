import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/firewall_log.dart';
import '../models/saved_suspicious_log_entry.dart';
import '../services/database_helper.dart';
import '../services/log_analysis_service.dart';

class SavedLogsController extends ChangeNotifier {
  final DatabaseHelper _databaseHelper;
  List<SavedSuspiciousLogEntry> savedSuspiciousLogs = [];
  bool _disposed = false;

  SavedLogsController({DatabaseHelper? databaseHelper})
      : _databaseHelper = databaseHelper ?? DatabaseHelper();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshData() async {
    final storedSuspiciousLogs = await _databaseHelper.getSavedSuspiciousLogs();
    if (_disposed) return;
    savedSuspiciousLogs = storedSuspiciousLogs;
    _notify();
  }

  Future<void> saveSuspiciousLog(FirewallLog log, String sourceLabel) async {
    final analysis = LogAnalysisService.analyze(log);
    if (!analysis.isSuspicious) return;

    final entry = SavedSuspiciousLogEntry(
      signature: _signatureForLog(log),
      sourceLabel: sourceLabel,
      savedAt: DateTime.now().toIso8601String(),
      riskLevel: analysis.riskLevel,
      log: log,
    );

    await _databaseHelper.upsertSavedSuspiciousLog(entry);
    await refreshData();
  }

  Future<void> removeSavedSuspiciousLog(String signature) async {
    await _databaseHelper.deleteSavedSuspiciousLog(signature);
    await refreshData();
  }

  bool isSuspiciousSaved(FirewallLog log) {
    final signature = _signatureForLog(log);
    return savedSuspiciousLogs.any((e) => e.signature == signature);
  }

  Future<void> copySuspiciousLog(SavedSuspiciousLogEntry entry) async {
    final analysis = LogAnalysisService.analyze(entry.log);
    final text = [
      'SUSPICIOUS LOG ENTRY',
      'Source: ${entry.sourceLabel}',
      'Saved At: ${entry.savedAt}',
      'IP Address: ${entry.log.ipAddress}',
      'Timestamp: ${entry.log.timestamp}',
      'Risk Level: ${entry.riskLevel} (${analysis.severityScore})',
      'Findings: ${analysis.findings.join(", ")}',
      'Request: ${entry.log.method} ${entry.log.url}',
      'Response: ${entry.log.responseCode} (${entry.log.responseSize} bytes)',
      'User Agent: ${entry.log.userAgent}',
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: text));
  }

  String _signatureForLog(FirewallLog log) {
    return [
      log.timestamp,
      log.ipAddress,
      log.method,
      log.url,
      log.request,
      log.responseCode.toString(),
      log.responseSize.toString(),
    ].join('|');
  }
}

import 'package:flutter/material.dart';

import '../controllers/home_screen_controller.dart';
import '../services/log_analysis_service.dart';

/// Shows the summary dashboard as a modal dialog.
void showDashboardDialog(
    BuildContext context, HomeScreenController ctrl) {
  final logs = ctrl.logs;
  final totalLogs = logs.length;
  final suspiciousLogs = logs.where(LogAnalysisService.isSuspicious).toList();
  final ipCounts = <String, int>{};
  final statusCounts = <String, int>{};
  final riskCounts = <String, int>{};

  // Analyze once and reuse — memoization in LogAnalysisService makes this free.
  int totalScore = 0;
  for (final log in logs) {
    final analysis = LogAnalysisService.analyze(log);
    totalScore += analysis.severityScore;
    ipCounts[log.ipAddress] = (ipCounts[log.ipAddress] ?? 0) + 1;
    statusCounts[log.responseCode.toString()] =
        (statusCounts[log.responseCode.toString()] ?? 0) + 1;
    riskCounts[analysis.riskLevel] =
        (riskCounts[analysis.riskLevel] ?? 0) + 1;
  }

  final avgSeverity =
      totalLogs == 0 ? '0' : (totalScore / totalLogs).toStringAsFixed(1);

  final topIps = ipCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topStatuses = statusCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final riskBreakdown = riskCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Summary Dashboard'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatCard('Total Logs', totalLogs.toString()),
              _buildStatCard(
                  'Suspicious Logs', suspiciousLogs.length.toString()),
              _buildStatCard('Average Severity', avgSeverity),
              const SizedBox(height: 16),
              const Text('Top IPs',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...topIps
                  .take(5)
                  .map((e) => Text('${e.key}: ${e.value} requests')),
              const SizedBox(height: 16),
              const Text('Top Status Codes',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...topStatuses
                  .take(5)
                  .map((e) => Text('${e.key}: ${e.value} entries')),
              const SizedBox(height: 16),
              const Text('Risk Breakdown',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...riskBreakdown.map((e) => Text('${e.key}: ${e.value} logs')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _buildStatCard(String label, String value) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
    ),
  );
}

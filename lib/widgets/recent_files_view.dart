import 'package:flutter/material.dart';

import '../controllers/home_screen_controller.dart';
import '../models/saved_suspicious_log_entry.dart';
import '../screens/log_analysis_screen.dart';
import '../services/format_utils.dart';
import '../services/log_analysis_service.dart';

/// The "Saved" tab — shows saved suspicious logs and legacy recent files.
class RecentFilesView extends StatelessWidget {
  final HomeScreenController controller;
  final void Function(SavedSuspiciousLogEntry) onLoadIntoLogs;

  const RecentFilesView({
    super.key,
    required this.controller,
    required this.onLoadIntoLogs,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ctrl = controller;

        if (ctrl.savedSuspiciousLogs.isEmpty && ctrl.recentFiles.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Nothing saved yet.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Save suspicious logs from the Logs tab to keep them here for investigation. '
                    'Legacy recent files will appear after you open log files.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (ctrl.savedSuspiciousLogs.isNotEmpty) ...[
              Text(
                'Suspicious Activity',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...ctrl.savedSuspiciousLogs.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          entry.riskLevel.isEmpty ? '!' : entry.riskLevel[0],
                        ),
                      ),
                      title: Text(
                          '${entry.log.ipAddress} • ${entry.riskLevel}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.sourceLabel} • Saved ${formatDateTime(entry.savedAt)}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            () {
                              final findings = LogAnalysisService.analyze(
                                      entry.log)
                                  .findings;
                              return findings.isNotEmpty
                                  ? findings.first
                                  : 'Saved suspicious event for later review.';
                            }(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.log.request.isNotEmpty
                                ? entry.log.request
                                : entry.log.url,
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Open analysis',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    LogAnalysisScreen(log: entry.log),
                              ),
                            ),
                            icon: const Icon(Icons.open_in_new),
                          ),
                          IconButton(
                            tooltip: 'Show in logs',
                            onPressed: () => onLoadIntoLogs(entry),
                            icon: const Icon(Icons.visibility_outlined),
                          ),
                          IconButton(
                            tooltip: 'Copy saved log',
                            onPressed: () async {
                              await ctrl.copySuspiciousLog(entry);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Saved suspicious log copied to clipboard.'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_all),
                          ),
                          IconButton(
                            tooltip: 'Remove saved suspicious log',
                            onPressed: () async => ctrl
                                .removeSavedSuspiciousLog(entry.signature),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (ctrl.recentFiles.isNotEmpty) ...[
              Text(
                'Legacy Recent Files',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...ctrl.recentFiles.map(
                (recentFile) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(recentFile.logCount.toString()),
                      ),
                      title: Text(recentFile.fileName),
                      subtitle: Text(
                        'Last opened: ${formatDateTime(recentFile.lastOpened)}\n${recentFile.path}',
                      ),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Re-open file',
                            onPressed: () async {
                              final err =
                                  await ctrl.openLogFile(recentFile.path);
                              if (err != null && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(err)),
                                );
                              }
                            },
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            tooltip: 'Remove from history',
                            onPressed: () async {
                              await ctrl.deleteRecentFile(recentFile.path);
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

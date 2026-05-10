import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/firewall_log.dart';
import '../screens/log_analysis_screen.dart';
import '../services/log_analysis_service.dart';

class LogEntryTile extends StatelessWidget {
  final FirewallLog log;
  final VoidCallback onDelete;
  final VoidCallback onAnalyze;
  final VoidCallback? onSaveSuspicious;
  final bool isSuspiciousSaved;
  final VoidCallback? onLongPress;

  const LogEntryTile({
    super.key,
    required this.log,
    required this.onDelete,
    required this.onAnalyze,
    this.onSaveSuspicious,
    this.isSuspiciousSaved = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final analysis = LogAnalysisService.analyze(log);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color riskColor;
    switch (analysis.riskLevel) {
      case 'Critical':
        riskColor = Colors.redAccent;
        break;
      case 'High':
        riskColor = Colors.orangeAccent;
        break;
      case 'Medium':
        riskColor = Colors.amber;
        break;
      case 'Low':
        riskColor = Colors.blueAccent;
        break;
      default:
        riskColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceVariant.withOpacity(0.3) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: riskColor.withOpacity(0.15),
          width: 0.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Risk level indicator bar
              Container(
                width: 4,
                color: riskColor,
              ),
              Expanded(
                child: InkWell(
                  onLongPress: onLongPress,
                  onTap: onAnalyze,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                log.ipAddress,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                            Text(
                              _formatTimestamp(log.timestamp),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            _buildBadge(
                              context,
                              log.method.toUpperCase(),
                              isDark ? colorScheme.primaryContainer.withOpacity(0.5) : colorScheme.primary.withOpacity(0.05),
                              isDark ? colorScheme.onPrimaryContainer : colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            _buildBadge(
                              context,
                              analysis.riskLevel.toUpperCase(),
                              riskColor.withOpacity(0.1),
                              riskColor,
                            ),
                            if (analysis.isBackendScored) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified, size: 14, color: Colors.blue),
                            ],
                            const Spacer(),
                            _buildInfoItem(context, Icons.code, '${log.responseCode}'),
                            const SizedBox(width: 8),
                            _buildInfoItem(context, Icons.data_usage, '${log.responseSize}B'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onAnalyze,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant),
                tooltip: 'Analyze',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context, String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  String _formatTimestamp(String ts) {
    if (ts.isEmpty) return 'Unknown Time';
    try {
      final parsed = DateTime.parse(ts);
      return DateFormat.jms().format(parsed);
    } catch (_) {
      // fallback for non-ISO formats (like traditional syslog "Apr 24 15:20:01")
      return ts;
    }
  }
}

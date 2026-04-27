import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/firewall_log.dart';
import '../models/log_diff.dart';
import '../services/export_service.dart';
import '../services/log_diff_service.dart';

class LogComparisonScreen extends StatefulWidget {
  final List<FirewallLog> logsA;
  final List<FirewallLog> logsB;
  final String fileNameA;
  final String fileNameB;
  final ExportService? exportService;

  const LogComparisonScreen({
    super.key,
    required this.logsA,
    required this.logsB,
    required this.fileNameA,
    required this.fileNameB,
    this.exportService,
  });

  @override
  State<LogComparisonScreen> createState() => _LogComparisonScreenState();
}

class _LogComparisonScreenState extends State<LogComparisonScreen> {
  late final LogDiffService _diffService;
  late final ExportService _exportService;
  late LogDiff _diff;
  late ComparisonSummary _summary;

  @override
  void initState() {
    super.initState();
    _diffService = LogDiffService();
    _exportService = widget.exportService ?? ExportService();
    _generateDiff();
  }

  void _generateDiff() {
    _diff = _diffService.compareLogs(
      widget.logsA,
      widget.logsB,
      widget.fileNameA,
      widget.fileNameB,
    );
    _summary = _diffService.generateSummary(_diff);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Comparison'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export Report',
            onPressed: _showExportOptions,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildSummaryCard(),
            _buildFileComparisonCard(),
            _buildStatisticsCard(),
            if (_diff.newIPs.isNotEmpty) _buildNewIPsSection(),
            if (_diff.removedIPs.isNotEmpty) _buildRemovedIPsSection(),
            if (_diff.escalated.isNotEmpty) _buildEscalatedSection(),
            if (_diff.resolved.isNotEmpty) _buildResolvedSection(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.blue.shade100],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Comparison Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSummaryMetric(
                  'New Threats',
                  _summary.newThreats.toString(),
                  Colors.red,
                ),
                _buildSummaryMetric(
                  'Resolved',
                  _summary.resolved.toString(),
                  Colors.green,
                ),
                _buildSummaryMetric(
                  'Escalated',
                  _summary.escalated.toString(),
                  Colors.deepOrange,
                ),
                _buildSummaryMetric(
                  'De-escalated',
                  _summary.deescalated.toString(),
                  Colors.blue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildFileComparisonCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compared Files',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Original File',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(widget.fileNameA, style: TextStyle(fontSize: 12)),
                      Text('${widget.logsA.length} entries',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: Colors.grey.shade400),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Updated File',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(widget.fileNameB, style: TextStyle(fontSize: 12)),
                      Text('${widget.logsB.length} entries',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard() {
    final ipsA = widget.logsA.map((l) => l.ipAddress).toSet();
    final ipsB = widget.logsB.map((l) => l.ipAddress).toSet();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Statistics',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildStatRow('Unique IPs (Original)', ipsA.length.toString()),
            _buildStatRow('Unique IPs (Updated)', ipsB.length.toString()),
            _buildStatRow('New IPs', _diff.newIPs.length.toString()),
            _buildStatRow('Removed IPs', _diff.removedIPs.length.toString()),
            _buildStatRow(
              'Common IPs',
              (ipsA.length + ipsB.length - _diff.newIPs.length - _diff.removedIPs.length)
                  .toString(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildNewIPsSection() {
    return _buildIPSection(
      'New IPs Found',
      _diff.newIPs,
      Colors.red,
      Icons.new_releases,
    );
  }

  Widget _buildRemovedIPsSection() {
    return _buildIPSection(
      'IPs No Longer Present',
      _diff.removedIPs,
      Colors.green,
      Icons.check_circle,
    );
  }

  Widget _buildIPSection(
    String title,
    List<DiffIP> ips,
    Color color,
    IconData icon,
  ) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  '$title (${ips.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ips.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final ip = ips[index];
                return ListTile(
                  title: Text(ip.ipAddress),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Country: ${ip.country}',
                          style: const TextStyle(fontSize: 12)),
                      Text('Requests: ${ip.requestCount}',
                          style: const TextStyle(fontSize: 12)),
                      if (ip.statusCodes.isNotEmpty)
                        Text('Status Codes: ${ip.statusCodes.join(", ")}',
                            style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEscalatedSection() {
    return _buildChangeSection(
      'Escalated Threats',
      _diff.escalated,
      Colors.deepOrange,
      Icons.trending_up,
    );
  }

  Widget _buildResolvedSection() {
    return _buildChangeSection(
      'De-escalated Threats',
      _diff.resolved,
      Colors.blue,
      Icons.trending_down,
    );
  }

  Widget _buildChangeSection(
    String title,
    List<IPChangeInfo> changes,
    Color color,
    IconData icon,
  ) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  '$title (${changes.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: changes.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final change = changes[index];
                return ListTile(
                  title: Text(change.ipAddress),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Country: ${change.country}',
                          style: const TextStyle(fontSize: 12)),
                      Row(
                        children: [
                          Text(
                            '${change.previousCount} → ${change.currentCount}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: change.changePercent > 0
                                  ? Colors.red.shade100
                                  : Colors.green.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${change.changePercent > 0 ? "+" : ""}${change.changePercent}%',
                              style: TextStyle(
                                fontSize: 11,
                                color: change.changePercent > 0
                                    ? Colors.red
                                    : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Export as CSV'),
              onTap: () {
                Navigator.pop(context);
                _exportReport(false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Export as PDF'),
              onTap: () {
                Navigator.pop(context);
                _exportReport(true);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _exportReport(bool asPdf) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exporting comparison report as ${asPdf ? "PDF" : "CSV"}...'),
      ),
    );

    // TODO: Implement actual export functionality
    // This would use the ExportService to generate CSV or PDF
    // For now, just show a message
  }
}

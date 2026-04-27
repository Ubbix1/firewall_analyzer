import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/firewall_log.dart';
import '../services/log_analysis_service.dart';

class LogAnalysisScreen extends StatelessWidget {
  final FirewallLog log;

  const LogAnalysisScreen({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final analysis = LogAnalysisService.analyze(log);

    return Scaffold(
      appBar: AppBar(title: const Text('Log Analysis')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text('IP Address: ${log.ipAddress}',
                style: const TextStyle(fontSize: 18)),
            Text('Timestamp: ${_formatTimestamp(log.timestamp)}',
                style: const TextStyle(fontSize: 18)),
            Text('Method: ${log.method}', style: const TextStyle(fontSize: 18)),
            Text('Request Method: ${log.requestMethod}',
                style: const TextStyle(fontSize: 18)),
            Text('Request: ${log.request}',
                style: const TextStyle(fontSize: 18)),
            Text('Status: ${log.status}', style: const TextStyle(fontSize: 18)),
            Text('Bytes: ${log.bytes}', style: const TextStyle(fontSize: 18)),
            Text('User Agent: ${log.userAgent}',
                style: const TextStyle(fontSize: 18)),
            Text('Parameters: ${log.parameters}',
                style: const TextStyle(fontSize: 18)),
            Text('URL: ${log.url}', style: const TextStyle(fontSize: 18)),
            Text('Response Code: ${log.responseCode}',
                style: const TextStyle(fontSize: 18)),
            Text('Response Size: ${log.responseSize}',
                style: const TextStyle(fontSize: 18)),
            Text('Country: ${log.country}',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            Text(
              'Risk Level: ${analysis.riskLevel}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              'Severity Score: ${analysis.severityScore}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            const Text(
              'Analysis:',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (analysis.findings.isEmpty)
              const Text('No significant issues detected.',
                  style: TextStyle(fontSize: 16))
            else
              ...analysis.findings.map(
                (finding) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child:
                      Text('- $finding', style: const TextStyle(fontSize: 16)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(String ts) {
    if (ts.isEmpty) return 'Unknown Time';
    try {
      final parsed = DateTime.parse(ts);
      return DateFormat.jms().format(parsed);
    } catch (_) {
      return ts;
    }
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/live_packet_record.dart';
import '../services/log_analysis_service.dart';

class LivePacketDetailDialog extends StatelessWidget {
  final LivePacketRecord packet;

  const LivePacketDetailDialog({super.key, required this.packet});

  @override
  Widget build(BuildContext context) {
    final analysis = LogAnalysisService.analyze(packet.log);
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Live Packet Details'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow(context, 'Timestamp', DateFormat.jms().format(packet.receivedAt)),
              _buildInfoRow(context, 'IP Address', packet.log.ipAddress),
              _buildInfoRow(context, 'Risk Level', '${analysis.riskLevel} (${analysis.severityScore})'),
              const Divider(height: 24),
              const Text(
                'Raw Packet Content',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  packet.rawPacket,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Analysis Findings',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (analysis.findings.isEmpty)
                const Text('No suspicious patterns detected.')
              else
                ...analysis.findings.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f)),
                        ],
                      ),
                    )),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text(value),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/firewall_log.dart';

class RecentLogs extends StatelessWidget {
  final Map<String, List<FirewallLog>> recentLogs;
  final Function(String alias) onAliasTap;

  const RecentLogs({
    super.key,
    required this.recentLogs,
    required this.onAliasTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: recentLogs.keys.length,
      itemBuilder: (context, index) {
        String alias = recentLogs.keys.elementAt(index);
        return ExpansionTile(
          title: Text(alias),
          children: recentLogs[alias]!
              .map((log) => ListTile(
                    title: Text(log.ipAddress),
                    subtitle: Text(_formatTimestamp(log.timestamp)),
                    onTap: () => onAliasTap(alias),
                  ))
              .toList(),
        );
      },
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

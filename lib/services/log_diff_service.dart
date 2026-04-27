import '../models/firewall_log.dart';
import '../models/log_diff.dart';

class LogDiffService {
  /// Compare two sets of logs and generate a diff report
  LogDiff compareLogs(
    List<FirewallLog> logsA,
    List<FirewallLog> logsB,
    String fileNameA,
    String fileNameB,
  ) {
    // Aggregate logs by IP
    final ipStatsA = _aggregateByIP(logsA);
    final ipStatsB = _aggregateByIP(logsB);

    // Find new IPs (in B but not in A)
    final newIPs = <DiffIP>[];
    for (final entry in ipStatsB.entries) {
      if (!ipStatsA.containsKey(entry.key)) {
        newIPs.add(entry.value);
      }
    }

    // Find removed IPs (in A but not in B)
    final removedIPs = <DiffIP>[];
    for (final entry in ipStatsA.entries) {
      if (!ipStatsB.containsKey(entry.key)) {
        removedIPs.add(entry.value);
      }
    }

    // Find escalated IPs (increased request count)
    final escalated = <IPChangeInfo>[];
    for (final entry in ipStatsB.entries) {
      if (ipStatsA.containsKey(entry.key)) {
        final previousCount = ipStatsA[entry.key]!.requestCount;
        final currentCount = entry.value.requestCount;
        if (currentCount > previousCount) {
          escalated.add(
            IPChangeInfo(
              ipAddress: entry.key,
              country: entry.value.country,
              previousCount: previousCount,
              currentCount: currentCount,
            ),
          );
        }
      }
    }

    // Find de-escalated IPs (decreased request count)
    final resolved = <IPChangeInfo>[];
    for (final entry in ipStatsB.entries) {
      if (ipStatsA.containsKey(entry.key)) {
        final previousCount = ipStatsA[entry.key]!.requestCount;
        final currentCount = entry.value.requestCount;
        if (currentCount < previousCount) {
          resolved.add(
            IPChangeInfo(
              ipAddress: entry.key,
              country: entry.value.country,
              previousCount: previousCount,
              currentCount: currentCount,
            ),
          );
        }
      }
    }

    return LogDiff(
      logFileA: fileNameA,
      logFileB: fileNameB,
      newIPs: newIPs,
      removedIPs: removedIPs,
      escalated: escalated,
      resolved: resolved,
    );
  }

  /// Aggregate logs by IP address
  Map<String, DiffIP> _aggregateByIP(List<FirewallLog> logs) {
    final ipStats = <String, Map<String, dynamic>>{};

    for (final log in logs) {
      ipStats.putIfAbsent(log.ipAddress, () => {
        'country': log.country,
        'count': 0,
        'urls': <String>{},
        'statusCodes': <int>{},
      });

      ipStats[log.ipAddress]!['count']++;
      if (log.url.isNotEmpty) {
        (ipStats[log.ipAddress]!['urls'] as Set).add(log.url);
      }
      ipStats[log.ipAddress]!['statusCodes'].add(log.responseCode);
    }

    return ipStats.map((ip, stats) {
      final urls = (stats['urls'] as Set<String>).toList();
      urls.sort((a, b) => b.length.compareTo(
          a.length)); // Sort by length (longer URLs are typically more specific)

      return MapEntry(
        ip,
        DiffIP(
          ipAddress: ip,
          country: stats['country'] as String? ?? '',
          requestCount: stats['count'] as int,
          topUrls: urls.take(5).toList(), // Top 5 URLs
          statusCodes: Set<int>.from(stats['statusCodes'] as List<int>),
        ),
      );
    });
  }

  /// Generate comparison summary
  ComparisonSummary generateSummary(LogDiff diff) {
    return ComparisonSummary(
      newThreats: diff.newIPs.length + diff.escalated.length,
      resolved: diff.removedIPs.length + diff.resolved.length,
      escalated: diff.escalated.length,
      deescalated: diff.resolved.length,
      timeRange: '${diff.generatedAt}',
    );
  }

  /// Get top threatening IPs from diff
  List<DiffIP> getTopThreats(LogDiff diff, {int limit = 10}) {
    final all = [...diff.newIPs, ...diff.escalated.map((e) => DiffIP(
      ipAddress: e.ipAddress,
      country: e.country,
      requestCount: e.currentCount,
      topUrls: [],
      statusCodes: {},
    ))];
    all.sort((a, b) => b.requestCount.compareTo(a.requestCount));
    return all.take(limit).toList();
  }
}

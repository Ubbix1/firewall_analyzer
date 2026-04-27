class LogDiff {
  final String logFileA;
  final String logFileB;
  final List<DiffIP> newIPs;
  final List<DiffIP> removedIPs;
  final List<IPChangeInfo> escalated;
  final List<IPChangeInfo> resolved;
  final DateTime generatedAt;

  LogDiff({
    required this.logFileA,
    required this.logFileB,
    required this.newIPs,
    required this.removedIPs,
    required this.escalated,
    required this.resolved,
    DateTime? generatedAt,
  }) : generatedAt = generatedAt ?? DateTime.now();

  int get totalNewThreats => newIPs.length + escalated.length;
  int get totalResolved => removedIPs.length + resolved.length;
  int get netChange => totalNewThreats - totalResolved;
}

class DiffIP {
  final String ipAddress;
  final String country;
  final int requestCount;
  final List<String> topUrls;
  final Set<int> statusCodes;

  DiffIP({
    required this.ipAddress,
    required this.country,
    required this.requestCount,
    required this.topUrls,
    required this.statusCodes,
  });
}

class IPChangeInfo {
  final String ipAddress;
  final String country;
  final int previousCount;
  final int currentCount;
  final int changePercent;

  IPChangeInfo({
    required this.ipAddress,
    required this.country,
    required this.previousCount,
    required this.currentCount,
  }) : changePercent = previousCount > 0
            ? (((currentCount - previousCount) / previousCount) * 100).toInt()
            : 100;
}

class ComparisonSummary {
  final int newThreats;
  final int resolved;
  final int escalated;
  final int deescalated;
  final String timeRange;

  ComparisonSummary({
    required this.newThreats,
    required this.resolved,
    required this.escalated,
    required this.deescalated,
    required this.timeRange,
  });

  String toFormattedString() {
    return 'New Threats: $newThreats | Resolved: $resolved | '
        'Escalated: $escalated | De-escalated: $deescalated';
  }
}

import '../models/firewall_log.dart';

String _sanitize(String input) {
  if (input.isEmpty) return input;
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;')
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
}

List<FirewallLog> parseLogs(String logData) {
  // the existing parser was written for space-delimited HTTP firewall logs
  // (common in access.log files).  when you feed it an Ubuntu `auth.log` or
  // `syslog` entry the structure is totally different – the split-by-space
  // approach yields too few parts and code that indexes into the resulting
  // list can throw RangeError, which is what you saw.  instead we now try the
  // familiar format first and fall back gracefully to a very loose regex;
  // individual malformed lines are swallowed so the UI never crashes.

  List<FirewallLog> logs = [];
  int idCounter = 1;

  // Track IP request times for anomaly detection (only meaningful for
  // logs containing an IP/timestamp pair).
  Map<String, List<DateTime>> ipRequestTimes = {};
  const int anomalyThreshold = 10; // More than 10 requests per minute = anomaly
  const int timeWindowMinutes = 1;

  final lines = logData.split('\n');
  for (var line in lines) {
    if (line.trim().isEmpty) continue;

    try {
      // first attempt: assume the familiar HTTP-style space-separated record.
      // Field layout: [0]=ip [1]=ts [2]=method [3]=reqMethod [4]=request
      //               [5]=status [6]=bytes [7]=ua [8]=params [9]=url
      //               [10]=responseCode [11]=responseSize [12]=country
      var parts = line.split(' ');
      if (parts.length > 11) {
        String country = parts.length > 12 ? parts[12] : '';

        DateTime? requestTime;
        try {
          String timestampStr = parts[1].replaceAll('[', '').replaceAll(']', '');
          requestTime = DateTime.tryParse(
              timestampStr.replaceAll('/', '-').replaceAll(':', ' '));
        } catch (_) {
          requestTime = null;
        }

        bool isAnomaly = false;
        final ip = parts[0];
        if (requestTime != null && ip.isNotEmpty) {
          ipRequestTimes[ip] ??= [];
          final cutoffTime =
              requestTime.subtract(const Duration(minutes: timeWindowMinutes));
          ipRequestTimes[ip]!.removeWhere((t) => t.isBefore(cutoffTime));
          ipRequestTimes[ip]!.add(requestTime);
          if (ipRequestTimes[ip]!.length > anomalyThreshold) {
            isAnomaly = true;
          }
        }

        logs.add(FirewallLog(
          id: idCounter++,
          ipAddress: _sanitize(parts[0]),
          timestamp: _sanitize(parts[1]),
          method: _sanitize(parts[2]),
          requestMethod: _sanitize(parts[3]),
          request: _sanitize(parts[4]),
          status: _sanitize(parts[5]),
          bytes: _sanitize(parts[6]),
          userAgent: _sanitize(parts[7]),
          parameters: _sanitize(parts[8]),
          url: _sanitize(parts[9]),
          responseCode: int.tryParse(parts[10]) ?? 0,
          responseSize: int.tryParse(parts[11]) ?? 0,
          country: _sanitize(country),
          requestRateAnomaly: isAnomaly,
        ));
        continue; // move to next line
      }

      // second attempt: try to extract timestamp and IP from Ubuntu/syslog format.
      // Example: 2026-04-24T15:20:01.155423+05:30 noodleos CRON[234225]...
      final isoTsMatch = RegExp(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[^\s]*)").firstMatch(line);
      final syslogTsMatch = RegExp(r"^([A-Z][a-z]{2}\s+\d+\s+\d{2}:\d{2}:\d{2})").firstMatch(line);
      final ipMatch = RegExp(r"(\d{1,3}(?:\.\d{1,3}){3})").firstMatch(line);

      if (isoTsMatch != null || syslogTsMatch != null || ipMatch != null) {
        final timestamp = isoTsMatch?.group(1) ?? syslogTsMatch?.group(1) ?? '';
        final ip = ipMatch?.group(1) ?? 'system';
        
        logs.add(FirewallLog(
          id: idCounter++,
          ipAddress: _sanitize(ip),
          timestamp: _sanitize(timestamp),
          method: '',
          requestMethod: '',
          request: _sanitize(line),
          status: '',
          bytes: '',
          userAgent: '',
          parameters: '',
          url: '',
          responseCode: 0,
          responseSize: 0,
          country: '',
          requestRateAnomaly: false,
        ));
        continue;
      }
    } catch (e) {
      // any unexpected issue parsing a single line should not blow up the
      // entire import, so just skip it and continue
      continue;
    }
  }
  return logs;
}


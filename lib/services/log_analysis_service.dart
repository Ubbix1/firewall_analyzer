import '../models/firewall_log.dart';

// ---------------------------------------------------------------------------
// Where the severity decision came from.
// ---------------------------------------------------------------------------
enum AnalysisSource {
  /// The verdict was provided by packet_server.py (authoritative).
  backend,

  /// The verdict was computed locally (client-side fallback for file uploads).
  local,
}

class LogAnalysisResult {
  final List<String> findings;
  final int severityScore;
  final String riskLevel;

  /// Indicates whether the verdict came from the backend or local scoring.
  /// Always prefer displaying backend results when [source] is [AnalysisSource.backend].
  final AnalysisSource source;

  const LogAnalysisResult({
    required this.findings,
    required this.severityScore,
    required this.riskLevel,
    this.source = AnalysisSource.local,
  });

  bool get isSuspicious => findings.isNotEmpty;

  bool get isBackendScored => source == AnalysisSource.backend;
}

class LogAnalysisService {
  // ---------------------------------------------------------------------------
  // Memoization cache — keyed on FirewallLog.id (non-null only).
  // Call clearCache() whenever the log set is replaced wholesale.
  // ---------------------------------------------------------------------------
  static final Map<int, LogAnalysisResult> _cache = {};

  /// Remove all cached results.  Call this after replaceAllLogs / deleteLog.
  static void clearCache() => _cache.clear();

  /// Remove a single entry from the cache when a log is deleted or updated.
  static void evict(int? id) {
    if (id != null) _cache.remove(id);
  }

  // ---------------------------------------------------------------------------
  // analyze() — Backend is the authority.
  //
  // Priority order:
  //   1. backendSeverityScore present → use it directly (most accurate)
  //   2. backendThreatLevel present   → map to score (backward compat)
  //   3. Neither                      → client-side fallback (local files)
  // ---------------------------------------------------------------------------
  static LogAnalysisResult analyze(FirewallLog log) {
    // ── 0. Check Analysis Cache ────────────────────────────────────────────
    // If the log already has a cached score/level, return a result immediately.
    // This is the fastest path for sorting and list rendering.
    if (log.cachedSeverityScore != null && log.cachedRiskLevel != null) {
      return LogAnalysisResult(
        findings: log.backendAlerts ?? const [],
        severityScore: log.cachedSeverityScore!,
        riskLevel: log.cachedRiskLevel!,
        source: log.backendSeverityScore != null || log.backendThreatLevel != null
            ? AnalysisSource.backend
            : AnalysisSource.local,
      );
    }

    // ── 1. Backend provided a numeric score ────────────────────────────────
    final backendScore = log.backendSeverityScore;
    final backendLevel = log.backendThreatLevel?.trim().toLowerCase();
    final backendAlerts = log.backendAlerts ?? const <String>[];

    LogAnalysisResult result;

    if (backendScore != null && backendScore > 0) {
      result = LogAnalysisResult(
        findings: backendAlerts,
        severityScore: backendScore.clamp(0, 100),
        riskLevel: backendLevel != null
            ? _riskLevelFromBackend(backendLevel)
            : _riskLevelFor(backendScore.clamp(0, 100)),
        source: AnalysisSource.backend,
      );
    }
    // ── 2. Backend provided a level string but no numeric score ────────────
    else if (backendLevel != null && backendLevel.isNotEmpty) {
      final mappedScore = _scoreFromThreatLevel(backendLevel);
      result = LogAnalysisResult(
        findings: backendAlerts,
        severityScore: mappedScore,
        riskLevel: _riskLevelFromBackend(backendLevel),
        source: AnalysisSource.backend,
      );
    }
    // ── 3. Local fallback — memoized, for locally-opened files ─────────────
    else {
      final id = log.id;
      if (id != null) {
        final cached = _cache[id];
        if (cached != null) {
          log.cachedSeverityScore = cached.severityScore;
          log.cachedRiskLevel = cached.riskLevel;
          return cached;
        }
      }
      result = _compute(log);
      if (id != null) _cache[id] = result;
    }

    // Populate the cache on the log object for future rapid access
    log.cachedSeverityScore = result.severityScore;
    log.cachedRiskLevel = result.riskLevel;

    return result;
  }

  // ---------------------------------------------------------------------------
  // Helpers for backend-level → Flutter conventions
  // ---------------------------------------------------------------------------

  /// Maps backend threat level string to Flutter's capitalised risk level.
  static String _riskLevelFromBackend(String level) {
    switch (level) {
      case 'critical': return 'Critical';
      case 'high':     return 'High';
      case 'medium':   return 'Medium';
      default:         return 'Low';
    }
  }

  /// Maps backend threat level string → representative numeric score.
  /// Uses a mid-range value within each band to preserve future granularity.
  static int _scoreFromThreatLevel(String level) {
    switch (level) {
      case 'critical': return 90;
      case 'high':     return 68;
      case 'medium':   return 42;
      default:         return 15;
    }
  }

  // ---------------------------------------------------------------------------
  // Client-side computation (used only when no backend data is present)
  // ---------------------------------------------------------------------------

  static bool isSuspicious(FirewallLog log) => analyze(log).isSuspicious;

  static String overview(List<FirewallLog> logs) {
    if (logs.isEmpty) {
      return 'No logs loaded.';
    }

    final suspiciousLogs = logs.where(isSuspicious).length;
    if (suspiciousLogs == 0) {
      return 'No suspicious patterns detected across ${logs.length} logs.';
    }

    return 'Suspicious activity in $suspiciousLogs of ${logs.length} logs.';
  }

  static String detailedSummary(List<FirewallLog> logs) {
    if (logs.isEmpty) {
      return 'No logs to analyze.';
    }

    final buffer = StringBuffer();
    var suspiciousLogs = 0;

    for (final log in logs) {
      final result = analyze(log);
      if (!result.isSuspicious) {
        continue;
      }

      suspiciousLogs++;
      buffer.writeln(
        '${log.ipAddress} [${result.riskLevel} ${result.severityScore}] ${result.findings.join(" ")}',
      );
    }

    if (suspiciousLogs == 0) {
      return 'No suspicious patterns detected.';
    }

    return 'Total suspicious logs: $suspiciousLogs\n\n${buffer.toString().trim()}';
  }

  static LogAnalysisResult _compute(FirewallLog log) {
    final findings = <String>[];
    var score = 0;

    final request = log.request.toLowerCase();
    final url = log.url.toLowerCase();
    final userAgent = log.userAgent.toLowerCase();

    if (log.responseCode == 404) {
      findings.add('Frequent 404 patterns can indicate reconnaissance activity.');
      score += 18;
    }
    if (log.responseCode == 401 || log.responseCode == 403) {
      findings.add('Unauthorized or forbidden access attempts were detected.');
      score += 24;
    }
    if (log.responseCode >= 500) {
      findings.add(
          'Server-side error responses may signal exploit attempts or instability.');
      score += 28;
    }
    if (log.requestRateAnomaly) {
      findings.add('Request-rate anomaly detected for this source IP.');
      score += 30;
    }
    if (userAgent.contains('bot') ||
        userAgent.contains('crawler') ||
        userAgent.contains('sqlmap') ||
        userAgent.contains('scanner')) {
      findings.add(
          'Suspicious automated client signature found in the user agent.');
      score += 14;
    }
    if (request.contains('union select') ||
        request.contains('or 1=1') ||
        request.contains('drop table') ||
        request.contains('information_schema')) {
      findings.add('Possible SQL injection payload detected.');
      score += 40;
    }
    if (request.contains('<script') ||
        request.contains('onerror=') ||
        request.contains('onload=')) {
      findings.add('Possible cross-site scripting payload detected.');
      score += 36;
    }
    if (request.contains('../') ||
        request.contains('..\\') ||
        request.contains('%2e%2e%2f')) {
      findings.add('Directory traversal indicators detected.');
      score += 34;
    }
    if (request.contains(';') ||
        request.contains('&&') ||
        request.contains('|') ||
        request.contains('`')) {
      findings.add('Possible command-injection chaining detected.');
      score += 32;
    }
    if (url.contains('/etc/passwd') || url.contains('.htaccess')) {
      findings.add('Sensitive file access pattern detected.');
      score += 28;
    }
    if (url.contains('malicious') ||
        url.contains('exploit') ||
        url.contains('shell')) {
      findings.add('Known malicious or exploit-oriented path indicator detected.');
      score += 24;
    }

    score = score.clamp(0, 100);
    return LogAnalysisResult(
      findings: findings,
      severityScore: score,
      riskLevel: _riskLevelFor(score),
      source: AnalysisSource.local,
    );
  }

  static String _riskLevelFor(int score) {
    if (score >= 80) {
      return 'Critical';
    }
    if (score >= 55) {
      return 'High';
    }
    if (score >= 30) {
      return 'Medium';
    }
    if (score > 0) {
      return 'Low';
    }
    return 'Informational';
  }
}

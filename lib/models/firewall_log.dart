class FirewallLog {
  int? id;
  String ipAddress;
  String timestamp;
  String method;
  String requestMethod;
  String request;
  String status;
  String bytes;
  String userAgent;
  String parameters;
  String url;
  int responseCode;
  int responseSize;
  String country;
  double? latitude;
  double? longitude;
  bool requestRateAnomaly;
  String source; // e.g. "caddy", "syslog", "auth"

  // ── Backend-authority threat fields ──────────────────────────────────────
  // Populated when the log was received from packet_server.py.
  // When non-null these take precedence over client-side scoring.
  List<String>? backendAlerts;       // e.g. ["SQL Injection Attempt"]
  String?       backendThreatLevel;  // "critical" | "high" | "medium"
  int?          backendSeverityScore; // 0-100, matches Flutter's scale

  // ── Analysis Cache ────────────────────────────────────────────────────────
  // To avoid re-computing analysis during every sort/render (O(n log n)).
  int? cachedSeverityScore;
  String? cachedRiskLevel;

  FirewallLog({
    this.id,
    required this.ipAddress,
    required this.timestamp,
    required this.method,
    required this.requestMethod,
    required this.request,
    required this.status,
    required this.bytes,
    required this.userAgent,
    required this.parameters,
    required this.url,
    required this.responseCode,
    required this.responseSize,
    required this.country,
    this.latitude,
    this.longitude,
    required this.requestRateAnomaly,
    this.source = '',
    this.backendAlerts,
    this.backendThreatLevel,
    this.backendSeverityScore,
    this.cachedSeverityScore,
    this.cachedRiskLevel,
  });

  FirewallLog copyWith({
    int? id,
    String? ipAddress,
    String? timestamp,
    String? method,
    String? requestMethod,
    String? request,
    String? status,
    String? bytes,
    String? userAgent,
    String? parameters,
    String? url,
    int? responseCode,
    int? responseSize,
    String? country,
    double? latitude,
    double? longitude,
    bool? requestRateAnomaly,
    String? source,
    List<String>? backendAlerts,
    String? backendThreatLevel,
    int? backendSeverityScore,
    int? cachedSeverityScore,
    String? cachedRiskLevel,
  }) {
    return FirewallLog(
      id: id ?? this.id,
      ipAddress: ipAddress ?? this.ipAddress,
      timestamp: timestamp ?? this.timestamp,
      method: method ?? this.method,
      requestMethod: requestMethod ?? this.requestMethod,
      request: request ?? this.request,
      status: status ?? this.status,
      bytes: bytes ?? this.bytes,
      userAgent: userAgent ?? this.userAgent,
      parameters: parameters ?? this.parameters,
      url: url ?? this.url,
      responseCode: responseCode ?? this.responseCode,
      responseSize: responseSize ?? this.responseSize,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      requestRateAnomaly: requestRateAnomaly ?? this.requestRateAnomaly,
      source: source ?? this.source,
      backendAlerts: backendAlerts ?? this.backendAlerts,
      backendThreatLevel: backendThreatLevel ?? this.backendThreatLevel,
      backendSeverityScore: backendSeverityScore ?? this.backendSeverityScore,
      // Invalidate cache on copy unless explicitly provided (e.g. during analysis population)
      cachedSeverityScore: cachedSeverityScore,
      cachedRiskLevel: cachedRiskLevel,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ipAddress': ipAddress,
      'timestamp': timestamp,
      'method': method,
      'requestMethod': requestMethod,
      'request': request,
      'status': status,
      'bytes': bytes,
      'userAgent': userAgent,
      'parameters': parameters,
      'url': url,
      'responseCode': responseCode,
      'responseSize': responseSize,
      'country': country,
      'latitude': latitude,
      'longitude': longitude,
      'requestRateAnomaly': requestRateAnomaly ? 1 : 0,
      'source': source,
      // Backend-authority fields — stored as JSON string / plain text / int
      'backendAlerts': backendAlerts?.join('||'),
      'backendThreatLevel': backendThreatLevel,
      'backendSeverityScore': backendSeverityScore,
    };
  }

  static FirewallLog fromMap(Map<String, dynamic> map) {
    return FirewallLog(
      id: _asNullableInt(map['id']),
      ipAddress: _asString(map['ipAddress']),
      timestamp: _asString(map['timestamp']),
      method: _asString(map['method']),
      requestMethod: _asString(map['requestMethod']),
      status: _asString(map['status']),
      bytes: _asString(map['bytes']),
      userAgent: _asString(map['userAgent']),
      parameters: _asString(map['parameters']),
      url: _asString(map['url']),
      responseCode: _asInt(map['responseCode']),
      responseSize: _asInt(map['responseSize']),
      country: _asString(
        map['country'] ?? map['countryName'] ?? map['country_name'],
      ),
      latitude: _asNullableDouble(map['latitude'] ?? map['lat']),
      longitude: _asNullableDouble(
        map['longitude'] ?? map['lon'] ?? map['lng'],
      ),
      request: _asString(map['request']),
      requestRateAnomaly: _asBool(map['requestRateAnomaly']),
      source: _asString(map['source']),
      backendAlerts: _asBackendAlerts(map['backendAlerts']),
      backendThreatLevel: map['backendThreatLevel']?.toString().trim().isNotEmpty == true
          ? map['backendThreatLevel'].toString().trim()
          : null,
      backendSeverityScore: _asNullableInt(map['backendSeverityScore']),
    );
  }

  /// Accepts both a pipe-delimited string (from SQLite) and a List (from JSON).
  static List<String>? _asBackendAlerts(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      final items = value
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return items.isEmpty ? null : items;
    }
    final str = value.toString().trim();
    if (str.isEmpty) return null;
    return str.split('||').where((s) => s.isNotEmpty).toList();
  }

  Map<String, dynamic> toJson() => toMap();

  static FirewallLog fromJson(Map<String, dynamic> json) => fromMap(json);

  static String _asString(dynamic value) => _sanitize(value?.toString() ?? '');

  static String _sanitize(String input) {
    if (input.isEmpty) return input;
    // Strip ANSI escape sequences
    final ansiStripped = input.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
    // Escape HTML
    return ansiStripped
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _asNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString());
  }

  static bool _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is int) {
      return value != 0;
    }
    final normalized = value?.toString().toLowerCase().trim();
    return normalized == 'true' || normalized == '1';
  }

  static double? _asNullableDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}

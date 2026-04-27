import 'dart:convert';

import '../models/firewall_log.dart';
import '../models/live_packet_record.dart';

class LivePacketParser {
  static LivePacketRecord? tryParse({
    required String message,
    required int id,
  }) {
    final payload = _normalizePayload(_parsePayload(message));
    final type = payload['type']?.toString().trim().toLowerCase();
    if ((type?.isNotEmpty ?? false) && type != 'packet' && type != 'log') {
      return null;
    }

    final rawPacket = _firstString(
          payload,
          const ['data', 'packet', 'message', 'raw', 'request'],
        ) ??
        message;
    final receivedAt = _parseTimestamp(
          _firstString(payload, const ['timestamp', 'receivedAt', 'time']),
        ) ??
        DateTime.now();
    final method = _firstString(payload, const ['method', 'httpMethod']) ??
        _extractMethod(rawPacket) ??
        'LIVE';
    final url = _firstString(payload, const ['url', 'path', 'requestUri']) ??
        _extractUrl(rawPacket);
    final responseCode = _firstInt(
          payload,
          const ['responseCode', 'statusCode', 'status'],
        ) ??
        _extractStatusCode(rawPacket) ??
        0;
    final responseSize = _firstInt(
          payload,
          const ['responseSize', 'bytesSent', 'size', 'contentLength'],
        ) ??
        0;

    final log = FirewallLog(
      id: id,
      ipAddress: _firstString(
            payload,
            const ['ipAddress', 'ip', 'srcIp', 'sourceIp', 'clientIp'],
          ) ??
          'live-stream',
      timestamp: receivedAt.toIso8601String(),
      method: method,
      requestMethod: _firstString(payload, const ['requestMethod']) ?? method,
      request: rawPacket,
      status: _firstString(payload, const ['statusText', 'status']) ??
          responseCode.toString(),
      bytes: _firstString(payload, const ['bytes', 'length']) ??
          responseSize.toString(),
      userAgent: _firstString(payload, const ['userAgent', 'ua']) ?? '',
      parameters:
          _firstString(payload, const ['parameters', 'query', 'queryString']) ??
              '',
      url: url,
      responseCode: responseCode,
      responseSize: responseSize,
      country: _firstString(
            payload,
            const ['country', 'countryName', 'country_name'],
          ) ??
          '',
      latitude: _firstDouble(payload, const ['latitude', 'lat']),
      longitude: _firstDouble(payload, const ['longitude', 'lon', 'lng']),
      requestRateAnomaly:
          _firstBool(payload, const ['requestRateAnomaly']) ?? false,
      source: _firstString(payload, const ['source', 'logSource']) ?? '',
      // ── Backend-authority fields ─────────────────────────────────────────
      // packet_server.py already embeds these for every live packet/log event.
      backendAlerts: _parseAlertsList(payload['alerts']),
      backendThreatLevel: _firstString(
        payload,
        const ['threatLevel', 'threat_level'],
      ),
      backendSeverityScore: _firstInt(
        payload,
        const ['severityScore', 'severity_score'],
      ),
    );

    return LivePacketRecord(
      id: id,
      log: log,
      rawPacket: rawPacket,
      receivedAt: receivedAt,
    );
  }

  static LivePacketRecord parse({
    required String message,
    required int id,
  }) {
    return tryParse(message: message, id: id)!;
  }

  static Map<String, dynamic> _parsePayload(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Fall back to treating the whole message as the packet payload.
    }

    return <String, dynamic>{'data': message};
  }

  static Map<String, dynamic> _normalizePayload(Map<String, dynamic> payload) {
    final nestedData = payload['data'];
    if (nestedData is! Map) {
      return payload;
    }

    final normalized = Map<String, dynamic>.from(nestedData);
    payload.forEach((key, value) {
      if (key == 'data' || normalized.containsKey(key)) {
        return;
      }
      normalized[key] = value;
    });
    return normalized;
  }

  static String? _firstString(
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = payload[key];
      if (value == null) {
        continue;
      }
      final normalized = value.toString().trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  static int? _firstInt(
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = payload[key];
      if (value == null) {
        continue;
      }
      if (value is int) {
        return value;
      }
      final parsed = int.tryParse(value.toString());
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static double? _firstDouble(
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = payload[key];
      if (value == null) {
        continue;
      }
      if (value is num) {
        return value.toDouble();
      }
      final parsed = double.tryParse(value.toString());
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static bool? _firstBool(
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = payload[key];
      if (value == null) {
        continue;
      }
      if (value is bool) {
        return value;
      }
      final normalized = value.toString().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return null;
  }

  static DateTime? _parseTimestamp(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static String? _extractMethod(String rawPacket) {
    final match = RegExp(
      r'\b(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b',
      caseSensitive: false,
    ).firstMatch(rawPacket);
    return match?.group(0)?.toUpperCase();
  }

  static String _extractUrl(String rawPacket) {
    final match = RegExp(
      r'\b(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s+(\S+)',
      caseSensitive: false,
    ).firstMatch(rawPacket);
    return match?.group(1) ?? rawPacket;
  }

  static int? _extractStatusCode(String rawPacket) {
    final match = RegExp(r'\b([1-5]\d{2})\b').firstMatch(rawPacket);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Converts the backend's `alerts` field (a JSON list of strings or null)
  /// into a Dart [List<String>].  Returns null if no alerts are present.
  static List<String>? _parseAlertsList(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      final items = value
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return items.isEmpty ? null : items;
    }
    // Backend sometimes sends a single string
    final str = value.toString().trim();
    return str.isEmpty ? null : [str];
  }
}

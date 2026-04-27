import 'dart:convert';

import '../models/server_status_snapshot.dart';

class ServerStatusParser {
  static ServerStatusSnapshot? parse(dynamic message) {
    final payload = _parsePayload(message);
    if (payload.isEmpty) {
      return null;
    }

    final type = payload['type']?.toString().trim().toLowerCase() ?? '';
    if (type.isNotEmpty && type != 'server_status') {
      return null;
    }
    if (type.isEmpty && !_looksLikeStatusPayload(payload)) {
      return null;
    }

    return ServerStatusSnapshot(
      receivedAt: _parseDateTime(payload['timestamp']) ?? DateTime.now(),
      hostname: _asString(payload['hostname']),
      localIp: _asString(payload['localIp']),
      platform: _asString(payload['platform']),
      platformRelease: _asString(payload['platformRelease']),
      platformVersion: _asString(payload['platformVersion']),
      architecture: _asString(payload['architecture']),
      pythonVersion: _asString(payload['pythonVersion']),
      cpuModel: _asString(payload['cpuModel']),
      cpuCores: _asInt(payload['cpuCores']) ?? 0,
      cpuUsagePercent: _asDouble(payload['cpuUsagePercent']),
      memoryTotalMb: _asInt(payload['memoryTotalMb']),
      memoryUsedMb: _asInt(payload['memoryUsedMb']),
      memoryUsagePercent: _asDouble(payload['memoryUsagePercent']),
      diskTotalGb: _asDouble(payload['diskTotalGb']),
      diskUsedGb: _asDouble(payload['diskUsedGb']),
      diskUsagePercent: _asDouble(payload['diskUsagePercent']),
      sshConnections: _asInt(payload['sshConnections']) ?? 0,
      activeTcpConnections: _asInt(payload['activeTcpConnections']) ?? 0,
      udpConnections: _asInt(payload['udpConnections']) ?? 0,
      uniqueSourceIps: _asInt(payload['uniqueSourceIps']) ?? 0,
      uptimeSeconds: _asInt(payload['uptimeSeconds']) ?? 0,
      uptime: _asString(payload['uptime']),
      connectedClients: _asInt(payload['connectedClients']) ?? 0,
      activeClients: _parseListMap(payload['activeClients']),
      registeredDevices: _parseListMap(payload['registeredDevices']),
      activeSshSessions: _parseListMap(payload['activeSshSessions']),
      recentSshAttempts: _parseListMap(payload['recentSshAttempts']),
      packetsCaptured: _asInt(payload['packetsCaptured']) ?? 0,
      tcpPackets: _asInt(payload['tcpPackets']) ?? 0,
      udpPackets: _asInt(payload['udpPackets']) ?? 0,
      otherPackets: _asInt(payload['otherPackets']) ?? 0,
      lastPacketAt: _parseDateTime(payload['lastPacketAt']),
      batteryPresent: _asBool(payload['batteryPresent']) ?? false,
      batteryPercent: _asInt(payload['batteryPercent']),
      isCharging: _asBool(payload['isCharging']),
      batteryStatus: _asString(payload['batteryStatus']),
      cloudStatus: _parseCloudStatus(payload['cloudStatus']),
      dockerContainers: _parseDockerContainers(payload['dockerContainers']),
    );
  }

  static Map<String, String> _parseCloudStatus(dynamic value) {
    if (value is! Map) {
      return {};
    }
    final result = <String, String>{};
    value.forEach((key, val) {
      result[key.toString()] = val?.toString() ?? '';
    });
    return result;
  }

  static List<Map<String, dynamic>> _parseDockerContainers(dynamic value) {
    if (value is! List) {
      return [];
    }
    return value.map((entry) {
      if (entry is Map) {
        return Map<String, dynamic>.from(entry);
      }

      final raw = entry.toString();
      final parts = raw.split('\t');
      if (parts.length >= 5) {
        final status = parts[3].trim();
        return <String, dynamic>{
          'id': parts[0].trim(),
          'image': parts[1].trim(),
          'name': parts[4].trim(),
          'state': status.toLowerCase().contains('up') ? 'running' : 'exited',
          'status': status,
          'raw': raw,
        };
      }

      return <String, dynamic>{
        'name': raw,
        'state': 'unknown',
        'status': 'Unknown',
        'raw': raw,
      };
    }).toList(growable: false);
  }

  static List<Map<String, dynamic>> _parseListMap(dynamic value) {
    if (value is! List) {
      return [];
    }
    final result = <Map<String, dynamic>>[];
    for (final e in value) {
      if (e is Map) {
        result.add(Map<String, dynamic>.from(e));
      } else {
        result.add(<String, dynamic>{});
      }
    }
    return result;
  }

  static bool _looksLikeStatusPayload(Map<String, dynamic> payload) {
    return payload.containsKey('hostname') ||
        payload.containsKey('cpuUsagePercent') ||
        payload.containsKey('memoryTotalMb') ||
        payload.containsKey('connectedClients') ||
        payload.containsKey('packetsCaptured');
  }

  static Map<String, dynamic> _parsePayload(dynamic message) {
    if (message is Map<String, dynamic>) {
      return message;
    }
    if (message is Map) {
      return Map<String, dynamic>.from(message);
    }
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Ignore malformed payloads and let the caller drop them.
    }
    return const <String, dynamic>{};
  }

  static String _asString(dynamic value) => value?.toString().trim() ?? '';

  static int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _asDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    final normalized = value?.toString().toLowerCase().trim();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return null;
  }

  static DateTime? _parseDateTime(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}

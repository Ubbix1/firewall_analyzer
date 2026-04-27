import 'dart:convert';

import 'firewall_log.dart';

class SavedSuspiciousLogEntry {
  final int? id;
  final String signature;
  final String sourceLabel;
  final String savedAt;
  final String riskLevel;
  final FirewallLog log;

  const SavedSuspiciousLogEntry({
    this.id,
    required this.signature,
    required this.sourceLabel,
    required this.savedAt,
    required this.riskLevel,
    required this.log,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'signature': signature,
      'sourceLabel': sourceLabel,
      'savedAt': savedAt,
      'riskLevel': riskLevel,
      'logJson': jsonEncode(log.toJson()),
    };
  }

  static SavedSuspiciousLogEntry fromMap(Map<String, dynamic> map) {
    final rawJson = map['logJson']?.toString() ?? '{}';
    final decoded = jsonDecode(rawJson);
    final payload = decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);

    return SavedSuspiciousLogEntry(
      id: map['id'] as int?,
      signature: map['signature']?.toString() ?? '',
      sourceLabel: map['sourceLabel']?.toString() ?? '',
      savedAt: map['savedAt']?.toString() ?? '',
      riskLevel: map['riskLevel']?.toString() ?? '',
      log: FirewallLog.fromJson(payload),
    );
  }
}

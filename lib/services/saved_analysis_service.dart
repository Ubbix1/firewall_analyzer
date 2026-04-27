import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/live_packet_record.dart';
import '../models/firewall_log.dart';

class SavedAnalysisFile {
  final String name;
  final DateTime savedAt;
  final List<LivePacketRecord> packets;

  SavedAnalysisFile({
    required this.name,
    required this.savedAt,
    required this.packets,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'savedAt': savedAt.toIso8601String(),
        'packets': packets.map((p) => {
          'id': p.id,
          'receivedAt': p.receivedAt.toIso8601String(),
          'rawPacket': p.rawPacket,
          'log': p.log.toJson(),
        }).toList(),
      };

  factory SavedAnalysisFile.fromJson(Map<String, dynamic> json) {
    return SavedAnalysisFile(
      name: json['name'],
      savedAt: DateTime.parse(json['savedAt']),
      packets: (json['packets'] as List).map((p) {
        final Map<String, dynamic> packetJson = Map<String, dynamic>.from(p);
        return LivePacketRecord(
          id: packetJson['id'] ?? 0,
          receivedAt: DateTime.parse(packetJson['receivedAt']),
          rawPacket: packetJson['rawPacket'],
          log: FirewallLog.fromJson(Map<String, dynamic>.from(packetJson['log'])),
        );
      }).toList().cast<LivePacketRecord>(),
    );
  }
}

class SavedAnalysisService {
  static const String _storageKey = 'saved_analysis_files';

  static Future<void> saveAnalysis(String name, List<LivePacketRecord> packets) async {
    final prefs = await SharedPreferences.getInstance();
    final files = await getAllSavedAnalysis();
    
    final newFile = SavedAnalysisFile(
      name: name,
      savedAt: DateTime.now(),
      packets: packets,
    );
    
    files.add(newFile);
    await _saveAll(prefs, files);
  }

  static Future<List<SavedAnalysisFile>> getAllSavedAnalysis() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString(_storageKey);
    if (encoded == null) return [];
    
    try {
      final List<dynamic> decoded = jsonDecode(encoded);
      return decoded.map((item) {
        final Map<String, dynamic> fileJson = Map<String, dynamic>.from(item);
        return SavedAnalysisFile.fromJson(fileJson);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> deleteAnalysis(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final files = await getAllSavedAnalysis();
    files.removeWhere((f) => f.name == name);
    await _saveAll(prefs, files);
  }

  static Future<void> _saveAll(SharedPreferences prefs, List<SavedAnalysisFile> files) async {
    final String encoded = jsonEncode(files.map((f) => f.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}

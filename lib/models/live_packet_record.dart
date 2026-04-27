import 'firewall_log.dart';

class LivePacketRecord {
  final int id;
  final FirewallLog log;
  final String rawPacket;
  final DateTime receivedAt;

  const LivePacketRecord({
    required this.id,
    required this.log,
    required this.rawPacket,
    required this.receivedAt,
  });

  LivePacketRecord copyWith({
    int? id,
    FirewallLog? log,
    String? rawPacket,
    DateTime? receivedAt,
  }) {
    return LivePacketRecord(
      id: id ?? this.id,
      log: log ?? this.log,
      rawPacket: rawPacket ?? this.rawPacket,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }
}

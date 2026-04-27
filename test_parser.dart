import 'dart:convert';
import 'lib/services/server_status_parser.dart';

void main() {
  final payload = {
    "type": "server_status",
    "timestamp": "2026-04-22T18:02:46Z",
    "hostname": "noodleos",
    "localIp": "127.0.0.1",
    "platform": "Linux",
    "platformRelease": "5.15",
    "platformVersion": "1",
    "architecture": "x86_64",
    "pythonVersion": "3.10",
    "cpuModel": "Intel",
    "cpuCores": 4,
    "cpuUsagePercent": 10.0,
    "memoryTotalMb": 4000,
    "memoryUsedMb": 2000,
    "memoryUsagePercent": 50.0,
    "diskTotalGb": 100.0,
    "diskUsedGb": 50.0,
    "diskUsagePercent": 50.0,
    "sshConnections": 1,
    "activeTcpConnections": 10,
    "udpConnections": 5,
    "uniqueSourceIps": 2,
    "uptimeSeconds": 1000,
    "uptime": "1000s",
    "connectedClients": 1,
    "activeClients": [],
    "registeredDevices": [],
    "activeSshSessions": [
      {
        "user": "root",
        "tty": "pts/0",
        "ip": "1.2.3.4",
        "connectedAt": "10:00"
      }
    ],
    "recentSshAttempts": [
      {
        "timestamp": "2026-04-22T18:02:46Z",
        "ip": "1.2.3.4",
        "user": "admin",
        "status": "FAILED"
      }
    ],
    "packetsCaptured": 100,
    "tcpPackets": 50,
    "udpPackets": 50,
    "otherPackets": 0,
    "lastPacketAt": null,
    "batteryPresent": false,
    "batteryPercent": null,
    "isCharging": null,
    "batteryStatus": "Unknown",
    "cloudStatus": {},
    "dockerContainers": []
  };

  try {
    final snapshot = ServerStatusParser.parse(jsonEncode(payload));
    print("Parsed successfully. Active SSH sessions: ${snapshot?.activeSshSessions.length}");
    print("Recent SSH attempts: ${snapshot?.recentSshAttempts.length}");
  } catch (e, stack) {
    print("Error parsing: $e");
    print(stack);
  }
}

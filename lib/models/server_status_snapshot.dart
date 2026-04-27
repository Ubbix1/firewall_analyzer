class ServerStatusSnapshot {
  final DateTime receivedAt;
  final String hostname;
  final String localIp;
  final String platform;
  final String platformRelease;
  final String platformVersion;
  final String architecture;
  final String pythonVersion;
  final String cpuModel;
  final int cpuCores;
  final double? cpuUsagePercent;
  final int? memoryTotalMb;
  final int? memoryUsedMb;
  final double? memoryUsagePercent;
  final double? diskTotalGb;
  final double? diskUsedGb;
  final double? diskUsagePercent;
  // added metrics
  final int sshConnections;
  final int activeTcpConnections;
  final int udpConnections;
  final int uniqueSourceIps;
  final int uptimeSeconds;
  final String uptime;
  final int connectedClients;
  final List<Map<String, dynamic>> activeClients;
  final List<Map<String, dynamic>> registeredDevices;
  final List<Map<String, dynamic>> activeSshSessions;
  final List<Map<String, dynamic>> recentSshAttempts;
  final int packetsCaptured;
  final int tcpPackets;
  final int udpPackets;
  final int otherPackets;
  final DateTime? lastPacketAt;
  final bool batteryPresent;
  final int? batteryPercent;
  final bool? isCharging;
  final String batteryStatus;
  final Map<String, String> cloudStatus;
  final List<Map<String, dynamic>> dockerContainers;

  const ServerStatusSnapshot({
    required this.receivedAt,
    required this.hostname,
    required this.localIp,
    required this.platform,
    required this.platformRelease,
    required this.platformVersion,
    required this.architecture,
    required this.pythonVersion,
    required this.cpuModel,
    required this.cpuCores,
    required this.cpuUsagePercent,
    required this.memoryTotalMb,
    required this.memoryUsedMb,
    required this.memoryUsagePercent,
    required this.diskTotalGb,
    required this.diskUsedGb,
    required this.diskUsagePercent,
    required this.uptimeSeconds,
    required this.uptime,
    required this.connectedClients,
    required this.activeClients,
    required this.registeredDevices,
    required this.activeSshSessions,
    required this.recentSshAttempts,
    required this.packetsCaptured,
    required this.tcpPackets,
    required this.udpPackets,
    required this.otherPackets,
    required this.lastPacketAt,
    required this.sshConnections,
    required this.activeTcpConnections,
    required this.udpConnections,
    required this.uniqueSourceIps,
    required this.batteryPresent,
    required this.batteryPercent,
    required this.isCharging,
    required this.batteryStatus,
    this.cloudStatus = const {},
    this.dockerContainers = const [],
  });
}

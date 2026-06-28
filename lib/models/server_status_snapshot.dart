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
  final double? cpuTemp;
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
    this.cpuTemp,
  });

  factory ServerStatusSnapshot.fromJson(Map<String, dynamic> json) {
    return ServerStatusSnapshot(
      receivedAt: DateTime.parse(json['receivedAt']),
      hostname: json['hostname'] ?? 'Unknown',
      localIp: json['localIp'] ?? 'Unknown',
      platform: json['platform'] ?? 'Unknown',
      platformRelease: json['platformRelease'] ?? 'Unknown',
      platformVersion: json['platformVersion'] ?? 'Unknown',
      architecture: json['architecture'] ?? 'Unknown',
      pythonVersion: json['pythonVersion'] ?? 'Unknown',
      cpuModel: json['cpuModel'] ?? 'Unknown',
      cpuCores: json['cpuCores'] ?? 1,
      cpuUsagePercent: (json['cpuUsagePercent'] as num?)?.toDouble(),
      memoryTotalMb: json['memoryTotalMb'],
      memoryUsedMb: json['memoryUsedMb'],
      memoryUsagePercent: (json['memoryUsagePercent'] as num?)?.toDouble(),
      diskTotalGb: (json['diskTotalGb'] as num?)?.toDouble(),
      diskUsedGb: (json['diskUsedGb'] as num?)?.toDouble(),
      diskUsagePercent: (json['diskUsagePercent'] as num?)?.toDouble(),
      uptimeSeconds: json['uptimeSeconds'] ?? 0,
      uptime: json['uptime'] ?? '0s',
      connectedClients: json['connectedClients'] ?? 0,
      activeClients: List<Map<String, dynamic>>.from(json['activeClients'] ?? []),
      registeredDevices: List<Map<String, dynamic>>.from(json['registeredDevices'] ?? []),
      activeSshSessions: List<Map<String, dynamic>>.from(json['activeSshSessions'] ?? []),
      recentSshAttempts: List<Map<String, dynamic>>.from(json['recentSshAttempts'] ?? []),
      packetsCaptured: json['packetsCaptured'] ?? 0,
      tcpPackets: json['tcpPackets'] ?? 0,
      udpPackets: json['udpPackets'] ?? 0,
      otherPackets: json['otherPackets'] ?? 0,
      lastPacketAt: json['lastPacketAt'] != null ? DateTime.parse(json['lastPacketAt']) : null,
      sshConnections: json['sshConnections'] ?? 0,
      activeTcpConnections: json['activeTcpConnections'] ?? 0,
      udpConnections: json['udpConnections'] ?? 0,
      uniqueSourceIps: json['uniqueSourceIps'] ?? 0,
      batteryPresent: json['batteryPresent'] ?? false,
      batteryPercent: json['batteryPercent'],
      isCharging: json['isCharging'],
      batteryStatus: json['batteryStatus'] ?? 'Unknown',
      cloudStatus: Map<String, String>.from(json['cloudStatus'] ?? {}),
      dockerContainers: List<Map<String, dynamic>>.from(json['dockerContainers'] ?? []),
      cpuTemp: (json['cpuTemp'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'receivedAt': receivedAt.toIso8601String(),
      'hostname': hostname,
      'localIp': localIp,
      'platform': platform,
      'platformRelease': platformRelease,
      'platformVersion': platformVersion,
      'architecture': architecture,
      'pythonVersion': pythonVersion,
      'cpuModel': cpuModel,
      'cpuCores': cpuCores,
      'cpuUsagePercent': cpuUsagePercent,
      'memoryTotalMb': memoryTotalMb,
      'memoryUsedMb': memoryUsedMb,
      'memoryUsagePercent': memoryUsagePercent,
      'diskTotalGb': diskTotalGb,
      'diskUsedGb': diskUsedGb,
      'diskUsagePercent': diskUsagePercent,
      'uptimeSeconds': uptimeSeconds,
      'uptime': uptime,
      'connectedClients': connectedClients,
      'activeClients': activeClients,
      'registeredDevices': registeredDevices,
      'activeSshSessions': activeSshSessions,
      'recentSshAttempts': recentSshAttempts,
      'packetsCaptured': packetsCaptured,
      'tcpPackets': tcpPackets,
      'udpPackets': udpPackets,
      'otherPackets': otherPackets,
      'lastPacketAt': lastPacketAt?.toIso8601String(),
      'sshConnections': sshConnections,
      'activeTcpConnections': activeTcpConnections,
      'udpConnections': udpConnections,
      'uniqueSourceIps': uniqueSourceIps,
      'batteryPresent': batteryPresent,
      'batteryPercent': batteryPercent,
      'isCharging': isCharging,
      'batteryStatus': batteryStatus,
      'cloudStatus': cloudStatus,
      'dockerContainers': dockerContainers,
      'cpuTemp': cpuTemp,
    };
  }
}

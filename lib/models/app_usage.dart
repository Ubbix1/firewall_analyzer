class AppUsage {
  final int pid;
  final String name;
  final String user;
  final double cpuUsage;
  final double memoryUsage;
  final String status;

  AppUsage({
    required this.pid,
    required this.name,
    required this.user,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.status,
  });

  factory AppUsage.fromJson(Map<String, dynamic> json) {
    return AppUsage(
      pid: json['pid'] ?? 0,
      name: json['name'] ?? 'Unknown',
      user: json['user'] ?? 'N/A',
      cpuUsage: (json['cpuUsage'] ?? 0.0).toDouble(),
      memoryUsage: (json['memoryUsage'] ?? 0.0).toDouble(),
      status: json['status'] ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pid': pid,
      'name': name,
      'user': user,
      'cpuUsage': cpuUsage,
      'memoryUsage': memoryUsage,
      'status': status,
    };
  }
}

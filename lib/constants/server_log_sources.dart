class ServerLogSource {
  final String id;
  final String label;
  final String virtualPath;

  const ServerLogSource({
    required this.id,
    required this.label,
    required this.virtualPath,
  });
}

const List<ServerLogSource> serverLogSources = [
  ServerLogSource(
    id: 'auth',
    label: 'Authentication (auth.log)',
    virtualPath: '/var/log/auth.log',
  ),
  ServerLogSource(
    id: 'syslog',
    label: 'System Logs (syslog)',
    virtualPath: '/var/log/syslog',
  ),
  ServerLogSource(
    id: 'ufw',
    label: 'UFW Firewall',
    virtualPath: '/var/log/ufw.log',
  ),
  ServerLogSource(
    id: 'tailscale',
    label: 'Tailscale Logs',
    virtualPath: '/var/log/tailscale/tailscaled.log',
  ),
];

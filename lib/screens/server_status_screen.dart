import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../widgets/connectivity_gate.dart';

import '../controllers/server_status_controller.dart';
import '../models/server_status_snapshot.dart';
import '../models/app_usage.dart';

class ServerStatusScreen extends StatefulWidget {
  final ServerStatusController controller;
  final VoidCallback onOpenSettings;

  const ServerStatusScreen({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  @override
  State<ServerStatusScreen> createState() => _ServerStatusScreenState();
}

class _ServerStatusScreenState extends State<ServerStatusScreen> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final snapshot = widget.controller.snapshot;
        final isLoading = widget.controller.isLoading;

        if (snapshot == null) {
          return _buildSkeleton(context);
        }

        return ConnectivityGate(
          controller: widget.controller,
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (widget.controller.isUsingCache || widget.controller.isOffline)
                    _buildOfflineIndicator(context),
                  _buildStatusCard(context, snapshot),
                  const SizedBox(height: 16),
                  _buildBatteryCard(context, snapshot),
                  _buildSectionTitle('Server'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.8,
              children: [
                _buildModernStatCard(
                  context,
                  icon: Icons.dns,
                  label: 'Hostname',
                  value: snapshot.hostname,
                  color: Colors.blue,
                ),
                _buildModernStatCard(
                  context,
                  icon: Icons.wifi,
                  label: 'Local IP',
                  value: snapshot.localIp,
                  color: Colors.indigo,
                ),
                _buildModernStatCard(
                  context,
                  icon: Icons.timelapse,
                  label: 'Uptime',
                  value: snapshot.uptime,
                  color: Colors.teal,
                ),
                _buildModernStatCard(
                  context,
                  icon: Icons.group,
                  label: 'Clients',
                  value: '${snapshot.connectedClients}',
                  color: Colors.purple,
                ),
                _buildModernStatCard(
                  context,
                  icon: Icons.bug_report,
                  label: 'Threat Activity',
                  value: '${snapshot.uniqueSourceIps} Unique IPs',
                  color: Colors.red,
                ),
                _buildModernStatCard(
                  context,
                  icon: Icons.lan,
                  label: 'TCP / UDP',
                  value: '${snapshot.activeTcpConnections} / ${snapshot.udpConnections}',
                  color: Colors.indigo,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('System Specs'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.8,
              children: [
                _buildModernStatCard(
                  context,
                  icon: Icons.memory,
                  label: 'CPU',
                  value: '${snapshot.cpuModel}\n${snapshot.cpuCores} cores',
                  color: Colors.orange,
                ),
                _buildModernStatCard(
                  context,
                  icon: Icons.developer_board,
                  label: 'Platform',
                  value: '${snapshot.platform}\n${snapshot.architecture}',
                  color: Colors.blueGrey,
                ),
                _buildModernStatCard(
                  context,
                  icon: Icons.code,
                  label: 'Python',
                  value: snapshot.pythonVersion,
                  color: Colors.blue,
                ),
                _buildModernStatCard(
                  context,
                  icon: Icons.info_outline,
                  label: 'Kernel',
                  value: snapshot.platformVersion,
                  color: Colors.cyan,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSectionTitle('Resource Usage'),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildResourceBar(
                      context,
                      icon: Icons.speed,
                      label: 'CPU Usage',
                      value: snapshot.cpuUsagePercent ?? 0,
                      displayValue: _formatPercent(snapshot.cpuUsagePercent),
                    ),
                    const SizedBox(height: 12),
                    _buildResourceBar(
                      context,
                      icon: Icons.storage,
                      label: 'Memory',
                      value: snapshot.memoryTotalMb != null && snapshot.memoryTotalMb! > 0
                          ? (snapshot.memoryUsedMb ?? 0) / snapshot.memoryTotalMb!.toDouble() * 100
                          : 0,
                      displayValue: '${_formatMb(snapshot.memoryUsedMb)} / ${_formatMb(snapshot.memoryTotalMb)}',
                    ),
                    const SizedBox(height: 12),
                    _buildResourceBar(
                      context,
                      icon: Icons.save,
                      label: 'Disk',
                      value: snapshot.diskUsagePercent ?? 0,
                      displayValue: '${_formatGb(snapshot.diskUsedGb)} / ${_formatGb(snapshot.diskTotalGb)}',
                    ),
                  ],
                ),
              ),
            ),
             const SizedBox(height: 16),
             _buildSectionTitle('Live SSH Sessions'),
             _buildLiveSshSessionsList(context, snapshot),
            _buildSectionTitle('App Usage (Top Processes)'),
            _buildAppUsageList(context),
            const SizedBox(height: 32),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Overview Card Skeleton
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          const SizedBox(height: 16),
          // Battery Card Skeleton
          Container(
            height: 90,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          const SizedBox(height: 24),
          _buildSkeletonSectionTitle(),
          const SizedBox(height: 12),
          // Server Grid Skeleton
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: List.generate(6, (index) => _buildSkeletonMetricCard()),
          ),
          const SizedBox(height: 24),
          _buildSkeletonSectionTitle(),
          const SizedBox(height: 12),
          // Resource usage card
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          const SizedBox(height: 24),
          _buildSkeletonSectionTitle(),
          const SizedBox(height: 12),
          // System Specs Grid Skeleton
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: List.generate(4, (index) => _buildSkeletonMetricCard()),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSkeletonSectionTitle() {
    return Container(
      width: 120,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildSkeletonMetricCard({double? width}) {
    return Container(
      width: width,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    ServerStatusSnapshot snapshot,
  ) {
    final isConnecting = widget.controller.isConnectingSocket;
    final isLive = widget.controller.isSocketConnected;
    final lastSync = widget.controller.lastLiveSyncUpdate;
    final lastCache = widget.controller.lastCacheUpdate;

    String getTimeAgo(DateTime? dateTime) {
      if (dateTime == null) return 'Never';
      final diff = DateTime.now().difference(dateTime);
      if (diff.inSeconds < 30) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return DateFormat.Hm().format(dateTime);
    }

    // Determine badge color and text
    final Color statusColor = isLive ? Colors.green : (isConnecting ? Colors.blue : Colors.orange);
    final String statusLabel = isLive ? 'LIVE' : (isConnecting ? 'SYNCING' : 'CACHED');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Overview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLive || isConnecting) 
                        _PulseIndicator(color: statusColor, size: 6)
                      else 
                        const Icon(Icons.history, size: 10, color: Colors.orange),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildStatusRow(
              context,
              icon: isLive ? Icons.check_circle : (isConnecting ? Icons.sync : Icons.cloud_off),
              label: 'System Status',
              value: isLive ? 'Synchronized' : (isConnecting ? 'Connecting...' : 'Offline / Viewing Cache'),
              color: statusColor,
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
              context,
              icon: Icons.access_time,
              label: 'Last Update',
              value: isLive ? 'Active now' : getTimeAgo(lastSync ?? lastCache),
              color: isLive ? Colors.blue : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color?.withOpacity(0.7) ?? Theme.of(context).hintColor),
        const SizedBox(width: 10),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).hintColor,
                fontSize: 10,
              ),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 10,
              ),
        ),
      ],
    );
  }

  Widget _buildOfflineIndicator(BuildContext context) {
    final isOffline = widget.controller.isOffline;
    final lastUpdate = widget.controller.lastCacheUpdate;
    final timeAgo = lastUpdate != null
        ? DateFormat.Hm().format(lastUpdate)
        : 'Unknown';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: isOffline ? Colors.red.withOpacity(0.9) : Colors.orange.withOpacity(0.9),
      child: Row(
        children: [
          Icon(
            isOffline ? Icons.cloud_off : Icons.history,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isOffline
                  ? 'Server Offline - Showing cached status'
                  : 'Viewing cached metrics (Updated $timeAgo)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (isOffline)
            TextButton(
              onPressed: () => widget.controller.connectAndSync(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                minimumSize: const Size(50, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('RETRY', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildBatteryCard(
    BuildContext context,
    ServerStatusSnapshot snapshot,
  ) {
    final batteryText = !snapshot.batteryPresent
        ? 'No battery detected'
        : '${snapshot.batteryPercent ?? '--'}% | ${snapshot.batteryStatus}';
    final icon = snapshot.isCharging == true
        ? Icons.battery_charging_full
        : Icons.battery_std;
    final color = (snapshot.batteryPercent ?? 100) < 20 ? Colors.red : Colors.green;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.12),
            color.withOpacity(0.04),
          ],
        ),
        border: Border.all(
          color: color.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Battery Status',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  batteryText,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (snapshot.batteryPresent && snapshot.batteryPercent != null)
            SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: snapshot.batteryPercent! / 100,
                    strokeWidth: 6,
                    backgroundColor: color.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                  Center(
                    child: Text(
                      '${snapshot.batteryPercent}%',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            width: 24,
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceBar(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required String displayValue,
  }) {
    final percentage = value.clamp(0, 100);
    final color = percentage > 85
        ? Colors.red
        : percentage > 70
            ? Colors.orange
            : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            Text(
              displayValue,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).hintColor,
                    fontFamily: 'monospace',
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Container(
                height: 10,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                height: 10,
                width: (MediaQuery.of(context).size.width - 64) * (percentage / 100),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color,
                      color.withOpacity(0.7),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModernStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = color ?? colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            baseColor.withOpacity(0.1),
            baseColor.withOpacity(0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: baseColor.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: baseColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 14,
                      color: baseColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  value,
                  key: ValueKey<String>(value),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
                    fontSize: 12,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProtocolStats(
    BuildContext context, {
    required int tcp,
    required int udp,
    required int other,
  }) {
    final total = tcp + udp + other;
    final tcpPercent = total > 0 ? tcp / total : 0.0;
    final udpPercent = total > 0 ? udp / total : 0.0;
    final otherPercent = total > 0 ? other / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Protocol Distribution',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (tcp > 0)
                    Expanded(
                        flex: (tcpPercent * 100).toInt().clamp(1, 100),
                        child: Container(color: Colors.blue)),
                  if (udp > 0)
                    Expanded(
                        flex: (udpPercent * 100).toInt().clamp(1, 100),
                        child: Container(color: Colors.orange)),
                  if (other > 0)
                    Expanded(
                        flex: (otherPercent * 100).toInt().clamp(1, 100),
                        child: Container(color: Colors.grey)),
                  if (total == 0)
                    Expanded(child: Container(color: Colors.grey.withOpacity(0.2))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildProtocolLegendItem('TCP', tcp, Colors.blue),
              _buildProtocolLegendItem('UDP', udp, Colors.orange),
              _buildProtocolLegendItem('Other', other, Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProtocolLegendItem(String label, int value, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 2),
        Text('$value',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ],
    );
  }



  String _formatPercent(double? value) {
    if (value == null) {
      return 'Unavailable';
    }
    return '${value.toStringAsFixed(1)}%';
  }

  String _formatMb(int? value) {
    if (value == null) {
      return 'Unavailable';
    }
    return '$value MB';
  }

  String _formatGb(double? value) {
    if (value == null) {
      return 'Unavailable';
    }
    return '${value.toStringAsFixed(1)} GB';
  }

  Widget _buildAppUsageList(BuildContext context) {
    final apps = widget.controller.appUsage;
    
    if (apps.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Column(
          children: [
            Icon(Icons.query_stats, size: 48, color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text('No app usage data available yet.', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => widget.controller.loadAppUsage(),
              icon: const Icon(Icons.refresh),
              label: const Text('Fetch App Usage'),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: apps.length,
            separatorBuilder: (context, index) => Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
            itemBuilder: (context, index) {
              final app = apps[index];
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      app.name.isNotEmpty ? app.name.substring(0, 1).toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  app.name,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
                subtitle: Text(
                  'PID: ${app.pid} • ${app.user}',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUsageTag(context, '${app.cpuUsage}%', app.cpuUsage > 50 ? Colors.red : Colors.blue, 'CPU'),
                    const SizedBox(width: 8),
                    _buildUsageTag(context, '${app.memoryUsage}%', app.memoryUsage > 10 ? Colors.orange : Colors.green, 'MEM'),
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextButton.icon(
               onPressed: () => widget.controller.loadAppUsage(),
               icon: const Icon(Icons.refresh, size: 16),
               label: const Text('Refresh Processes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageTag(BuildContext context, String value, Color color, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Theme.of(context).hintColor),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildLiveSshSessionsList(BuildContext context, ServerStatusSnapshot snapshot) {
    if (snapshot.activeSshSessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
        ),
        child: const Center(
          child: Text('No active SSH sessions.', style: TextStyle(fontWeight: FontWeight.w500)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: snapshot.activeSshSessions.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
        itemBuilder: (context, index) {
          final session = snapshot.activeSshSessions[index];
          final user = session['user'] ?? 'Unknown User';
          final ip = session['ip'] ?? 'Unknown IP';
          
          String deviceName = ip;
          try {
            final regDevice = snapshot.registeredDevices.firstWhere(
              (d) => d['ip'] == ip || d['localIp'] == ip,
              orElse: () => {},
            );
            if (regDevice.isNotEmpty) {
              deviceName = regDevice['deviceName'] ?? regDevice['deviceModel'] ?? ip;
            }
          } catch (_) {}

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.terminal, color: Colors.indigo, size: 20),
            ),
            title: Text(
              deviceName,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            subtitle: Text(
              'User: $user • ${session['connectedAt'] ?? 'Unknown'}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.security, color: Colors.green, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'SECURE',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 9),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PulseIndicator extends StatefulWidget {
  final Color color;
  final double size;
  const _PulseIndicator({required this.color, this.size = 8});

  @override
  State<_PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<_PulseIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity(1.0 - _controller.value),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.5),
                blurRadius: 8 * _controller.value,
                spreadRadius: 4 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

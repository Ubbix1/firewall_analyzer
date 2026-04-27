import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../controllers/server_status_controller.dart';
import '../models/server_status_snapshot.dart';

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
          if (isLoading) {
            return _buildSkeleton(context);
          }

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.settings_input_antenna,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Use the top-right settings icon to open Server Settings, connect to your endpoint, and load server metrics.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: widget.onOpenSettings,
                      icon: const Icon(Icons.settings),
                      label: const Text('Open Settings'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            Expanded(
              child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildStatusCard(context, snapshot),
            const SizedBox(height: 16),
            _buildBatteryCard(context, snapshot),
            _buildSectionTitle('Server'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildMetricCard(
                  context,
                  icon: Icons.dns,
                  label: 'Hostname',
                  value: snapshot.hostname,
                ),
                _buildMetricCard(
                  context,
                  icon: Icons.wifi,
                  label: 'Local IP',
                  value: snapshot.localIp,
                ),
                _buildMetricCard(
                  context,
                  icon: Icons.timelapse,
                  label: 'Uptime',
                  value: snapshot.uptime,
                ),
                _buildMetricCard(
                  context,
                  icon: Icons.group,
                  label: 'Clients',
                  value: '${snapshot.connectedClients}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSectionTitle('System Specs'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildMetricCard(
                  context,
                  icon: Icons.memory,
                  label: 'CPU',
                  value: '${snapshot.cpuModel}\n${snapshot.cpuCores} cores',
                ),
                _buildMetricCard(
                  context,
                  icon: Icons.developer_board,
                  label: 'Platform',
                  value:
                      '${snapshot.platform} ${snapshot.platformRelease}\n${snapshot.architecture}',
                ),
                _buildMetricCard(
                  context,
                  icon: Icons.code,
                  label: 'Python',
                  value: snapshot.pythonVersion,
                ),
                _buildMetricCard(
                  context,
                  icon: Icons.info_outline,
                  label: 'Kernel',
                  value: snapshot.platformVersion,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSectionTitle('Resource Usage'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _buildResourceBar(
                      context,
                      icon: Icons.speed,
                      label: 'CPU Usage',
                      value: snapshot.cpuUsagePercent ?? 0,
                      displayValue: _formatPercent(snapshot.cpuUsagePercent),
                    ),
                    const SizedBox(height: 16),
                    _buildResourceBar(
                      context,
                      icon: Icons.storage,
                      label: 'Memory',
                      value: snapshot.memoryTotalMb != null && snapshot.memoryTotalMb! > 0
                          ? (snapshot.memoryUsedMb ?? 0) / snapshot.memoryTotalMb!.toDouble() * 100
                          : 0,
                      displayValue: '${_formatMb(snapshot.memoryUsedMb)} / ${_formatMb(snapshot.memoryTotalMb)}',
                    ),
                    const SizedBox(height: 16),
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
            // Network Overview and Active Traffic hidden to save memory/resources
            const SizedBox(height: 16),
            _buildSectionTitle('Security & Sessions'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildModernStatCard(
                  context,
                  icon: Icons.security,
                  label: 'SSH SESSIONS',
                  value: '${snapshot.sshConnections}',
                  color: Colors.orange,
                ),
                _buildModernStatCard(
                  context,
                  icon: Icons.bolt,
                  label: 'TCP CONNS',
                  value: '${snapshot.activeTcpConnections}',
                  color: Colors.amber,
                ),
                _buildModernStatCard(
                  context,
                  icon: Icons.swap_horiz,
                  label: 'UDP CONNS',
                  value: '${snapshot.udpConnections}',
                  color: Colors.cyan,
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ],
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
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 16),
          // Battery Card Skeleton
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 24),
          _buildSkeletonSectionTitle(),
          const SizedBox(height: 12),
          // Metric Cards Row 1
          Row(
            children: [
              Expanded(child: _buildSkeletonMetricCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildSkeletonMetricCard()),
            ],
          ),
          const SizedBox(height: 24),
          _buildSkeletonSectionTitle(),
          const SizedBox(height: 12),
          // Resource usage card
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 24),
          _buildSkeletonSectionTitle(),
          const SizedBox(height: 12),
          // Grid-like metrics
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(
                4, (index) => _buildSkeletonMetricCard(width: 170)),
          ),
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
    final updatedText =
        DateFormat.yMMMd().add_Hms().format(snapshot.receivedAt.toLocal());

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
                if (widget.controller.isSocketConnected)
                  _PulseIndicator(color: Colors.blue),
              ],
            ),
            const SizedBox(height: 16),
            _buildSettingRow(
              context,
              icon: widget.controller.isSocketConnected
                  ? Icons.sync
                  : Icons.sync_disabled,
              label: 'Connection Status',
              value: widget.controller.statusMessage,
              trailing: widget.controller.isSocketConnected 
                  ? Text(
                      'Live',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            _buildSettingRow(
              context,
              icon: Icons.access_time,
              label: 'Last Snapshot',
              value: updatedText,
            ),
          ],
        ),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              child: Icon(icon),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Battery',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    batteryText,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    final color = percentage > 80
        ? Colors.red
        : percentage > 60
            ? Colors.orange
            : Colors.green;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Text(
                displayValue,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                height: 6,
                width: MediaQuery.of(context).size.width * (percentage / 100),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            baseColor.withOpacity(0.12),
            baseColor.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: baseColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: baseColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: baseColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.2),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  value,
                  key: ValueKey<String>(value),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
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

  Widget _buildMetricCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
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
}

class _PulseIndicator extends StatefulWidget {
  final Color color;
  const _PulseIndicator({required this.color});

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
          width: 8,
          height: 8,
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

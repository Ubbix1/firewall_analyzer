import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../widgets/connectivity_gate.dart';

import '../controllers/server_status_controller.dart';
import '../models/server_status_snapshot.dart';

class CloudStatusScreen extends StatefulWidget {
  final ServerStatusController controller;
  final VoidCallback onOpenSettings;

  const CloudStatusScreen({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  @override
  State<CloudStatusScreen> createState() => _CloudStatusScreenState();
}

class _CloudStatusScreenState extends State<CloudStatusScreen> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final snapshot = widget.controller.snapshot;
        final isLoading = widget.controller.isLoading;

        if (snapshot == null) {
          if (isLoading || widget.controller.isConnectingSocket) {
            return _buildSkeleton(context);
          }
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('Cloud data unavailable'),
                SizedBox(height: 4),
                Text('Connecting to official endpoint...', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          );
        }

        return ConnectivityGate(
          controller: widget.controller,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (widget.controller.isUsingCache || widget.controller.isOffline)
                _buildOfflineIndicator(context),
              _buildCloudStatusCard(context, snapshot),
              const SizedBox(height: 16),
              _buildDockerContainersSection(context, snapshot),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCloudStatusCard(
    BuildContext context,
    ServerStatusSnapshot snapshot,
  ) {
    if (snapshot.cloudStatus.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(
                Icons.cloud_off,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(
                'Cloud Status Unavailable',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'No cloud status data received yet',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cloud Status',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ...snapshot.cloudStatus.entries
                .where((entry) => entry.key != 'landing_page')
                .map(
              (entry) => _buildCloudStatusItem(context, entry.key, entry.value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudStatusItem(
    BuildContext context,
    String service,
    String status,
  ) {
    final isActive = status.toLowerCase() == 'active' ||
        status.toLowerCase() == 'ok' ||
        status.toLowerCase() == 'live';
    final icon = isActive ? Icons.circle : Icons.cancel;
    final color = isActive ? Colors.green : Colors.red;

    final displayName = service
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              word[0].toUpperCase() + (word.length > 1 ? word.substring(1) : ''),
        )
        .join(' ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDockerContainersSection(
    BuildContext context,
    ServerStatusSnapshot snapshot,
  ) {
    if (snapshot.dockerContainers.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Docker Containers',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'No containers found',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Docker Containers',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ...snapshot.dockerContainers.map(
              (container) => _buildDockerContainerRow(context, container),
            ),
          ],
        ),
      ),
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
        padding: const EdgeInsets.all(12),
        children: [
          // Cloud Status Card Skeleton
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 16),
          // Docker Containers Header
          Container(
            width: 150,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          // Docker Containers Skeleton
          ...List.generate(
            3,
            (index) => Container(
              height: 70,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDockerContainerRow(
    BuildContext context,
    Map<String, dynamic> container,
  ) {
    final name = _containerValue(container, 'name', fallback: 'Unknown');
    final image = _containerValue(container, 'image');
    final status = _containerValue(container, 'status', fallback: 'Unknown');
    final state = _containerValue(container, 'state', fallback: 'unknown');
    final isRunning = _isContainerRunning(state: state, status: status);
    final isUnknown = state.toLowerCase() == 'unknown' && status == 'Unknown';
    final statusColor = isRunning
        ? Colors.green
        : isUnknown
            ? Colors.grey
            : Colors.orange;
    final statusIcon = isRunning
        ? Icons.circle
        : isUnknown
            ? Icons.help_outline
            : Icons.pause_circle;
    final statusLabel = isRunning
        ? 'Running'
        : isUnknown
            ? 'Unknown'
            : 'Stopped';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (image.isNotEmpty)
                  Text(
                    image,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                statusLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                status,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _containerValue(
    Map<String, dynamic> container,
    String key, {
    String fallback = '',
  }) {
    final value = container[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  bool _isContainerRunning({
    required String state,
    required String status,
  }) {
    final normalizedState = state.toLowerCase().trim();
    final normalizedStatus = status.toLowerCase().trim();
    return normalizedState == 'running' || normalizedStatus.startsWith('up ');
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isOffline ? Colors.red.withOpacity(0.9) : Colors.orange.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ),
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
                  : 'Viewing cached cloud metrics (Updated $timeAgo)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

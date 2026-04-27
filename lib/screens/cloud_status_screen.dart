import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

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
          if (isLoading) {
            return _buildSkeleton(context);
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_queue,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Use the top-right settings icon to open Server Settings, connect to your endpoint, and load cloud status.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
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

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildCloudStatusCard(context, snapshot),
            const SizedBox(height: 16),
            _buildDockerContainersSection(context, snapshot),
          ],
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
            ...snapshot.cloudStatus.entries.map(
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            status,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (image.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    image,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            statusLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
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
}

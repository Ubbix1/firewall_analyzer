    import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/server_status_controller.dart';
import 'whitelist_screen.dart';
import 'server_settings/about/about_screen.dart';
import 'server_settings/theme/theme_settings_screen.dart';

class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({
    super.key,
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ServerStatusController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(
              widget.controller.loadHttpSnapshot(
                onMessage: _showSnackBar,
              ),
            ),
          ),
        ],
      ),

      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final currentUri = controller.currentUri;
          final snapshot = controller.snapshot;

          final updatedText = snapshot == null
              ? 'No snapshot yet'
              : DateFormat.yMMMd()
                  .add_Hms()
                  .format(snapshot.receivedAt.toLocal());

          return Column(
            children: [
              /// STATUS BAR
              Container(
                width: double.infinity,
                color: controller.isSocketConnected
                    ? Colors.green
                    : Colors.red,
                padding: const EdgeInsets.all(12),
                child: Text(
                  controller.isSocketConnected
                      ? 'Server Connected'
                      : 'Server Disconnected',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              /// MAIN CONTENT
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    /// ENDPOINT CARD
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Endpoint',
                              style:
                                  Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),

                            TextField(
                              controller: controller.urlController,
                              decoration: const InputDecoration(
                                labelText: 'Shared Server URL',
                                hintText: 'wss://analyzer.plexaur.com',
                                helperText:
                                    'Use your shared server domain here.',
                                border: OutlineInputBorder(),
                              ),
                            ),

                            const SizedBox(height: 12),

                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: controller.isLoading ||
                                          controller.isConnectingSocket
                                      ? null
                                      : () => unawaited(
                                            controller.connectAndSync(
                                              onMessage: _showSnackBar,
                                            ),
                                          ),
                                  icon: const Icon(Icons.refresh),
                                  label: Text(
                                    snapshot == null
                                        ? 'Load Status'
                                        : 'Reconnect',
                                  ),
                                ),

                                OutlinedButton.icon(
                                  onPressed:
                                      controller.isLoading || currentUri == null
                                          ? null
                                          : () => unawaited(
                                                controller.loadHttpSnapshot(
                                                  onMessage: _showSnackBar,
                                                ),
                                              ),
                                  icon: const Icon(
                                      Icons.cloud_download_outlined),
                                  label: const Text('HTTP Refresh'),
                                ),

                                ElevatedButton.icon(
                                  onPressed: controller.isSocketConnected
                                      ? () => unawaited(
                                          controller.disconnect())
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.error,
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .onError,
                                  ),
                                  icon: const Icon(Icons.link_off),
                                  label: const Text('Disconnect'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    /// STATUS CARD
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connection Status',
                              style:
                                  Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),

                            _buildSettingRow(
                              context,
                              icon: controller.isSocketConnected
                                  ? Icons.sync
                                  : Icons.sync_disabled,
                              label: 'Live Sync',
                              value: controller.statusMessage,
                            ),

                            const SizedBox(height: 10),

                            _buildSettingRow(
                              context,
                              icon: snapshot != null
                                  ? Icons.cloud_done
                                  : Icons.cloud_off,
                              label: 'HTTP Snapshot',
                              value: snapshot == null ? 'Pending' : 'Loaded',
                            ),

                            const SizedBox(height: 10),

                            _buildSettingRow(
                              context,
                              icon: Icons.access_time,
                              label: 'Updated',
                              value: updatedText,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    /// SSH MONITOR CARD
                    if (snapshot != null) _buildSshMonitorCard(context, snapshot),
                    if (snapshot != null) const SizedBox(height: 16),

                    /// SECURITY CARD
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Security',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Manage trusted IPs and whitelist to prevent false positives.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const WhitelistScreen(),
                                ),
                              ),
                              icon: const Icon(Icons.shield),
                              label: const Text('Manage Whitelist'),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    /// PREFERENCES CARD
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preferences',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.palette_outlined),
                              title: const Text('Theme Settings'),
                              subtitle: const Text('Customize application appearance'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ThemeSettingsScreen(
                                    currentMode: widget.themeMode,
                                    onThemeChanged: widget.onThemeModeChanged,
                                  ),
                                ),
                              ),
                            ),
                            const Divider(),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.info_outline),
                              title: const Text('About'),
                              subtitle: const Text('Version info and creator details'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AboutScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              Text(value),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSshMonitorCard(BuildContext context, snapshot) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.security, color: Colors.indigo),
                const SizedBox(width: 8),
                Text(
                  'SSH Monitor',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Active SSH Sessions',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (snapshot.activeSshSessions.isEmpty)
              const Text('No active SSH sessions.')
            else
              ...snapshot.activeSshSessions.map((session) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person, color: Colors.green),
                  title: Text(session['user'] ?? 'Unknown User'),
                  subtitle: Text('IP: ${session['ip']} | TTY: ${session['tty']}'),
                  trailing: Text(session['connectedAt'] ?? '', style: const TextStyle(fontSize: 12)),
                );
              }),
            const Divider(),
            Text(
              'Recent Bot Attempts (Auth Logs)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (snapshot.recentSshAttempts.isEmpty)
              const Text('No recent auth logs found.')
            else
              ...snapshot.recentSshAttempts.take(10).map((attempt) {
                final isFailed = attempt['status'] == 'FAILED';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isFailed ? Icons.warning : Icons.check_circle,
                    color: isFailed ? Colors.red : Colors.green,
                  ),
                  title: Text('User: ${attempt['user']}'),
                  subtitle: Text('IP: ${attempt['ip']}\nTime: ${attempt['timestamp']}'),
                  isThreeLine: true,
                );
              }),
          ],
        ),
      ),
    );
  }
}

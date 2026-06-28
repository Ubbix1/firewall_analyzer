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
                    : (controller.isConnectingSocket || controller.isLoading
                        ? Colors.orange
                        : Colors.red),
                padding: const EdgeInsets.all(12),
                child: Text(
                  controller.isSocketConnected
                      ? 'System Online'
                      : (controller.isConnectingSocket || controller.isLoading
                          ? 'Synchronizing Metrics...'
                          : 'Endpoint Unreachable'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
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
                               'Permanent Endpoint',
                               style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                 color: Theme.of(context).hintColor,
                                 fontWeight: FontWeight.bold,
                               ),
                             ),
                             const SizedBox(height: 8),
                             TextField(
                               controller: controller.urlController,
                               readOnly: true,
                               style: TextStyle(
                                 fontWeight: FontWeight.bold,
                                 fontFamily: 'monospace',
                                 color: Theme.of(context).colorScheme.onSurface,
                               ),
                               decoration: InputDecoration(
                                 prefixIcon: const Icon(Icons.cloud_done, color: Colors.blue),
                                 filled: true,
                                 fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                                 border: const OutlineInputBorder(),
                                 hintText: 'wss://analyzer.plexaur.com',
                               ),
                             ),
                            const SizedBox(height: 12),

                            const SizedBox(height: 8),
                            Text(
                              'The system automatically synchronizes with the official security endpoint in real-time.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
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
                              label: 'Last Response',
                              value: updatedText,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),


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

}

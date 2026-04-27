import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/home_screen_controller.dart';
import '../controllers/server_status_controller.dart';
import '../models/firewall_log.dart';
import '../models/saved_suspicious_log_entry.dart';
import '../screens/live_packet_screen.dart';
import '../screens/log_selection_dialog.dart';
import '../screens/server_settings_screen.dart';
import '../screens/server_settings/about/about_screen.dart';
import '../screens/server_settings/theme/theme_settings_screen.dart';
import '../screens/server_status_screen.dart';
import '../screens/threat_map_screen.dart';
import '../screens/cloud_status_screen.dart';
import '../screens/user_client_screen.dart';
import '../screens/unified_saved_screen.dart';
import '../controllers/live_controller.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/geo_ip_service.dart';
import '../services/log_analysis_service.dart';
import '../widgets/dashboard_dialog.dart';
import '../widgets/filter_sort_dialog.dart';
import '../widgets/log_list_view.dart';
import '../widgets/recent_files_view.dart';

class HomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final DatabaseHelper? databaseHelper;
  final GeoIpService? geoIpService;
  final ExportService? exportService;
  final bool skipInitialLoad;

  const HomeScreen({
    super.key,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.databaseHelper,
    this.geoIpService,
    this.exportService,
    this.skipInitialLoad = false,
  });

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final HomeScreenController _ctrl;
  late final ServerStatusController _serverStatusController;
  late final LiveController _liveController;
  int _selectedIndex = 0;

  final List<bool> _initializedTabs = [true, false, false, false, false];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serverStatusController = ServerStatusController();
    _ctrl = HomeScreenController(
      databaseHelper: widget.databaseHelper,
      geoIpService: widget.geoIpService,
      exportService: widget.exportService,
      serverStatusController: _serverStatusController,
      skipInitialLoad: widget.skipInitialLoad,
    );
    _liveController = LiveController();

    // Defer controller initialization until after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_ctrl.init());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_ctrl.clearLogs()); // Final cleanup
    _ctrl.dispose();
    _serverStatusController.dispose();
    _liveController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached || state == AppLifecycleState.paused) {
      // Clear all local logs when exiting or backgrounding to keep the app clean
      unawaited(_ctrl.clearLogs());
    }
  }

  void _onItemTapped(int index) {
    if (index >= 0 && index < _initializedTabs.length) {
      _initializedTabs[index] = true;
    }
    setState(() => _selectedIndex = index);
    
    // Update live controller activity
    _liveController.setActive(index == 2);
  }

  String _pageTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Logs';
      case 1:
        return 'Saved';
      case 2:
        return 'Live';
      case 3:
        return 'Server';
      case 4:
        return 'Cloud';
      default:
        return 'Firewall Log Analyzer';
    }
  }

  void _openServerSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServerSettingsScreen(
          controller: _serverStatusController,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged ?? (_) {},
        ),
      ),
    );
  }

  void _openUserClient() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            UserClientScreen(controller: _serverStatusController),
      ),
    );
  }

  void _cycleThemeMode() {
    late final ThemeMode next;
    switch (widget.themeMode) {
      case ThemeMode.system:
        next = ThemeMode.light;
        break;
      case ThemeMode.light:
        next = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        next = ThemeMode.system;
        break;
    }
    widget.onThemeModeChanged?.call(next);
  }

  IconData _themeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light theme';
      case ThemeMode.dark:
        return 'Dark theme';
      case ThemeMode.system:
        return 'System theme';
    }
  }



  void _showAnalyzeDialog(FirewallLog log) {
    final analysis = LogAnalysisService.analyze(log);
    final findings = analysis.findings.isEmpty
        ? 'No suspicious patterns detected.'
        : analysis.findings.join('\n\n');

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log Analysis'),
        content: SingleChildScrollView(
          child: Text(
            'Risk: ${analysis.riskLevel} (${analysis.severityScore})\n\n$findings',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportLogs(bool asPdf) async {
    final result = await _ctrl.exportLogs(asPdf: asPdf);
    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No filtered logs available to export.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Exported ${result.exportedLogs} logs to ${result.filePath}',
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;

    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        if (_ctrl.isMemoryCritical) {
          return Scaffold(
            body: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              color: Colors.red.shade900,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.report_problem, color: Colors.white, size: 80),
                  const SizedBox(height: 24),
                  const Text(
                    'EMERGENCY SHUTDOWN',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _ctrl.serverMemoryWarning ?? 'Server memory usage is critically high.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    'Waiting for server to recover...',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }

        final body = Column(
          children: [
            if (_ctrl.serverMemoryWarning != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: _ctrl.isMemoryCritical ? Colors.red.shade900 : Colors.orange.shade900,
                child: Row(
                  children: [
                    Icon(
                      _ctrl.isMemoryCritical ? Icons.report_problem : Icons.warning_amber,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _ctrl.serverMemoryWarning!,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  // Tab 0: Logs
                  LogListView(
                    controller: _ctrl,
                    onShowDashboard: () => showDashboardDialog(context, _ctrl),
                    onShowFilterSort: () => showFilterSortDialog(context, _ctrl),
                    onShowAnalyzeDialog: _showAnalyzeDialog,
                    onShowComparison: (ctx) => showDialog(
                      context: ctx,
                      builder: (_) => LogSelectionDialog(
                        currentLogs: _ctrl.logs,
                        recentFiles: _ctrl.recentFiles,
                        databaseHelper: DatabaseHelper(),
                      ),
                    ),
                  ),
                  
                  // Tab 1: Saved
                  _initializedTabs[1]
                      ? UnifiedSavedScreen(
                          controller: _ctrl,
                          onLoadIntoLogs: (SavedSuspiciousLogEntry entry) {
                            _ctrl.loadSavedSuspiciousLogIntoLogs(entry);
                            setState(() => _selectedIndex = 0);
                          },
                        )
                      : const SizedBox.shrink(),


                  // Tab 2: Live
                  _initializedTabs[2]
                      ? LivePacketScreen(controller: _liveController)
                      : const SizedBox.shrink(),

                  // Tab 3: Server
                  _initializedTabs[3]
                      ? ServerStatusScreen(
                          controller: _serverStatusController,
                          onOpenSettings: _openServerSettings,
                        )
                      : const SizedBox.shrink(),

                  // Tab 4: Cloud
                  _initializedTabs[4]
                      ? CloudStatusScreen(
                          controller: _serverStatusController,
                          onOpenSettings: _openServerSettings,
                        )
                      : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        );

        final appBarActions = <Widget>[
          // ── logs page specific actions ─────────────────────────────────────
          if (_selectedIndex == 0) ...[
            if (_ctrl.isSearching) ...[
              IconButton(
                tooltip: 'Filter & Sort',
                onPressed: () => showFilterSortDialog(context, _ctrl),
                icon: const Icon(Icons.filter_list),
              ),
              IconButton(
                tooltip: 'Close search',
                onPressed: _ctrl.toggleSearch,
                icon: const Icon(Icons.close),
              ),
            ] else ...[
              IconButton(
                tooltip: 'Search logs',
                onPressed: _ctrl.toggleSearch,
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'Dashboard',
                onPressed: () => showDashboardDialog(context, _ctrl),
                icon: const Icon(Icons.dashboard_customize),
              ),
              IconButton(
                tooltip: 'Upload log file',
                onPressed: () => unawaited(_ctrl.uploadLogs()),
                icon: const Icon(Icons.upload_file),
              ),
            ],
          ],

          // ── saved page specific actions ────────────────────────────────────
          if (_selectedIndex == 1) ...[
            IconButton(
              tooltip: 'Compare logs',
              onPressed: _ctrl.recentFiles.length >= 2
                  ? () => showDialog(
                        context: context,
                        builder: (_) => LogSelectionDialog(
                          currentLogs: _ctrl.logs,
                          recentFiles: _ctrl.recentFiles,
                          databaseHelper: DatabaseHelper(),
                        ),
                      )
                  : null,
              icon: const Icon(Icons.compare),
            ),
          ],

          // ── server page specific actions ────────────────────────────────────
          if (_selectedIndex == 3) ...[
            IconButton(
              tooltip: 'User clients',
              onPressed: _openUserClient,
              icon: const Icon(Icons.group),
            ),
          ],

          // ── global settings menu ───────────────────────────────────────────
          PopupMenuButton<String>(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onSelected: (value) {
              switch (value) {
                case 'server_settings':
                  _openServerSettings();
                  break;
                case 'export_csv':
                  unawaited(_exportLogs(false));
                  break;
                case 'export_pdf':
                  unawaited(_exportLogs(true));
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'server_settings',
                child: Row(
                  children: [
                    Icon(Icons.dns, size: 18),
                    const SizedBox(width: 12),
                    Text('Server Settings'),
                  ],
                ),
              ),
              if (_selectedIndex == 0) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'export_csv',
                  child: Row(
                    children: [
                      Icon(Icons.file_download, size: 18),
                      const SizedBox(width: 12),
                      Text('Export CSV'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'export_pdf',
                  child: Row(
                    children: [
                      Icon(Icons.picture_as_pdf, size: 18),
                      const SizedBox(width: 12),
                      Text('Export PDF'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ];

        const navDestinations = <(IconData, String)>[
          (Icons.list, 'Logs'),
          (Icons.history, 'Saved'),
          (Icons.wifi_tethering, 'Live'),
          (Icons.battery_6_bar, 'Server'),
          (Icons.cloud, 'Cloud'),
        ];

        Widget appBarTitle;
        if (_selectedIndex == 0 && _ctrl.isSearching) {
          appBarTitle = TextField(
            controller: _ctrl.searchController,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Search logs...',
              hintStyle: TextStyle(color: Colors.white70),
              border: InputBorder.none,
            ),
          );
        } else {
          appBarTitle = Text(_pageTitle());
        }

        if (isWide) {
          return Scaffold(
            appBar: AppBar(
              title: appBarTitle,
              actions: appBarActions,
            ),
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (idx) {
                    if (_ctrl.isSearching) _ctrl.toggleSearch();
                    _onItemTapped(idx);
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: navDestinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.$1),
                            label: Text(d.$2),
                          ))
                      .toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: appBarTitle,
            actions: appBarActions,
          ),
          body: body,
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            items: navDestinations
                .map((d) => BottomNavigationBarItem(
                      icon: Icon(d.$1),
                      label: d.$2,
                    ))
                .toList(),
            currentIndex: _selectedIndex,
            selectedItemColor: Colors.blue,
            onTap: (idx) {
              if (_ctrl.isSearching) _ctrl.toggleSearch();
              _onItemTapped(idx);
            },
          ),
        );
      },
    );
  }
}

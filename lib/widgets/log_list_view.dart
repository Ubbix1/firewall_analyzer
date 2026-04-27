import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:shimmer/shimmer.dart';

import '../constants/server_log_sources.dart';
import '../controllers/home_screen_controller.dart';
import '../models/firewall_log.dart';
import '../services/log_analysis_service.dart';
import 'log_entry_tile.dart';

/// The full-screen "Logs" tab content.
/// Reads from [HomeScreenController] via [ListenableBuilder].
class LogListView extends StatefulWidget {
  final HomeScreenController controller;
  final VoidCallback onShowDashboard;
  final VoidCallback onShowFilterSort;
  final void Function(FirewallLog) onShowAnalyzeDialog;

  final void Function(BuildContext) onShowComparison;

  const LogListView({
    super.key,
    required this.controller,
    required this.onShowDashboard,
    required this.onShowFilterSort,
    required this.onShowAnalyzeDialog,

    required this.onShowComparison,
  });

  @override
  State<LogListView> createState() => _LogListViewState();
}

class _LogListViewState extends State<LogListView> {
  final ScrollController _scrollController = ScrollController();

  HomeScreenController get ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter >= 300) return;

    if (ctrl.activeServerLogSourceId != null) {
      if (ctrl.hasMoreRemoteLogs && !ctrl.isLoadingMoreRemoteLogs) {
        unawaited(ctrl.loadMoreServerLogs().catchError((e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Unable to load more server logs: $e')),
            );
          }
        }));
      }
      return;
    }

    if (ctrl.hasMoreLogs) {
      ctrl.loadMoreLocalLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final suspiciousCount =
            ctrl.logs.where(LogAnalysisService.isSuspicious).length;
        ServerLogSource? selectedSource;
        for (final s in serverLogSources) {
          if (s.id == ctrl.activeServerLogSourceId) {
            selectedSource = s;
            break;
          }
        }

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ctrl.isLoading || ctrl.isEnriching || ctrl.loadingProgress > 0)
                LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  value: (ctrl.loadingProgress > 0 && ctrl.loadingProgress < 1.0)
                      ? ctrl.loadingProgress
                      : null,
                ),

              // ── Stats Dashboard ───────────────────────────────────────────
              _buildStatsDashboard(context, suspiciousCount),

              // ── Control Panel ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildLogSourceDropdown(context, selectedSource),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _buildViewFilterDropdown(context),
                    ),
                    const SizedBox(width: 8),
                    if (ctrl.isLoading)
                      IconButton(
                        onPressed: () => ctrl.stopLoading(),
                        icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                        tooltip: 'Stop loading',
                      )
                    else
                      IconButton(
                        onPressed: () => ctrl.clearLogs(),
                        icon: const Icon(Icons.delete_sweep_outlined),
                        tooltip: 'Clear logs',
                      ),
                  ],
                ),
              ),

              if (ctrl.activeServerLogSourceId != null)
                _buildSyncStatus(context, selectedSource),

              // ── Active Filters ────────────────────────────────────────────
              _buildActiveFilters(context, selectedSource, suspiciousCount),

              // ── Log list ──────────────────────────────────────────────────
              Expanded(
                child: ctrl.isLoading && ctrl.logs.isEmpty
                    ? _buildSkeletonLoader(context)
                    : ctrl.filteredLogs.isEmpty
                        ? _buildEmptyState(context)
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: ctrl.visibleLogs.length + (ctrl.hasMoreLogs ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= ctrl.visibleLogs.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }

                              final log = ctrl.visibleLogs[index];
                              return LogEntryTile(
                                log: log,
                                isSuspiciousSaved: ctrl.isSuspiciousSaved(log),
                                onDelete: () async {
                                  final logId = log.id;
                                  if (logId == null) return;
                                  await ctrl.removeLog(logId);
                                },
                                onAnalyze: () => widget.onShowAnalyzeDialog(log),
                                onSaveSuspicious: LogAnalysisService.isSuspicious(log)
                                    ? () async => ctrl.saveSuspiciousLog(log)
                                    : null,
                                onLongPress: LogAnalysisService.isSuspicious(log)
                                    ? () async {
                                        await _confirmSaveSuspiciousLog(context, log);
                                      }
                                    : null,
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsDashboard(BuildContext context, int suspiciousCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Security Overview',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatCard(
                  context,
                  'Total Logs',
                  ctrl.logs.length.toString(),
                  Icons.article_outlined,
                  Colors.blue,
                ),
                _buildStatCard(
                  context,
                  'Suspicious',
                  suspiciousCount.toString(),
                  Icons.security_update_warning_outlined,
                  Colors.redAccent,
                ),
                _buildStatCard(
                  context,
                  'Filtered',
                  ctrl.filteredLogs.length.toString(),
                  Icons.filter_list_alt,
                  Colors.orange,
                ),
                _buildStatCard(
                  context,
                  'Visible',
                  ctrl.visibleLogs.length.toString(),
                  Icons.visibility_outlined,
                  Colors.green,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogSourceDropdown(BuildContext context, ServerLogSource? selectedSource) {
    return DropdownButtonFormField<String>(
      key: ValueKey(ctrl.activeServerLogSourceId),
      value: selectedSource?.id,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Source',
        prefixIcon: const Icon(Icons.dns_outlined, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      items: serverLogSources.map((source) => DropdownMenuItem(
        value: source.id,
        child: Text(
          source.label, 
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      )).toList(),
      onChanged: (value) async {
        if (value == null) return;
        final messenger = ScaffoldMessenger.of(context);
        for (final source in serverLogSources) {
          if (source.id == value) {
            final err = await ctrl.loadServerLogSource(source);
            if (err != null) {
              messenger.showSnackBar(SnackBar(content: Text(err)));
            }
            break;
          }
        }
      },
    );
  }

  Widget _buildViewFilterDropdown(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: ctrl.logViewFilter,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'View',
        prefixIcon: const Icon(Icons.auto_awesome_mosaic_outlined, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      items: HomeScreenController.logViewOptions.map((opt) => DropdownMenuItem(
        value: opt,
        child: Text(
          opt, 
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      )).toList(),
      onChanged: (value) {
        if (value != null) ctrl.setLogViewFilter(value);
      },
    );
  }

  Widget _buildSyncStatus(BuildContext context, ServerLogSource? selectedSource) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (ctrl.isLoading || ctrl.isLoadingMoreRemoteLogs)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.sync_alt, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ctrl.loadingStatusMessage ?? (ctrl.isLoading ? 'Syncing records...' : 'Showing records from ${selectedSource?.label}.'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveFilters(BuildContext context, ServerLogSource? selectedSource, int suspiciousCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (ctrl.activeFilePath != null)
            Chip(
              label: Text(path.basename(ctrl.activeFilePath!), style: const TextStyle(fontSize: 11)),
              avatar: const Icon(Icons.description_outlined, size: 14),
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
            ),
          if (ctrl.statusFilter != null)
            InputChip(
              label: Text('Status ${ctrl.statusFilter}', style: const TextStyle(fontSize: 11)),
              onDeleted: () => ctrl.setStatusFilter(null),
              deleteIcon: const Icon(Icons.cancel, size: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            ctrl.logs.isEmpty
                ? (ctrl.activeServerLogSourceId == null ? 'Select a log source to begin' : 'No records found')
                : 'No logs match current filters',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }


  Future<void> _confirmSaveSuspiciousLog(
      BuildContext context, FirewallLog log) async {
    if (!LogAnalysisService.isSuspicious(log)) return;
    final messenger = ScaffoldMessenger.of(context);
    final shouldSave = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Save Suspicious Activity'),
            content: const Text(
              'Save this suspicious log to the Saved page for quick access later?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldSave) {
      await ctrl.saveSuspiciousLog(log);
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Saved to recent suspicious activity.')),
        );
      }
    }
  }

  Widget _buildSkeletonLoader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.builder(
        itemCount: 10,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 150,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

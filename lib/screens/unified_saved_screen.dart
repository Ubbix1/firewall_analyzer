import 'package:flutter/material.dart';
import '../controllers/home_screen_controller.dart';
import '../models/saved_suspicious_log_entry.dart';
import './saved_analysis_screen.dart';
import '../widgets/recent_files_view.dart';

class UnifiedSavedScreen extends StatelessWidget {
  final HomeScreenController controller;
  final void Function(SavedSuspiciousLogEntry) onLoadIntoLogs;

  const UnifiedSavedScreen({
    super.key,
    required this.controller,
    required this.onLoadIntoLogs,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.history), text: 'Log Activity'),
              Tab(icon: Icon(Icons.wifi_tethering), text: 'Live Snapshots'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                RecentFilesView(
                  controller: controller,
                  onLoadIntoLogs: onLoadIntoLogs,
                ),
                const SavedAnalysisScreen(isEmbedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

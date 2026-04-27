import 'package:flutter/material.dart';

import '../models/firewall_log.dart';
import '../models/recent_file_entry.dart';
import '../services/database_helper.dart';
import 'log_comparison_screen.dart';

class LogSelectionDialog extends StatefulWidget {
  final List<FirewallLog> currentLogs;
  final List<RecentFileEntry> recentFiles;
  final DatabaseHelper databaseHelper;

  const LogSelectionDialog({
    super.key,
    required this.currentLogs,
    required this.recentFiles,
    required this.databaseHelper,
  });

  @override
  State<LogSelectionDialog> createState() => _LogSelectionDialogState();
}

class _LogSelectionDialogState extends State<LogSelectionDialog> {
  RecentFileEntry? _selectedFileA;
  RecentFileEntry? _selectedFileB;
  List<FirewallLog>? _logsA;
  List<FirewallLog>? _logsB;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-select current logs as first option
    if (widget.currentLogs.isNotEmpty && widget.recentFiles.isNotEmpty) {
      _selectedFileA = widget.recentFiles.first;
    }
  }

  Future<void> _loadLogsForFile(RecentFileEntry file, bool isFileA) async {
    // In a real implementation, you would load logs from the file
    // For now, we'll just use the current logs if it's the current file
    setState(() {
      _isLoading = true;
    });

    try {
      // Simulating file load - in reality you'd read from disk
      // For now, use current logs as a placeholder
      final logs = widget.currentLogs;

      setState(() {
        if (isFileA) {
          _logsA = logs;
        } else {
          _logsB = logs;
        }
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const canCompare =
        'Select two different log files to compare. You can also compare a saved log file with the currently loaded logs.';

    return AlertDialog(
      title: const Text('Select Logs to Compare'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                canCompare,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text(
                'First Log File',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildFileSelector(true),
              const SizedBox(height: 16),
              const Text(
                'Second Log File',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildFileSelector(false),
              if (_isLoading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _canCompare() ? _startComparison : null,
          child: const Text('Compare'),
        ),
      ],
    );
  }

  Widget _buildFileSelector(bool isFileA) {
    final selectedFile = isFileA ? _selectedFileA : _selectedFileB;

    return DropdownButtonFormField<RecentFileEntry>(
      value: selectedFile,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: 'Select a file',
        suffixIcon: selectedFile != null
            ? Tooltip(
                message: selectedFile.path,
                child: const Icon(Icons.info),
              )
            : null,
      ),
      items: widget.recentFiles.map((file) {
        return DropdownMenuItem(
          value: file,
          child: Text(
            '${file.fileName} (${file.logCount} logs)',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (file) {
        setState(() {
          if (isFileA) {
            _selectedFileA = file;
            if (file != null) {
              _loadLogsForFile(file, true);
            }
          } else {
            _selectedFileB = file;
            if (file != null) {
              _loadLogsForFile(file, false);
            }
          }
        });
      },
    );
  }

  bool _canCompare() {
    return _selectedFileA != null &&
        _selectedFileB != null &&
        _selectedFileA != _selectedFileB &&
        _logsA != null &&
        _logsB != null;
  }

  void _startComparison() {
    if (!_canCompare()) return;

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LogComparisonScreen(
          logsA: _logsA!,
          logsB: _logsB!,
          fileNameA: _selectedFileA!.fileName,
          fileNameB: _selectedFileB!.fileName,
        ),
      ),
    );
  }
}

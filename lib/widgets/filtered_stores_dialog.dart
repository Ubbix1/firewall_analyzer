import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';

import '../services/filtered_data_store_service.dart';

class FilteredStoresDialog extends StatefulWidget {
  const FilteredStoresDialog({super.key});

  @override
  State<FilteredStoresDialog> createState() => _FilteredStoresDialogState();
}

class _FilteredStoresDialogState extends State<FilteredStoresDialog> {
  List<File> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    final files = await FilteredDataStoreService.getStoredFiles();
    setState(() {
      _files = files;
      _isLoading = false;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Saved JSON Stores'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _files.isEmpty
                ? const Center(child: Text('No saved JSON stores found.'))
                : ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final stat = file.statSync();
                      final date = DateFormat('MMM d, yyyy HH:mm').format(stat.modified);
                      final size = _formatBytes(stat.size);

                      return ListTile(
                        leading: const Icon(Icons.data_object),
                        title: Text(path.basename(file.path)),
                        subtitle: Text('$date  •  $size'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await FilteredDataStoreService.deleteFile(file);
                            _loadFiles();
                          },
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        if (_files.isNotEmpty)
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear All Stores'),
                  content: const Text('Are you sure you want to delete all saved JSON stores?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear All')),
                  ],
                ),
              );
              if (confirm == true) {
                await FilteredDataStoreService.clearAll();
                _loadFiles();
              }
            },
            child: const Text('Clear All'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

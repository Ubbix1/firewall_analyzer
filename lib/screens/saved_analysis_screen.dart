import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/live_packet_record.dart';
import '../services/saved_analysis_service.dart';
import '../services/log_analysis_service.dart';

class SavedAnalysisScreen extends StatefulWidget {
  final bool isEmbedded;
  const SavedAnalysisScreen({super.key, this.isEmbedded = false});

  @override
  State<SavedAnalysisScreen> createState() => _SavedAnalysisScreenState();
}

class _SavedAnalysisScreenState extends State<SavedAnalysisScreen> {
  List<SavedAnalysisFile> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    final files = await SavedAnalysisService.getAllSavedAnalysis();
    setState(() {
      _files = files..sort((a, b) => b.savedAt.compareTo(a.savedAt));
      _isLoading = false;
    });
  }

  Future<void> _deleteFile(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Analysis'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SavedAnalysisService.deleteAnalysis(name);
      _loadFiles();
    }
  }

  void _viewFile(SavedAnalysisFile file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnalysisDetailScreen(file: file),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _files.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_open, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No saved analysis files found.'),
                    Text('Hold "Suspicious" chip for 3s in Live view to save.'),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _files.length,
                padding: const EdgeInsets.all(12),
                itemBuilder: (context, index) {
                  final file = _files[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: Text(
                        file.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${file.packets.length} packets  •  ${DateFormat.yMMMd().add_jm().format(file.savedAt)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteFile(file.name),
                      ),
                      onTap: () => _viewFile(file),
                    ),
                  );
                },
              );

    if (widget.isEmbedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Suspicious Analysis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFiles,
          ),
        ],
      ),
      body: body,
    );
  }
}

class AnalysisDetailScreen extends StatelessWidget {
  final SavedAnalysisFile file;

  const AnalysisDetailScreen({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file.name),
            Text(
              '${file.packets.length} Packets Analyzed',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: ListView.builder(
        itemCount: file.packets.length,
        itemBuilder: (context, index) {
          final packet = file.packets[index];
          final analysis = LogAnalysisService.analyze(packet.log);
          
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: analysis.riskLevel == 'Critical' ? Colors.red : Colors.orange,
                child: const Icon(Icons.security, color: Colors.white, size: 16),
              ),
              title: Text(
                packet.log.ipAddress,
                style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${analysis.riskLevel} (${analysis.severityScore})  •  ${DateFormat.jms().format(packet.receivedAt)}',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Raw Packet:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: SelectableText(
                          packet.rawPacket,
                          style: const TextStyle(fontFamily: 'Courier', fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Findings:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      ...analysis.findings.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $f'),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

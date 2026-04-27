import 'package:flutter/material.dart';

import '../services/whitelist_service.dart';

class WhitelistScreen extends StatefulWidget {
  const WhitelistScreen({super.key});

  @override
  State<WhitelistScreen> createState() => _WhitelistScreenState();
}

class _WhitelistScreenState extends State<WhitelistScreen> {
  final _ipController = TextEditingController();
  final _descriptionController = TextEditingController();
  late Future<Map<String, String?>> _whitelistFuture;

  @override
  void initState() {
    super.initState();
    _loadWhitelist();
  }

  void _loadWhitelist() {
    _whitelistFuture = WhitelistService.getAllWhitelist();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addToWhitelist() async {
    final ip = _ipController.text.trim();
    final description = _descriptionController.text.trim();

    if (ip.isEmpty) {
      _showSnackBar('Please enter an IP address');
      return;
    }

    try {
      await WhitelistService.addToWhitelist(
        ip,
        description: description.isNotEmpty ? description : null,
      );
      _ipController.clear();
      _descriptionController.clear();
      setState(() {
        _loadWhitelist();
      });
      _showSnackBar('Added $ip to whitelist');
    } catch (e) {
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _removeFromWhitelist(String ip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Whitelist'),
        content: Text('Remove $ip from whitelist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await WhitelistService.removeFromWhitelist(ip);
      setState(() {
        _loadWhitelist();
      });
      _showSnackBar('Removed $ip from whitelist');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trusted IPs Whitelist'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Trusted IP',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'IP Address',
                      hintText: '192.168.29.77',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'e.g., Server, Laptop, Router',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _addToWhitelist,
                    icon: const Icon(Icons.add),
                    label: const Text('Add to Whitelist'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Whitelisted IPs',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, String?>>(
            future: _whitelistFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}'),
                );
              }

              final whitelist = snapshot.data ?? {};

              if (whitelist.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          const Text('No whitelisted IPs yet'),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () async {
                              await WhitelistService.addCommonInternalRanges();
                              setState(() {
                                _loadWhitelist();
                              });
                              _showSnackBar('Added common internal ranges');
                            },
                            child: const Text('Add Common Internal Ranges'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  ...whitelist.entries.map((entry) {
                    final ip = entry.key;
                    final description = entry.value;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(
                          Icons.shield_outlined,
                          color: Colors.green,
                        ),
                        title: Text(ip),
                        subtitle: description != null && description.isNotEmpty
                            ? Text(description)
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _removeFromWhitelist(ip),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear Whitelist'),
                          content: const Text(
                            'Remove all whitelisted IPs? This cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Clear All'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await WhitelistService.clearWhitelist();
                        setState(() {
                          _loadWhitelist();
                        });
                        _showSnackBar('Whitelist cleared');
                      }
                    },
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Clear All'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

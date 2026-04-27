import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/server_status_controller.dart';

class UserClientScreen extends StatefulWidget {
  final ServerStatusController controller;

  const UserClientScreen({
    super.key,
    required this.controller,
  });

  @override
  State<UserClientScreen> createState() => _UserClientScreenState();
}

class _UserClientScreenState extends State<UserClientScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Clients'),
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final snapshot = controller.snapshot;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active Users (${snapshot?.activeClients.length ?? 0})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (snapshot?.activeClients.isEmpty ?? true)
                        const Text('No active users')
                      else
                        ...snapshot!.activeClients.map((client) => _buildClientRow(context, client)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registered Devices (${snapshot?.registeredDevices.length ?? 0})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (snapshot?.registeredDevices.isEmpty ?? true)
                        const Text('No registered devices')
                      else
                        ...snapshot!.registeredDevices.map((device) => _buildClientRow(context, device, isActive: false)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildClientRow(BuildContext context, Map<String, dynamic> client, {bool isActive = true}) {
    final ip = client['ip'] ?? 'Unknown';
    final localIp = client['localIp'] ?? 'Unknown';
    final deviceName = client['deviceName'] ?? client['device'] ?? 'Unknown Device';
    final deviceModel = client['deviceModel'] ?? 'Unknown';
    final platform = client['platform'] ?? 'Unknown';
    final androidVersion = client['androidVersion'] ?? 'Unknown';
    final macAddress = client['macAddress'] ?? 'Not Available';
    final location = client['location'] ?? 'Unknown';
    final lastSeen = client['lastSeen'] ?? 'Unknown';
    final connectedAt = client['connectedAt'] ?? '';
    final registeredAt = client['registeredAt'] ?? '';
    final deviceId = client['deviceId'] ?? client['id'] ?? 'Not Available';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isActive ? Icons.smartphone : Icons.phone_android,
                  size: 20,
                  color: isActive ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$deviceName ($deviceModel)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Platform: $platform ${androidVersion != 'Unknown' ? 'v$androidVersion' : ''}'),
            if (localIp != 'Unknown')
              Text('Network IP: $localIp • Location: $location')
            else
              Text('IP: $ip • Location: $location'),
            if (deviceId != 'Not Available')
              Text('Device ID: $deviceId', style: TextStyle(fontSize: 11, color: Colors.grey[600]))
            else
              const SizedBox(height: 0),
            if (macAddress != 'Not Available') Text('MAC: $macAddress'),
            Text('${isActive ? 'Connected' : 'Last Seen'}: $lastSeen'),
            if (connectedAt.isNotEmpty) Text('Connected At: $connectedAt'),
            if (registeredAt.isNotEmpty && !isActive) Text('Registered At: $registeredAt'),
          ],
        ),
      ),
    );
  }
}
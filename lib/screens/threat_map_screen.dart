  import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/firewall_log.dart';
import '../services/log_analysis_service.dart';

class ThreatMapScreen extends StatelessWidget {
  final List<FirewallLog> logs;

  const ThreatMapScreen({super.key, required this.logs});

  void _showLogDetails(BuildContext context, FirewallLog log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('IP: ${log.ipAddress}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Country: ${log.country}'),
            Text('Status Code: ${log.responseCode}'),
            Text('URL: ${log.url}'),
            const SizedBox(height: 8),
            Text(
              LogAnalysisService.isSuspicious(log)
                  ? 'Status: Suspicious / Attack'
                  : 'Status: Normal',
              style: TextStyle(
                color: LogAnalysisService.isSuspicious(log)
                    ? Colors.red
                    : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validLogs = logs.where(
      (log) => log.latitude != null && log.longitude != null,
    ).toList();

    // Group logs by coordinates to show count or avoid identical overlaps.
    // Simplifying by just rendering them all, or slight random offsets.
    // For MVP, we render them directly.
    final markers = validLogs.map((log) {
      final isSuspicious = LogAnalysisService.isSuspicious(log);
      return Marker(
        point: LatLng(log.latitude!, log.longitude!),
        width: 30,
        height: 30,
        child: GestureDetector(
          onTap: () => _showLogDetails(context, log),
          child: Icon(
            Icons.location_on,
            color: isSuspicious ? Colors.red : Colors.blue,
            size: isSuspicious ? 30 : 20,
          ),
        ),
      );
    }).toList();

    return Scaffold(
      body: validLogs.isEmpty
          ? const Center(
              child: Text(
                'No logs with Geo coordinates available yet.\nUpload logs or wait for background enrichment.',
                textAlign: TextAlign.center,
              ),
            )
          : FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(20.0, 0.0),
                initialZoom: 2.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.firewall_log_analyzer',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
    );
  }
}

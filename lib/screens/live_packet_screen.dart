import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/live_controller.dart';
import '../models/live_packet_record.dart';
import '../services/log_analysis_service.dart';
import '../services/saved_analysis_service.dart';
import '../services/websocket_url_helper.dart';
import '../services/websocket_url_store.dart';
import '../widgets/live_packet_detail_dialog.dart';
import '../widgets/packet_chart_widget.dart';
import '../widgets/status_chip.dart';

class LivePacketScreen extends StatefulWidget {
  final LiveController controller;
  const LivePacketScreen({super.key, required this.controller});

  @override
  State<LivePacketScreen> createState() => _LivePacketScreenState();
}

class _LivePacketScreenState extends State<LivePacketScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _showSuspiciousOnly = false;

  @override
  void initState() {
    super.initState();
    _loadUrl();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _urlController.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadUrl() async {
    final savedUrl = await WebSocketUrlStore.load();
    if (mounted) {
      final ipUrl = 'ws://$defaultServerIp:8765';
      if (savedUrl.isEmpty || 
          savedUrl == defaultWebSocketUrl || 
          savedUrl.contains('analyzer.plexaur.com')) {
        _urlController.text = ipUrl;
      } else {
        _urlController.text = savedUrl;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = widget.controller;
    
    final displayedPackets = _showSuspiciousOnly 
        ? ctrl.packets.where((p) {
            final risk = LogAnalysisService.analyze(p.log).riskLevel;
            return risk == 'Critical' || risk == 'High' || risk == 'Medium';
          }).toList()
        : ctrl.packets;

    return Column(
      children: [
        _buildConnectionHeader(theme, ctrl),
        if (ctrl.isConnected) ...[
        _buildFilterBar(theme),
        RepaintBoundary(child: PacketChartWidget(packets: displayedPackets)),
        Expanded(
          child: displayedPackets.isEmpty
              ? _buildEmptyState(theme, _showSuspiciousOnly)
              : ListView.builder(
                  itemCount: displayedPackets.length,
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  cacheExtent: 500, // Optimize scrolling
                  itemBuilder: (context, index) {
                    return _PacketListTile(
                      key: ValueKey(displayedPackets[index].id),
                      packet: displayedPackets[index],
                      onTap: () => _showPacketDetails(context, displayedPackets[index]),
                    );
                  },
                ),
        ),
        ] else
          Expanded(
            child: _buildDisconnectedState(theme, ctrl),
          ),
      ],
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('All Traffic'),
            selected: !_showSuspiciousOnly,
            onSelected: (val) => setState(() => _showSuspiciousOnly = false),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Suspicious Only'),
            selected: _showSuspiciousOnly,
            onSelected: (val) => setState(() => _showSuspiciousOnly = true),
            selectedColor: theme.colorScheme.errorContainer,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionHeader(ThemeData theme, LiveController ctrl) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(
            ctrl.isConnected ? Icons.sensors : Icons.sensors_off,
            color: ctrl.isConnected ? Colors.green : theme.disabledColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ctrl.statusMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ctrl.isConnected ? theme.colorScheme.primary : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (ctrl.isConnected)
                  Text(
                    'Uptime: ${ctrl.connectedDuration}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.hintColor,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          if (ctrl.isConnected) ...[
            _PulseIndicator(color: ctrl.isSniffing ? Colors.green : Colors.grey),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: ctrl.isSniffing ? ctrl.stopSniffing : ctrl.startSniffing,
              icon: Icon(ctrl.isSniffing ? Icons.stop : Icons.play_arrow, size: 18),
              label: Text(ctrl.isSniffing ? 'STOP SNIFFING' : 'START SNIFFING'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ctrl.isSniffing 
                    ? theme.colorScheme.errorContainer 
                    : theme.colorScheme.primaryContainer,
                foregroundColor: ctrl.isSniffing 
                    ? theme.colorScheme.error 
                    : theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _saveSnapshot(ctrl),
              icon: const Icon(Icons.save_alt, size: 22),
              tooltip: 'Save Snapshot',
              color: theme.colorScheme.primary,
            ),
            IconButton(
              onPressed: () => ctrl.disconnect(),
              icon: const Icon(Icons.power_settings_new, size: 20),
              tooltip: 'Disconnect',
              color: theme.colorScheme.error,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveSnapshot(LiveController ctrl) async {
    if (ctrl.packets.isEmpty) return;

    final snapshotName = 'Live_${DateFormat('MMdd_HHmm').format(DateTime.now())}';
    
    // Auto-filter for suspicious packets if requested, or just save current view
    final packetsToSave = _showSuspiciousOnly 
        ? ctrl.packets.where((p) {
            final risk = LogAnalysisService.analyze(p.log).riskLevel;
            return risk != 'Low';
          }).toList()
        : ctrl.packets;

    if (packetsToSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No suspicious packets to save!'))
      );
      return;
    }

    await SavedAnalysisService.saveAnalysis(snapshotName, packetsToSave);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${packetsToSave.length} packets to snapshot: $snapshotName'),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
    }
  }

  Widget _buildDisconnectedState(ThemeData theme, LiveController ctrl) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lan_outlined, size: 64, color: theme.colorScheme.primary.withOpacity(0.2)),
            const SizedBox(height: 24),
            Text('Live Packet Feed', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Connect to a local packet server to see real-time firewall activity.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 32),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          labelText: 'Server WebSocket URL',
                          hintText: 'ws://$defaultServerIp:8765',
                          prefixIcon: const Icon(Icons.link),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: ctrl.isConnecting ? null : () => ctrl.connect(_urlController.text.trim()),
                          icon: ctrl.isConnecting
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.play_arrow),
                          label: Text(ctrl.isConnecting ? 'Connecting...' : 'Start Live Feed'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isFiltered) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!isFiltered) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Listening for incoming packets...',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
          ] else ...[
            Icon(Icons.shield_outlined, size: 48, color: theme.hintColor),
            const SizedBox(height: 16),
            Text(
              'No suspicious packets detected yet.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
          ],
        ],
      ),
    );
  }

  void _showPacketDetails(BuildContext context, LivePacketRecord packet) {
    showDialog(
      context: context,
      builder: (context) => LivePacketDetailDialog(packet: packet),
    );
  }
}

class _PacketListTile extends StatelessWidget {
  final LivePacketRecord packet;
  final VoidCallback onTap;

  const _PacketListTile({super.key, required this.packet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = LogAnalysisService.analyze(packet.log);
    final timeStr = DateFormat.Hms().format(packet.receivedAt);
    final isCritical = analysis.riskLevel == 'Critical' || analysis.riskLevel == 'High';

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isCritical ? theme.colorScheme.error.withOpacity(0.03) : null,
          border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
        ),
        child: Row(
          children: [
            _buildSeverityIndicator(analysis.riskLevel),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getMethodColor(packet.log.method).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          packet.log.method.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _getMethodColor(packet.log.method),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          packet.log.ipAddress,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (packet.log.backendAlerts?.isNotEmpty ?? false) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange.shade700),
                      ],
                      const Spacer(),
                      if (packet.log.source.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            packet.log.source.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 8,
                              color: theme.hintColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    packet.log.request,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  timeStr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                _buildRiskChip(analysis.riskLevel, theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getMethodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET': return Colors.blue;
      case 'POST': return Colors.green;
      case 'PUT': return Colors.orange;
      case 'DELETE': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildRiskChip(String level, ThemeData theme) {
    Color color;
    switch (level) {
      case 'Critical': color = Colors.red.shade900; break;
      case 'High': color = Colors.red; break;
      case 'Medium': color = Colors.orange; break;
      default: color = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        level.toUpperCase(),
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSeverityIndicator(String riskLevel) {
    Color color;
    switch (riskLevel) {
      case 'Critical': color = Colors.red.shade900; break;
      case 'High': color = Colors.red; break;
      case 'Medium': color = Colors.orange; break;
      case 'Low':
      default: color = Colors.green;
    }

    return Container(
      width: 4,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          if (riskLevel == 'Critical' || riskLevel == 'High')
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: 6,
              spreadRadius: 1,
            ),
        ],
      ),
    );
  }
}

class _PulseIndicator extends StatefulWidget {
  final Color color;
  const _PulseIndicator({required this.color});

  @override
  State<_PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<_PulseIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity(1.0 - _controller.value),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.5),
                blurRadius: 8 * _controller.value,
                spreadRadius: 4 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

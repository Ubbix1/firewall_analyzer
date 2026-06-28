import 'dart:async';
import 'dart:ui';
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
  
  // Stats tracking
  int _packetsLastSecond = 0;
  double _pps = 0.0;
  Timer? _ppsTimer;

  @override
  void initState() {
    super.initState();
    _loadUrl();
    widget.controller.addListener(_onControllerUpdate);
    _startStatsTimer();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _ppsTimer?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  void _startStatsTimer() {
    _ppsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final now = DateTime.now();
      final lastSecondPackets = widget.controller.packets.where((p) => 
        now.difference(p.receivedAt).inSeconds < 1
      ).length;
      
      setState(() {
        _pps = lastSecondPackets.toDouble();
      });
    });
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

    final criticalCount = ctrl.packets.where((p) {
      final risk = LogAnalysisService.analyze(p.log).riskLevel;
      return risk == 'Critical' || risk == 'High';
    }).length;

    return Container(
      color: theme.colorScheme.background,
      child: Column(
        children: [
          _buildConnectionHeader(theme, ctrl),
          if (ctrl.isConnected) ...[
            _buildLiveStatsStrip(theme, ctrl.packets.length, criticalCount),
            _buildFilterBar(theme),
            RepaintBoundary(child: PacketChartWidget(packets: ctrl.packets)),
            Expanded(
              child: displayedPackets.isEmpty
                  ? _buildEmptyState(theme, _showSuspiciousOnly)
                  : ListView.builder(
                      itemCount: displayedPackets.length,
                      padding: const EdgeInsets.only(top: 4, bottom: 80),
                      cacheExtent: 1000,
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
      ),
    );
  }

  Widget _buildLiveStatsStrip(ThemeData theme, int total, int critical) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('TOTAL', total.toString(), theme.colorScheme.primary),
          _buildStatItem('CRITICAL', critical.toString(), Colors.redAccent),
          _buildStatItem('RATE', '${_pps.toInt()} p/s', Colors.cyanAccent),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: color.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          _buildMinimalFilterChip('ALL TRAFFIC', !_showSuspiciousOnly, () => setState(() => _showSuspiciousOnly = false)),
          const SizedBox(width: 12),
          _buildMinimalFilterChip('SUSPICIOUS', _showSuspiciousOnly, () => setState(() => _showSuspiciousOnly = true), isAlert: true),
        ],
      ),
    );
  }

  Widget _buildMinimalFilterChip(String label, bool isSelected, VoidCallback onTap, {bool isAlert = false}) {
    final theme = Theme.of(context);
    final color = isAlert ? Colors.redAccent : theme.colorScheme.primary;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.3) : theme.dividerColor.withOpacity(0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: isSelected ? color : theme.hintColor,
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionHeader(ThemeData theme, LiveController ctrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.1),
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          _PulseIndicator(color: ctrl.isConnected ? (ctrl.isSniffing ? Colors.greenAccent : Colors.amberAccent) : Colors.grey),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ctrl.isConnected ? 'LIVE MONITOR ACTIVE' : 'MONITOR OFFLINE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    fontSize: 10,
                    color: ctrl.isConnected ? Colors.greenAccent : theme.hintColor,
                  ),
                ),
                Text(
                  ctrl.statusMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor.withOpacity(0.7),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (ctrl.isConnected) ...[
            IconButton(
              onPressed: ctrl.isSniffing ? ctrl.stopSniffing : ctrl.startSniffing,
              icon: Icon(ctrl.isSniffing ? Icons.stop_circle_outlined : Icons.play_circle_outline),
              color: ctrl.isSniffing ? Colors.redAccent : Colors.greenAccent,
              tooltip: ctrl.isSniffing ? 'Stop Sniffing' : 'Start Sniffing',
            ),
            IconButton(
              onPressed: () => _saveSnapshot(ctrl),
              icon: const Icon(Icons.screenshot_outlined),
              tooltip: 'Save Snapshot',
              color: theme.colorScheme.primary,
            ),
            IconButton(
              onPressed: () => ctrl.disconnect(),
              icon: const Icon(Icons.power_settings_new_outlined),
              tooltip: 'Disconnect',
              color: Colors.redAccent.withOpacity(0.7),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveSnapshot(LiveController ctrl) async {
    if (ctrl.packets.isEmpty) return;
    final snapshotName = 'Live_${DateFormat('MMdd_HHmm').format(DateTime.now())}';
    final packetsToSave = _showSuspiciousOnly 
        ? ctrl.packets.where((p) {
            final risk = LogAnalysisService.analyze(p.log).riskLevel;
            return risk != 'Low';
          }).toList()
        : ctrl.packets;

    if (packetsToSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No packets to save!')));
      return;
    }

    await SavedAnalysisService.saveAnalysis(snapshotName, packetsToSave);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${packetsToSave.length} packets to snapshot: $snapshotName'))
      );
    }
  }

  Widget _buildDisconnectedState(ThemeData theme, LiveController ctrl) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.05),
              ),
              child: Icon(Icons.router_outlined, size: 80, color: theme.colorScheme.primary.withOpacity(0.2)),
            ),
            const SizedBox(height: 32),
            Text('Packet Monitor', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w200, letterSpacing: 2)),
            const SizedBox(height: 16),
            Text(
              'Connect to the security endpoint to begin real-time traffic analysis.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.5),
            ),
            const SizedBox(height: 48),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _urlController,
                        style: const TextStyle(fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          labelText: 'WSS ENDPOINT',
                          hintText: 'ws://$defaultServerIp:8765',
                          prefixIcon: const Icon(Icons.bolt, size: 20),
                          labelStyle: const TextStyle(letterSpacing: 2, fontSize: 10, fontWeight: FontWeight.bold),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: ctrl.isConnecting ? null : () => ctrl.connect(_urlController.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: ctrl.isConnecting
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('INITIALIZE FEED', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
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
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.cyanAccent)),
          ),
          const SizedBox(height: 32),
          Text(
            isFiltered ? 'SCANNING FOR THREATS...' : 'AWAITING NETWORK TRAFFIC...',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
              color: theme.hintColor.withOpacity(0.5),
            ),
          ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isCritical ? Colors.redAccent.withOpacity(0.05) : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCritical ? Colors.redAccent.withOpacity(0.2) : theme.dividerColor.withOpacity(0.05),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                _buildSeverityBar(analysis.riskLevel),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildMethodBadge(packet.log.method),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                packet.log.ipAddress,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.hintColor,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          packet.log.request,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: theme.hintColor.withOpacity(0.3)),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMethodBadge(String method) {
    Color color;
    switch (method.toUpperCase()) {
      case 'GET': color = Colors.blueAccent; break;
      case 'POST': color = Colors.greenAccent; break;
      case 'PUT': color = Colors.orangeAccent; break;
      case 'DELETE': color = Colors.redAccent; break;
      default: color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        method.toUpperCase(),
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: color),
      ),
    );
  }

  Widget _buildSeverityBar(String riskLevel) {
    Color color;
    switch (riskLevel) {
      case 'Critical': color = Colors.red.shade900; break;
      case 'High': color = Colors.redAccent; break;
      case 'Medium': color = Colors.orangeAccent; break;
      default: color = Colors.greenAccent;
    }

    return Container(
      width: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
        boxShadow: [
          if (riskLevel == 'Critical' || riskLevel == 'High')
            BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 1),
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

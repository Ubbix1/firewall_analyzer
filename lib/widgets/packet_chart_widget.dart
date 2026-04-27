import 'package:flutter/material.dart';
import '../models/live_packet_record.dart';

class PacketChartWidget extends StatelessWidget {
  final List<LivePacketRecord> packets;

  const PacketChartWidget({super.key, required this.packets});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Dynamic visual representation of packet volume
    final now = DateTime.now();
    final bins = List.generate(40, (_) => 0);
    
    for (var packet in packets) {
      final diff = now.difference(packet.receivedAt).inSeconds;
      if (diff >= 0 && diff < 40) {
        bins[39 - diff]++;
      }
    }

    final maxVolume = bins.reduce((a, b) => a > b ? a : b);
    
    return Container(
      height: 120,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withOpacity(0.05)),
      ),
      child: Stack(
        children: [
          // Grid lines
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (_) => Container(
                height: 1,
                color: theme.dividerColor.withOpacity(0.03),
              )),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(
                bins.length,
                (index) {
                  final count = bins[index];
                  final ratio = maxVolume == 0 ? 0.05 : (count / maxVolume).clamp(0.05, 1.0);
                  
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: 96 * ratio,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.primary.withOpacity(0.6),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        boxShadow: [
                          if (count > 0)
                            BoxShadow(
                              color: theme.colorScheme.primary.withOpacity(0.3),
                              blurRadius: 4,
                              spreadRadius: 0,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

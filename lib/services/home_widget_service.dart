import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

class HomeWidgetService {
  static const String _batteryWidgetName = 'com.plexaur.firewall_log_analyzer.BatteryWidgetProvider';
  static const String _dockerWidgetName = 'com.plexaur.firewall_log_analyzer.DockerWidgetProvider';

  /// Call once during app startup to initialize the plugin.
  static Future<void> init() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await HomeWidget.setAppGroupId('com.plexaur.firewall_log_analyzer');
      debugPrint('HomeWidgetService initialized');
    } catch (e) {
      debugPrint('HomeWidgetService init error: $e');
    }
  }

  /// Push "Connecting…" placeholder data so the widgets are never blank.
  static Future<void> setConnecting() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      // Battery Widget
      await HomeWidget.saveWidgetData<String>('server_battery', '--%');
      await HomeWidget.saveWidgetData<String>('server_status', 'Connecting');
      await HomeWidget.saveWidgetData<String>('server_temp', '--°C');
      await HomeWidget.saveWidgetData<String>('server_ssh', '0 SSH');
      await HomeWidget.updateWidget(
        name: _batteryWidgetName,
        qualifiedAndroidName: _batteryWidgetName,
      );

      // Docker Widget
      await HomeWidget.saveWidgetData<String>('docker_count', '0/0');
      await HomeWidget.saveWidgetData<String>('docker_health', 'Connecting...');
      await HomeWidget.updateWidget(
        name: _dockerWidgetName,
        qualifiedAndroidName: _dockerWidgetName,
      );
    } catch (e) {
      debugPrint('HomeWidgetService setConnecting error: $e');
    }
  }

  // ── Battery Widget ──────────────────────────────────────────────────

  /// Save battery data to SharedPreferences (cheap, call on every update).
  static Future<void> saveBatteryWidgetData({
    required int? batteryPercent,
    required String status,
    required double? temperature,
    required int sshCount,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final batteryText = batteryPercent != null ? '$batteryPercent%' : '--%';
      final tempText =
          temperature != null ? '${temperature.toStringAsFixed(1)}°C' : '--°C';
      final sshText = '$sshCount SSH';

      await HomeWidget.saveWidgetData<String>('server_battery', batteryText);
      await HomeWidget.saveWidgetData<String>('server_status', status);
      await HomeWidget.saveWidgetData<String>('server_temp', tempText);
      await HomeWidget.saveWidgetData<String>('server_ssh', sshText);

      debugPrint(
          '💾 Battery prefs saved: $batteryText | $tempText | $sshText | $status');
    } catch (e) {
      debugPrint('Error saving battery widget data: $e');
    }
  }

  /// Tell Android to redraw the battery widget RemoteViews (expensive, call on timer).
  static Future<void> refreshBatteryWidget() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await HomeWidget.updateWidget(
        name: _batteryWidgetName,
        qualifiedAndroidName: _batteryWidgetName,
      );
      debugPrint('🔄 Battery widget RemoteViews refresh triggered');
    } catch (e) {
      debugPrint('Error refreshing battery widget: $e');
    }
  }

  /// Convenience: save + refresh in one call.
  static Future<void> updateBatteryWidget({
    required int? batteryPercent,
    required String status,
    required double? temperature,
    required int sshCount,
  }) async {
    await saveBatteryWidgetData(
      batteryPercent: batteryPercent,
      status: status,
      temperature: temperature,
      sshCount: sshCount,
    );
    await refreshBatteryWidget();
  }

  // ── Docker Widget ──────────────────────────────────────────────────

  /// Save docker data to SharedPreferences (cheap, call on every update).
  static Future<void> saveDockerWidgetData({
    required int runningCount,
    required int totalCount,
    required String status,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final countText = '$runningCount/$totalCount';
      final healthMsg = runningCount == totalCount && totalCount > 0
          ? 'All systems healthy'
          : runningCount < totalCount
              ? '${totalCount - runningCount} container(s) down!'
              : 'Waiting for data...';

      await HomeWidget.saveWidgetData<String>('docker_count', countText);
      await HomeWidget.saveWidgetData<String>('docker_health', healthMsg);
      await HomeWidget.saveWidgetData<String>('server_status', status);

      debugPrint('💾 Docker prefs saved: $countText | $healthMsg | $status');
    } catch (e) {
      debugPrint('Error saving docker widget data: $e');
    }
  }

  /// Tell Android to redraw the docker widget RemoteViews (expensive, call on timer).
  static Future<void> refreshDockerWidget() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await HomeWidget.updateWidget(
        name: _dockerWidgetName,
        qualifiedAndroidName: _dockerWidgetName,
      );
      debugPrint('🔄 Docker widget RemoteViews refresh triggered');
    } catch (e) {
      debugPrint('Error refreshing docker widget: $e');
    }
  }

  /// Convenience: save + refresh in one call.
  static Future<void> updateDockerWidget({
    required int runningCount,
    required int totalCount,
    required String status,
  }) async {
    await saveDockerWidgetData(
      runningCount: runningCount,
      totalCount: totalCount,
      status: status,
    );
    await refreshDockerWidget();
  }
}

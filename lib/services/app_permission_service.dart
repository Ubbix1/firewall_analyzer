import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissionStatus {
  final bool notificationGranted;
  final bool ignoreBatteryOptimizationsGranted;

  const AppPermissionStatus({
    required this.notificationGranted,
    required this.ignoreBatteryOptimizationsGranted,
  });

  bool get allRequiredGranted =>
      notificationGranted && ignoreBatteryOptimizationsGranted;
}

class AppPermissionService {
  static Future<AppPermissionStatus> getStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const AppPermissionStatus(
        notificationGranted: true,
        ignoreBatteryOptimizationsGranted: true,
      );
    }

    final notificationStatus = await Permission.notification.status;
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;

    return AppPermissionStatus(
      notificationGranted: notificationStatus.isGranted,
      ignoreBatteryOptimizationsGranted: batteryStatus.isGranted,
    );
  }

  static Future<AppPermissionStatus> requestMissingPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return getStatus();
    }

    var status = await getStatus();
    if (status.notificationGranted &&
        status.ignoreBatteryOptimizationsGranted) {
      return status;
    }

    if (!status.notificationGranted) {
      final notificationResult = await Permission.notification.request();
      if (!notificationResult.isGranted &&
          notificationResult.isPermanentlyDenied) {
        await openAppSettings();
      }
    }

    status = await getStatus();
    if (!status.ignoreBatteryOptimizationsGranted) {
      final batteryResult =
          await Permission.ignoreBatteryOptimizations.request();
      if (!batteryResult.isGranted && batteryResult.isPermanentlyDenied) {
        await openAppSettings();
      }
    }

    return getStatus();
  }
}

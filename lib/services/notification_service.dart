import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static const String batteryChannelId = 'battery_alerts';
  static const String securityChannelId = 'security_alerts';
  static const String notificationIcon = 'notification_icon';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(notificationIcon);
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);

    final androidImplementation = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        batteryChannelId,
        'Battery Alerts',
        description: 'Battery level and charging notifications',
        importance: Importance.high,
        playSound: true,
      ),
    );
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        securityChannelId,
        'Security Alerts',
        description: 'Critical and suspicious firewall alerts',
        importance: Importance.max,
        playSound: true,
      ),
    );

    _initialized = true;
    debugPrint('Notification service initialized');
  }

  static Future<void> requestPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final androidImplementation = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();

    final status = await Permission.notification.request();
    debugPrint('Notification permission status: $status');
  }

  static Future<void> showNotification({
    required String title,
    required String body,
    int? id,
    String type = 'generic',
    String level = 'info',
  }) async {
    await initialize();

    final isSecurityAlert = type == 'security_alert';
    final channelId = isSecurityAlert ? securityChannelId : batteryChannelId;
    final channelName = isSecurityAlert ? 'Security Alerts' : 'Battery Alerts';
    final channelDescription = isSecurityAlert
        ? 'Critical and suspicious firewall alerts'
        : 'Battery level and charging notifications';

    debugPrint('Showing notification [$type/$level]: $title - $body');

    try {
      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        icon: notificationIcon,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        largeIcon: const DrawableResourceAndroidBitmap(notificationIcon),
        showWhen: true,
        visibility: NotificationVisibility.public,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 300, 200, 300]),
        playSound: true,
        category: isSecurityAlert ? AndroidNotificationCategory.alarm : null,
        styleInformation: BigTextStyleInformation(body),
      );
      final details = NotificationDetails(android: androidDetails);

      await _plugin.show(
        id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
      );
      debugPrint('Notification sent successfully');
    } catch (error) {
      debugPrint('Error showing notification: $error');
    }
  }
}

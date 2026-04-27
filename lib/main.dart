import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/home_screen.dart';
import 'services/app_permission_service.dart';
import 'services/database_helper.dart';
import 'services/fcm_registration_service.dart';
import 'services/notification_service.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initialize();
  debugPrint('Background message: ${message.messageId}');
  _handleFirebaseMessage(message, showLocalNotification: false);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const FirewallLogAnalyzerApp());
  
  // Defer everything else until after the first frame.
  unawaited(_postLaunchSetup());
}

Future<void> _postLaunchSetup() async {
  // Defer notification and background messaging setup to avoid startup congestion.
  await Future<void>.delayed(const Duration(milliseconds: 500));
  Future.microtask(() => NotificationService.initialize());
  if (defaultTargetPlatform == TargetPlatform.android) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await _setupFirebaseMessaging();
  }
}

Future<void> _setupFirebaseMessaging() async {
  // Wait a bit more before requesting tokens and syncing with server.
  await Future<void>.delayed(const Duration(seconds: 2));
  
  final token = await FirebaseMessaging.instance.getToken();
  debugPrint('FCM token: $token');
  if (token != null) {
    unawaited(FcmRegistrationService.registerTokenWithSavedServer(token));
  }

  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    debugPrint('FCM token refreshed');
    unawaited(FcmRegistrationService.registerTokenWithSavedServer(newToken));
  });

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('Foreground message: ${message.messageId}');
    _handleFirebaseMessage(message, showLocalNotification: true);
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('Message opened app: ${message.messageId}');
    _handleFirebaseMessage(message, showLocalNotification: false);
  });

  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    debugPrint('Initial message: ${initialMessage.messageId}');
    _handleFirebaseMessage(initialMessage, showLocalNotification: false);
  }
}

void _handleFirebaseMessage(
  RemoteMessage message, {
  required bool showLocalNotification,
}) {
  final messageType = message.data['type'] ?? 'generic';
  final level = message.data['level'] ?? 'info';
  final title = message.data['title'] ??
      message.notification?.title ??
      (messageType == 'security_alert'
          ? 'Security Alert'
          : 'Firewall Notification');
  final body = message.data['body'] ??
      message.notification?.body ??
      'A new firewall event was received.';

  debugPrint('Push message [$messageType/$level]: $title - $body');

  if (showLocalNotification) {
    unawaited(
      NotificationService.showNotification(
        title: title,
        body: body,
        type: messageType,
        level: level,
      ),
    );
  }
}

class FirewallLogAnalyzerApp extends StatefulWidget {
  const FirewallLogAnalyzerApp({super.key});

  @override
  State<FirewallLogAnalyzerApp> createState() => _FirewallLogAnalyzerAppState();
}

class _FirewallLogAnalyzerAppState extends State<FirewallLogAnalyzerApp> {
  ThemeMode _themeMode = ThemeMode.system;
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final mode = await _databaseHelper.getThemeMode();
    if (mounted) {
      setState(() {
        _themeMode = mode;
      });
    }
  }

  Future<void> _setThemeMode(ThemeMode themeMode) async {
    setState(() {
      _themeMode = themeMode;
    });
    await _databaseHelper.setThemeMode(themeMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Firewall Log Analyzer',
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: defaultTargetPlatform == TargetPlatform.android
          ? AppPermissionGate(
              child: HomeScreen(
                themeMode: _themeMode,
                onThemeModeChanged: _setThemeMode,
              ),
            )
          : HomeScreen(
              themeMode: _themeMode,
              onThemeModeChanged: _setThemeMode,
            ),
    );
  }
}

class AppPermissionGate extends StatefulWidget {
  final Widget child;

  const AppPermissionGate({super.key, required this.child});

  @override
  State<AppPermissionGate> createState() => _AppPermissionGateState();
}

class _AppPermissionGateState extends State<AppPermissionGate>
    with WidgetsBindingObserver {
  AppPermissionStatus? _permissionStatus;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkPermissions(requestIfMissing: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkPermissions());
    }
  }

  Future<void> _checkPermissions({bool requestIfMissing = false}) async {
    final status = await AppPermissionService.getStatus();
    if (!mounted) {
      return;
    }

    setState(() {
      _permissionStatus = status;
    });

    if (requestIfMissing && !status.allRequiredGranted) {
      await _requestPermissionsUntilGranted();
    }
  }

  Future<void> _requestPermissionsUntilGranted() async {
    if (_isRequesting) {
      return;
    }

    setState(() {
      _isRequesting = true;
    });

    try {
      final updatedStatus =
          await AppPermissionService.requestMissingPermissions();
      if (!mounted) {
        return;
      }

      setState(() {
        _permissionStatus = updatedStatus;
      });

      if (!updatedStatus.allRequiredGranted) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) {
          return;
        }
        setState(() {});
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRequesting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _permissionStatus;
    if (status == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (status.allRequiredGranted) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        // We'll use an ImageFiltered for the premium blur feel
        Positioned.fill(
          child: ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: widget.child, // Blur the actual background content
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.4), // Darken slightly more for contrast
          ),
        ),
        _buildPermissionOverlay(context, status),
      ],
    );
  }

  Widget _buildPermissionOverlay(BuildContext context, AppPermissionStatus status) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 24,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.security, size: 64, color: Colors.blue),
                  const SizedBox(height: 24),
                  Text(
                    'Permissions Required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The app needs these Android permissions for background sync and push alerts.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  _buildPermissionTile(
                    context,
                    status.notificationGranted,
                    Icons.notifications_active,
                    'Notifications',
                    'Required for push alerts on your phone.',
                  ),
                  const SizedBox(height: 12),
                  _buildPermissionTile(
                    context,
                    status.ignoreBatteryOptimizationsGranted,
                    Icons.battery_saver,
                    'Battery Optimization',
                    'Allows background sync without interruption.',
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _isRequesting ? null : _requestPermissionsUntilGranted,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(_isRequesting ? 'Checking...' : 'Grant Permissions'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _isRequesting ? null : openAppSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Open App Settings'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionTile(
    BuildContext context,
    bool granted,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: granted ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: granted ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(granted ? Icons.check_circle : icon, color: granted ? Colors.green : Colors.grey),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

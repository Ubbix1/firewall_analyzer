import 'dart:convert';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdService {
  static const String _deviceIdKey = 'app_device_id';
  static const String _deviceIdentifierKey = 'app_device_identifier';

  /// Get or generate a unique device ID.
  /// This ID persists across app installations and is unique per device.
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if we already have a stored device ID
    String? storedId = prefs.getString(_deviceIdKey);
    if (storedId != null && storedId.isNotEmpty) {
      return storedId;
    }

    // Generate a new unique device ID
    final deviceId = await _generateUniqueDeviceId();
    
    // Store it for future use
    await prefs.setString(_deviceIdKey, deviceId);
    
    return deviceId;
  }

  /// Generate a unique device ID based on device information and a random component.
  /// This ensures uniqueness even for devices of the same model.
  static Future<String> _generateUniqueDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceHash = '';

      if (defaultTargetPlatform.toString() == 'TargetPlatform.android') {
        final androidInfo = await deviceInfo.androidInfo;
        // Combine multiple device identifiers for uniqueness
        final identifier = [
          androidInfo.manufacturer ?? '',
          androidInfo.brand ?? '',
          androidInfo.model ?? '',
          androidInfo.device ?? '',
          androidInfo.hardware ?? '',
          androidInfo.id ?? '', // This is a unique hardware identifier
        ].join('_');
        
        deviceHash = _generateHash(identifier);
      } else if (defaultTargetPlatform.toString() == 'TargetPlatform.iOS') {
        final iosInfo = await deviceInfo.iosInfo;
        // Use device name and model for iOS
        final identifier = [
          iosInfo.name ?? '',
          iosInfo.model ?? '',
          iosInfo.identifierForVendor ?? '', // Unique per app vendor
        ].join('_');
        
        deviceHash = _generateHash(identifier);
      } else {
        // Fallback for other platforms
        deviceHash = _generateHash('unknown_device');
      }

      // Add a random component to ensure uniqueness even if device hash is similar
      final randomSuffix = _generateRandomString(8);
      final finalId = '${deviceHash.substring(0, 16)}_$randomSuffix';
      
      debugPrint('Generated new device ID: $finalId');
      return finalId;
    } catch (e) {
      debugPrint('Error generating device ID: $e');
      // Fallback: generate a random ID if device info is unavailable
      return 'device_${_generateRandomString(20)}';
    }
  }

  /// Generate a simple hash from a string
  static String _generateHash(String input) {
    if (input.isEmpty) {
      return '0' * 32;
    }
    
    // Simple hash function using Dart's String hashCode
    // For production, consider using crypto package for proper hashing
    var hash = 5381;
    for (var i = 0; i < input.length; i++) {
      hash = ((hash << 5) + hash) ^ input.codeUnitAt(i);
    }
    
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Generate a random string of given length
  static String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Get device identifier information (for debugging/display purposes)
  static Future<Map<String, String>> getDeviceIdentifierInfo() async {
    final info = <String, String>{};
    
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (defaultTargetPlatform.toString() == 'TargetPlatform.android') {
        final androidInfo = await deviceInfo.androidInfo;
        info['platform'] = 'Android';
        info['manufacturer'] = androidInfo.manufacturer ?? 'Unknown';
        info['brand'] = androidInfo.brand ?? 'Unknown';
        info['model'] = androidInfo.model ?? 'Unknown';
        info['device'] = androidInfo.device ?? 'Unknown';
        info['hardware'] = androidInfo.hardware ?? 'Unknown';
        info['android_id'] = androidInfo.id ?? 'Unknown';
      } else if (defaultTargetPlatform.toString() == 'TargetPlatform.iOS') {
        final iosInfo = await deviceInfo.iosInfo;
        info['platform'] = 'iOS';
        info['name'] = iosInfo.name ?? 'Unknown';
        info['model'] = iosInfo.model ?? 'Unknown';
        info['system_version'] = iosInfo.systemVersion ?? 'Unknown';
        info['identifier_for_vendor'] = iosInfo.identifierForVendor ?? 'Unknown';
      }
    } catch (e) {
      info['error'] = 'Could not retrieve device info: $e';
    }
    
    return info;
  }

  /// Clear the stored device ID (useful for testing or resetting)
  static Future<void> clearStoredDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
    debugPrint('Cleared stored device ID');
  }
}

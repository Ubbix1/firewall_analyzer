import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/firewall_log.dart';

class FilteredDataStoreService {
  static Future<Directory> _getStoreDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(docDir.path, 'filtered_stores'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> saveFilteredData(String name, List<FirewallLog> logs) async {
    final dir = await _getStoreDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_$timestamp.json';
    final file = File(path.join(dir.path, fileName));

    final List<Map<String, dynamic>> jsonData = logs.map((log) => log.toMap()).toList();
    await file.writeAsString(jsonEncode(jsonData), flush: true);
    return file.path;
  }

  static Future<List<File>> getStoredFiles() async {
    final dir = await _getStoreDirectory();
    final List<FileSystemEntity> entities = await dir.list().toList();
    final files = entities.whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  static Future<void> deleteFile(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<void> clearAll() async {
    final dir = await _getStoreDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/firewall_log.dart';
import '../models/recent_file_entry.dart';
import '../models/saved_suspicious_log_entry.dart';
import 'log_analysis_service.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;
  static const _databaseName = 'firewall_logs.db';
  static const _databaseVersion = 7;
  static const logsTable = 'logs';
  static const recentFilesTable = 'recent_files';
  static const savedSuspiciousLogsTable = 'saved_suspicious_logs';
  static const settingsTable = 'settings';
  
  // Serialize all database access to prevent locking errors.
  // SQLite (via sqflite) is single-writer-safe, but concurrent reads/writes
  // from different threads/isolates can trigger lock warnings or timeouts.
  static Future<void> _dbQueue = Future.value();

  DatabaseHelper._internal();

  /// Runs a database operation within the serialized queue.
  /// Use this for ALL database access to prevent "database is locked" errors.
  Future<T> runQueued<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _dbQueue = _dbQueue.then((_) async {
      try {
        // Yield to the event loop before each operation to prevent starvation.
        await Future<void>.delayed(Duration.zero);
        final result = await operation();
        completer.complete(result);
      } catch (e, stack) {
        debugPrint('❌ DB Queue Operation Error: $e\n$stack');
        completer.completeError(e, stack);
      }
    });
    return completer.future;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async => _ensureSchema(db),
      onOpen: (db) async => _ensureSchema(db),
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $logsTable('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'ipAddress TEXT NOT NULL, '
      'timestamp TEXT NOT NULL, '
      'method TEXT NOT NULL, '
      'requestMethod TEXT NOT NULL, '
      'request TEXT NOT NULL DEFAULT "", '
      'status TEXT NOT NULL, '
      'bytes TEXT NOT NULL, '
      'userAgent TEXT NOT NULL, '
      'parameters TEXT NOT NULL, '
      'url TEXT NOT NULL, '
      'responseCode INTEGER NOT NULL, '
      'responseSize INTEGER NOT NULL, '
      'country TEXT NOT NULL DEFAULT "", '
      'latitude REAL, '
      'longitude REAL, '
      'requestRateAnomaly INTEGER NOT NULL DEFAULT 0, '
      'source TEXT NOT NULL DEFAULT ""'
      ')',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $recentFilesTable('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'path TEXT NOT NULL UNIQUE, '
      'fileName TEXT NOT NULL, '
      'lastOpened TEXT NOT NULL, '
      'logCount INTEGER NOT NULL DEFAULT 0'
      ')',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $savedSuspiciousLogsTable('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'signature TEXT NOT NULL UNIQUE, '
      'sourceLabel TEXT NOT NULL, '
      'savedAt TEXT NOT NULL, '
      'riskLevel TEXT NOT NULL, '
      'logJson TEXT NOT NULL'
      ')',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $settingsTable('
      'key TEXT PRIMARY KEY, '
      'value TEXT NOT NULL'
      ')',
    );
  }

  Future<void> _ensureSchema(Database db) async {
    await _createSchema(db);

    final columns = (await db.rawQuery('PRAGMA table_info($logsTable)'))
        .map((column) => column['name']?.toString() ?? '')
        .toSet();
    final missingColumns = <String, String>{
      'request':
          'ALTER TABLE $logsTable ADD COLUMN request TEXT NOT NULL DEFAULT ""',
      'country':
          'ALTER TABLE $logsTable ADD COLUMN country TEXT NOT NULL DEFAULT ""',
      'latitude':
          'ALTER TABLE $logsTable ADD COLUMN latitude REAL',
      'longitude':
          'ALTER TABLE $logsTable ADD COLUMN longitude REAL',
      'requestRateAnomaly':
          'ALTER TABLE $logsTable ADD COLUMN requestRateAnomaly INTEGER NOT NULL DEFAULT 0',
      // Backend-authority columns — NULL means no backend verdict yet (safe fallback)
      'backendAlerts':
          'ALTER TABLE $logsTable ADD COLUMN backendAlerts TEXT',
      'backendThreatLevel':
          'ALTER TABLE $logsTable ADD COLUMN backendThreatLevel TEXT',
      'backendSeverityScore':
          'ALTER TABLE $logsTable ADD COLUMN backendSeverityScore INTEGER',
      'source':
          'ALTER TABLE $logsTable ADD COLUMN source TEXT NOT NULL DEFAULT \"\"',
    };

    for (final entry in missingColumns.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(entry.value);
      }
    }
  }

  Future<int> insertLog(FirewallLog log) async {
    return runQueued(() async {
      final db = await database;
      final values = Map<String, dynamic>.from(log.toMap())..remove('id');
      return db.insert(
        logsTable,
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<FirewallLog>> getLogs() async {
    return runQueued(() async {
      final db = await database;
      final maps = await db.query(logsTable, orderBy: 'id DESC');
      return List.generate(maps.length, (i) {
        return FirewallLog.fromMap(maps[i]);
      });
    });
  }

  Future<List<FirewallLog>> replaceAllLogs(List<FirewallLog> logs) async {
    return runQueued(() async {
      final db = await database;
      await db.transaction((txn) async {
        await txn.delete(logsTable);
        final batch = txn.batch();
        for (final log in logs) {
          final values = Map<String, dynamic>.from(log.toMap())..remove('id');
          batch.insert(
            logsTable,
            values,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });

      // Invalidate the analysis cache — all IDs have changed after a full replace.
      LogAnalysisService.clearCache();
      
      // Since we are already in the queue, we can't call getLogs() (which also queues)
      // We must access the DB directly or use a non-queued internal method.
      final maps = await db.query(logsTable, orderBy: 'id DESC');
      return maps.map(FirewallLog.fromMap).toList();
    });
  }

  Future<void> clearLogs() async {
    return runQueued(() async {
      final db = await database;
      await db.delete(logsTable);
      LogAnalysisService.clearCache();
    });
  }

  Future<void> updateLog(FirewallLog log) async {
    return runQueued(() async {
      final db = await database;
      if (log.id == null) {
        final values = Map<String, dynamic>.from(log.toMap())..remove('id');
        await db.insert(logsTable, values, conflictAlgorithm: ConflictAlgorithm.replace);
        return;
      }

      await db.update(
        logsTable,
        log.toMap(),
        where: 'id = ?',
        whereArgs: [log.id],
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Evict stale cached analysis for this specific log.
      LogAnalysisService.evict(log.id);
    });
  }

  Future<void> upsertLogsBatch(List<FirewallLog> logs) async {
    if (logs.isEmpty) return;
    
    // Chunk size — smaller chunks keep the DB responsive for other tasks in the queue.
    const chunkSize = 500;
    
    // We don't queue the entire process as one big runQueued because we want to yield
    // between chunks. Instead, we split the work into multiple queued tasks.
    for (var i = 0; i < logs.length; i += chunkSize) {
      final end = (i + chunkSize < logs.length) ? i + chunkSize : logs.length;
      final chunk = logs.sublist(i, end);
      
      await runQueued(() async {
        final db = await database;
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (final log in chunk) {
            final values = log.toMap();
            if (log.id == null) {
              values.remove('id');
              batch.insert(
                logsTable,
                values,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            } else {
              batch.update(
                logsTable,
                values,
                where: 'id = ?',
                whereArgs: [log.id],
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              LogAnalysisService.evict(log.id);
            }
          }
          await batch.commit(noResult: true);
        });
      });
    }
  }

  Future<void> deleteLog(int id) async {
    return runQueued(() async {
      final db = await database;
      await db.delete(
        logsTable,
        where: 'id = ?',
        whereArgs: [id],
      );
      // Evict stale cached analysis for the deleted log.
      LogAnalysisService.evict(id);
    });
  }

  Future<void> upsertRecentFile(RecentFileEntry entry) async {
    return runQueued(() async {
      final db = await database;
      final values = Map<String, dynamic>.from(entry.toMap())..remove('id');
      await db.insert(
        recentFilesTable,
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<RecentFileEntry>> getRecentFiles() async {
    return runQueued(() async {
      final db = await database;
      final maps = await db.query(recentFilesTable, orderBy: 'lastOpened DESC');
      return maps.map(RecentFileEntry.fromMap).toList();
    });
  }

  Future<void> deleteRecentFile(String filePath) async {
    return runQueued(() async {
      final db = await database;
      await db.delete(
        recentFilesTable,
        where: 'path = ?',
        whereArgs: [filePath],
      );
    });
  }

  Future<void> upsertSavedSuspiciousLog(SavedSuspiciousLogEntry entry) async {
    return runQueued(() async {
      final db = await database;
      final values = Map<String, dynamic>.from(entry.toMap())..remove('id');
      await db.insert(
        savedSuspiciousLogsTable,
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<SavedSuspiciousLogEntry>> getSavedSuspiciousLogs() async {
    return runQueued(() async {
      final db = await database;
      final maps = await db.query(savedSuspiciousLogsTable, orderBy: 'savedAt DESC');
      return maps.map(SavedSuspiciousLogEntry.fromMap).toList();
    });
  }

  Future<void> deleteSavedSuspiciousLog(String signature) async {
    return runQueued(() async {
      final db = await database;
      await db.delete(
        savedSuspiciousLogsTable,
        where: 'signature = ?',
        whereArgs: [signature],
      );
    });
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    return runQueued(() async {
      final db = await database;
      await db.insert(
        settingsTable,
        {'key': 'theme_mode', 'value': mode.name},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<ThemeMode> getThemeMode() async {
    return runQueued(() async {
      final db = await database;
      final maps = await db.query(
        settingsTable,
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['theme_mode'],
        limit: 1,
      );

      if (maps.isEmpty) {
        return ThemeMode.system;
      }

      final value = maps.first['value']?.toString() ?? ThemeMode.system.name;
      return ThemeMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => ThemeMode.system,
      );
    });
  }
}

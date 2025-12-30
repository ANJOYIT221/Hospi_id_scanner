import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class CrashLoggerService {
  static final CrashLoggerService _instance = CrashLoggerService._internal();
  factory CrashLoggerService() => _instance;
  CrashLoggerService._internal();

  bool _isInitialized = false;
  Directory? _crashLogsDir;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final Directory appDir = await getApplicationDocumentsDirectory();

      _crashLogsDir = Directory('${appDir.path}/crash_logs');
      if (!await _crashLogsDir!.exists()) {
        await _crashLogsDir!.create(recursive: true);
      }

      FlutterError.onError = (FlutterErrorDetails details) {
        _logCrash(
          error: details.exception,
          stackTrace: details.stack,
          context: 'Flutter Framework Error',
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        _logCrash(
          error: error,
          stackTrace: stack,
          context: 'Platform Error',
        );
        return true;
      };

      _isInitialized = true;
      print('✅ CrashLogger initialisé : ${_crashLogsDir!.path}');
    } catch (e) {
      print('❌ Erreur initialisation CrashLogger: $e');
    }
  }

  Future<void> _logCrash({
    required dynamic error,
    StackTrace? stackTrace,
    String context = 'Unknown',
  }) async {
    if (_crashLogsDir == null) return;

    try {
      final now = DateTime.now();
      final timestamp = _formatTimestamp(now);
      final filename = 'crash_${_formatFilename(now)}.txt';
      final file = File('${_crashLogsDir!.path}/$filename');

      final ramInfo = await _getRAMInfo();
      final connectivity = await _getConnectivityInfo();

      final logContent = StringBuffer();
      logContent.writeln('=' * 60);
      logContent.writeln('CRASH REPORT');
      logContent.writeln('=' * 60);
      logContent.writeln('Date: $timestamp');
      logContent.writeln('App: ${Platform.isAndroid ? 'Android' : 'Unknown'}');
      logContent.writeln('Context: $context');
      logContent.writeln('');
      logContent.writeln('SYSTÈME:');
      logContent.writeln('- RAM utilisée: ${ramInfo['used']}');
      logContent.writeln('- RAM libre: ${ramInfo['free']}');
      logContent.writeln('');
      logContent.writeln('CONNECTIVITÉ:');
      logContent.writeln('- État: $connectivity');
      logContent.writeln('');
      logContent.writeln('ERREUR:');
      logContent.writeln('Type: ${error.runtimeType}');
      logContent.writeln('Message: $error');
      logContent.writeln('');
      logContent.writeln('STACK TRACE:');
      logContent.writeln(stackTrace?.toString() ?? 'Non disponible');
      logContent.writeln('=' * 60);

      await file.writeAsString(logContent.toString());
      print('💾 Crash loggé: ${file.path}');
    } catch (e) {
      print('❌ Erreur log crash: $e');
    }
  }

  Future<Map<String, String>> _getRAMInfo() async {
    try {
      final rssBytes = ProcessInfo.currentRss;
      final usedMB = (rssBytes / (1024 * 1024)).toStringAsFixed(2);

      return {
        'used': '$usedMB MB',
        'free': 'N/A',
      };
    } catch (e) {
      return {'used': 'N/A', 'free': 'N/A'};
    }
  }

  Future<String> _getConnectivityInfo() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult is List) {
        if (connectivityResult.contains(ConnectivityResult.wifi)) {
          return 'WiFi connecté';
        } else if (connectivityResult.contains(ConnectivityResult.mobile)) {
          return 'Données mobiles';
        } else if (connectivityResult.contains(ConnectivityResult.ethernet)) {
          return 'Ethernet';
        } else {
          return 'Hors ligne';
        }
      } else {
        if (connectivityResult == ConnectivityResult.wifi) {
          return 'WiFi connecté';
        } else if (connectivityResult == ConnectivityResult.mobile) {
          return 'Données mobiles';
        } else if (connectivityResult == ConnectivityResult.ethernet) {
          return 'Ethernet';
        } else {
          return 'Hors ligne';
        }
      }
    } catch (e) {
      return 'Erreur vérification';
    }
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  }

  String _formatFilename(DateTime dt) {
    return '${dt.year}${_pad(dt.month)}${_pad(dt.day)}_'
        '${_pad(dt.hour)}${_pad(dt.minute)}${_pad(dt.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  Future<List<File>> getCrashLogs() async {
    if (_crashLogsDir == null || !await _crashLogsDir!.exists()) {
      return [];
    }

    try {
      final files = _crashLogsDir!
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.txt'))
          .toList();

      files.sort((a, b) => b.path.compareTo(a.path));

      return files;
    } catch (e) {
      print('❌ Erreur récupération logs: $e');
      return [];
    }
  }

  Future<void> deleteAllLogs() async {
    if (_crashLogsDir == null || !await _crashLogsDir!.exists()) {
      return;
    }

    try {
      final files = await getCrashLogs();
      for (final file in files) {
        await file.delete();
      }
      print('🗑️ Tous les logs supprimés');
    } catch (e) {
      print('❌ Erreur suppression logs: $e');
    }
  }

  Future<void> deleteLog(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
        print('🗑️ Log supprimé: ${file.path}');
      }
    } catch (e) {
      print('❌ Erreur suppression log: $e');
    }
  }

  Future<String> readLogContent(File file) async {
    try {
      return await file.readAsString();
    } catch (e) {
      return 'Erreur lecture fichier: $e';
    }
  }
}
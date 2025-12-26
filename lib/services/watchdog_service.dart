import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WatchdogService {
  static final WatchdogService _instance = WatchdogService._internal();
  factory WatchdogService() => _instance;
  WatchdogService._internal();

  static const _channel = MethodChannel('hospismart/watchdog');

  Timer? _healthCheckTimer;
  Timer? _memoryCleanupTimer;
  DateTime _lastHealthCheck = DateTime.now();
  bool _isHealthy = true;
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 3;
  static const Duration _healthCheckInterval = Duration(seconds: 30);
  static const Duration _freezeThreshold = Duration(minutes: 10);
  static const Duration _memoryCleanupInterval = Duration(hours: 1);

  void start() {
    print('🐕 ========================================');
    print('🐕 WATCHDOG DÉMARRÉ');
    print('🐕 Surveillance toutes les ${_healthCheckInterval.inSeconds}s');
    print('🐕 Redémarrage si freeze > ${_freezeThreshold.inMinutes} minutes');
    print('🐕 Nettoyage mémoire toutes les ${_memoryCleanupInterval.inHours}h');
    print('==========================================');

    _startHealthCheck();
    _startMemoryCleanup();
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      _checkHealth();
    });
  }

  void _startMemoryCleanup() {
    _memoryCleanupTimer?.cancel();
    _memoryCleanupTimer = Timer.periodic(_memoryCleanupInterval, (_) {
      _cleanupMemory();
    });
  }

  void heartbeat() {
    _lastHealthCheck = DateTime.now();
    if (!_isHealthy) {
      print('💚 App de nouveau en bonne santé');
      _isHealthy = true;
      _consecutiveFailures = 0;
    }
  }

  void _checkHealth() {
    final now = DateTime.now();
    final timeSinceLastCheck = now.difference(_lastHealthCheck);

    if (timeSinceLastCheck > _freezeThreshold) {
      _consecutiveFailures++;
      _isHealthy = false;

      print('⚠️ ========================================');
      print('⚠️ FREEZE DÉTECTÉ !');
      print('⚠️ Dernière activité: ${timeSinceLastCheck.inMinutes}min ${timeSinceLastCheck.inSeconds % 60}s');
      print('⚠️ Tentatives échouées: $_consecutiveFailures/$_maxConsecutiveFailures');
      print('==========================================');

      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        print('🔴 ========================================');
        print('🔴 REDÉMARRAGE AUTOMATIQUE DE L\'APP');
        print('🔴 Raison: Freeze prolongé (${timeSinceLastCheck.inMinutes}min)');
        print('==========================================');
        _restartApp();
      }
    } else {
      if (_consecutiveFailures > 0 && timeSinceLastCheck.inSeconds < 60) {
        print('✅ App répond normalement (délai: ${timeSinceLastCheck.inSeconds}s)');
        _consecutiveFailures = 0;
      }
    }
  }

  void _cleanupMemory() {
    print('🧹 ========================================');
    print('🧹 NETTOYAGE MÉMOIRE PÉRIODIQUE');

    try {
      final before = ProcessInfo.currentRss ~/ (1024 * 1024);
      print('🧹 Mémoire avant: ${before}MB');

      _forceGarbageCollection();

      Future.delayed(const Duration(seconds: 2), () {
        final after = ProcessInfo.currentRss ~/ (1024 * 1024);
        print('🧹 Mémoire après: ${after}MB');
        final freed = before - after;
        if (freed > 0) {
          print('🧹 Libéré: ${freed}MB');
        } else {
          print('🧹 Pas de mémoire libérée (déjà optimisé)');
        }
        print('==========================================');
      });
    } catch (e) {
      print('⚠️ Erreur nettoyage mémoire: $e');
      print('==========================================');
    }
  }

  void _forceGarbageCollection() {
    try {
      final List<List<int>> temp = [];
      for (int i = 0; i < 100; i++) {
        temp.add(List.filled(1000, 0));
      }
      temp.clear();
    } catch (_) {}
  }

  Future<void> _restartApp() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('restartApp');
      } else {
        exit(0);
      }
    } catch (e) {
      print('❌ Erreur redémarrage via Platform Channel: $e');
      print('🔄 Tentative de redémarrage forcé...');
      exit(0);
    }
  }

  void logError(String context, dynamic error) {
    print('❌ [$context] Erreur: $error');
    print('🕐 Timestamp: ${DateTime.now().toIso8601String()}');
    heartbeat();
  }

  void logInfo(String message) {
    print('ℹ️ $message');
    heartbeat();
  }

  void stop() {
    print('🐕 Arrêt du watchdog');
    _healthCheckTimer?.cancel();
    _memoryCleanupTimer?.cancel();
  }
}
import 'dart:async';
import 'package:flutter/material.dart';

class WatchdogService {
  static final WatchdogService _instance = WatchdogService._internal();
  factory WatchdogService() => _instance;
  WatchdogService._internal();

  BuildContext? _context;

  // Méthode pour définir le contexte (ne fait rien mais reste compatible)
  void setContext(BuildContext context) {
    _context = context;
  }

  // Démarrage du watchdog (neutralisé - ne fait rien)
  void start() {
    print('🐕 ========================================');
    print('🐕 WATCHDOG DÉSACTIVÉ (mode neutre)');
    print('🐕 Aucune surveillance active');
    print('🐕 Aucun redémarrage automatique');
    print('==========================================');
  }

  // Arrêt du watchdog (ne fait rien)
  void stop() {
    print('🐕 Watchdog arrêté (était déjà inactif)');
  }

  // Heartbeat (ne fait rien mais reste compatible)
  void heartbeat() {
    // Ne fait rien - méthode neutre
  }

  // Log d'erreur (affiche juste le message sans action)
  void logError(String context, dynamic error) {
    print('❌ [$context] Erreur: $error');
    print('🕐 Timestamp: ${DateTime.now().toIso8601String()}');
    // Pas d'action, juste le log
  }

  // Log d'info (affiche juste le message sans action)
  void logInfo(String message) {
    print('ℹ️ $message');
    // Pas d'action, juste le log
  }
}
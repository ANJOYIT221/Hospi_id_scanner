// =======================
// splash_wrapper.dart (SCANNER) - SERVEUR WEBSOCKET PERMANENT
// Le scanner reste connecté et attend les requêtes de la borne
// Déclenchement automatique de l'appareil photo à la connexion
// =======================

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'id_scanner_screen.dart';

class SplashWrapper extends StatefulWidget {
  const SplashWrapper({super.key});

  @override
  _SplashWrapperState createState() => _SplashWrapperState();
}

class _SplashWrapperState extends State<SplashWrapper> with TickerProviderStateMixin {
  bool showLanding = true;

  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _connectionPulseController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _connectionPulseAnimation;

  HttpServer? _server;
  WebSocket? _borneSocket;
  Stream<dynamic>? _broadcastStream;
  bool _isServerRunning = false;
  bool _borneConnected = false;

  String _localIP = "Recherche...";
  static const int _serverPort = 3000;

  bool _autoNavigated = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startWebSocketServer();
  }

  void _initAnimations() {
    _fadeController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);
    _scaleController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _slideController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _pulseController = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this)..repeat(reverse: true);
    _connectionPulseController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _connectionPulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _connectionPulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 300), () => _scaleController.forward());
    Future.delayed(const Duration(milliseconds: 600), () => _slideController.forward());
  }

  // ============================================
  // 🆕 SERVEUR WEBSOCKET PERMANENT
  // ============================================

  Future<void> _startWebSocketServer() async {
    try {
      // Récupérer l'IP locale
      _localIP = await _getLocalIPv4() ?? "Inconnue";

      // Démarrer le serveur WebSocket
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _serverPort);

      setState(() => _isServerRunning = true);

      print('✅ ========================================');
      print('✅ SCANNER - Serveur WebSocket démarré');
      print('✅ Adresse: ws://$_localIP:$_serverPort');
      print('✅ ========================================');

      // Écouter les connexions entrantes
      _server!.transform(WebSocketTransformer()).listen((WebSocket socket) {
        print('🔗 BORNE connectée !');

        setState(() {
          _borneSocket = socket;
          _borneConnected = true;
        });

        // 🆕 DÉCLENCHEMENT AUTOMATIQUE DE L'APPAREIL PHOTO
        if (!_autoNavigated && mounted && showLanding) {
          _autoNavigated = true;
          print('📸 Déclenchement automatique de l\'écran de scan');
          _handleTap();
        }

        // Créer un broadcast stream
        _broadcastStream = socket.asBroadcastStream();

        // Écouter les messages de la borne
        _broadcastStream!.listen(
          _handleBorneMessage,
          onDone: () {
            print('🔌 BORNE déconnectée');
            setState(() {
              _borneConnected = false;
              _borneSocket = null;
              _broadcastStream = null;
              _autoNavigated = false; // Réinitialiser pour la prochaine connexion
            });
          },
          onError: (error) {
            print('❌ Erreur WebSocket: $error');
            setState(() {
              _borneConnected = false;
              _borneSocket = null;
              _broadcastStream = null;
              _autoNavigated = false;
            });
          },
        );
      });

    } catch (e) {
      print('❌ Erreur démarrage serveur: $e');
      setState(() => _isServerRunning = false);
    }
  }

  Future<String?> _getLocalIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.address.startsWith('127.')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('❌ Erreur récupération IP: $e');
    }
    return null;
  }

  // ============================================
  // 📨 GESTION DES MESSAGES DE LA BORNE
  // ============================================

  void _handleBorneMessage(dynamic message) {
    try {
      print('📨 SCANNER ← BORNE : Message reçu');

      final data = jsonDecode(message);
      if (data is! Map) {
        print('⚠️ Format invalide');
        return;
      }

      final action = data['action'];
      print('📨 Action: $action');

      // ===== DEMANDE DE CHECK-IN =====
      if (action == 'start_checkin') {
        print('🚀 Demande de check-in reçue');

        // Naviguer automatiquement vers l'écran de scan
        if (!_autoNavigated && mounted && showLanding) {
          _autoNavigated = true;
          _handleTap();
        }
        return;
      }

      // ===== AUTRES ACTIONS (à compléter selon tes besoins) =====
      print('⚠️ Action non gérée: $action');

    } catch (e) {
      print('❌ Erreur handleBorneMessage: $e');
    }
  }

  // ============================================
  // 🔄 ENVOI DE MESSAGES À LA BORNE
  // ============================================

  void _sendToBorne(Map<String, dynamic> data) {
    if (_borneSocket == null || _borneSocket!.readyState != WebSocket.open) {
      print('❌ Borne non connectée');
      return;
    }

    try {
      _borneSocket!.add(jsonEncode(data));
      print('📤 SCANNER → BORNE : ${data['action']}');
    } catch (e) {
      print('❌ Erreur envoi message: $e');
    }
  }

  // ============================================
  // UI
  // ============================================

  void _handleTap() {
    setState(() {
      showLanding = false;
    });
  }

  void _returnToSplash() {
    setState(() {
      showLanding = true;
      _autoNavigated = false;
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _connectionPulseController.dispose();
    _server?.close();
    _borneSocket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: showLanding ? _handleTap : null,
      child: Scaffold(
        body: showLanding
            ? _buildSplashScreen()
            : IdScannerScreen(
          broadcastStream: _broadcastStream,
          webSocket: _borneSocket,
          isConnected: _borneConnected,
          onReturnToSplash: _returnToSplash,
        ),
      ),
    );
  }

  Widget _buildSplashScreen() {
    return Stack(
      children: [
        // Fond dégradé
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1e3c72),
                Color(0xFF2a5298),
                Color(0xFF7e22ce),
              ],
            ),
          ),
        ),

        // Badge de statut serveur (en haut à droite)
        Positioned(
          top: 40,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: _isServerRunning
                    ? const Color(0xFF10B981).withOpacity(0.8)
                    : const Color(0xFFE63946).withOpacity(0.8),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _connectionPulseAnimation,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _isServerRunning ? const Color(0xFF10B981) : const Color(0xFFE63946),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isServerRunning ? const Color(0xFF10B981) : const Color(0xFFE63946))
                              .withOpacity(0.6),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isServerRunning ? "Serveur actif" : "Serveur inactif",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (_isServerRunning)
                      Text(
                        _localIP,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Badge connexion borne (en haut à gauche) - RÉDUIT
        Positioned(
          top: 40,
          left: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _borneConnected
                    ? const Color(0xFF10B981).withOpacity(0.8)
                    : const Color(0xFFFFB800).withOpacity(0.8),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _borneConnected ? Icons.link : Icons.link_off,
                  color: _borneConnected ? const Color(0xFF10B981) : const Color(0xFFFFB800),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _borneConnected ? "Connectée" : "En attente",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Contenu principal
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.2),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.document_scanner_outlined,
                    size: 100,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 50),
              SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      const Text(
                        "HOSPI SMART",
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 4,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              offset: Offset(0, 4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Scanner",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w300,
                          color: Colors.white.withOpacity(0.9),
                          letterSpacing: 6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.lock_outline,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _isServerRunning
                                  ? "Système de vérification d'identité sécurisé"
                                  : "Démarrage du serveur...",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withOpacity(0.95),
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
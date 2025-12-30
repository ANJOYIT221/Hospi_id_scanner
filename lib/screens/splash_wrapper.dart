import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'id_scanner_screen.dart';
import 'checkout.dart';
import '../services/watchdog_service.dart';
import '../services/crash_logger_service.dart';
import '../screens/crash_logs_screen.dart';

class SplashWrapper extends StatefulWidget {
  const SplashWrapper({super.key});

  @override
  _SplashWrapperState createState() => _SplashWrapperState();
}

class _SplashWrapperState extends State<SplashWrapper> with TickerProviderStateMixin {
  bool showLanding = true;
  String _currentScreen = 'checkin';

  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _connectionPulseController;
  late AnimationController _gradientController;
  late AnimationController _opacityController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _connectionPulseAnimation;
  late Animation<double> _gradientAnimation;
  late Animation<double> _opacityAnimation;

  HttpServer? _server;
  WebSocket? _borneSocket;
  Stream<dynamic>? _broadcastStream;
  bool _isServerRunning = false;
  bool _borneConnected = false;

  String _localIP = "Recherche...";
  static const int _serverPort = 3000;

  bool _autoNavigated = false;

  Timer? _gradientTrigger;
  Timer? _watchdogHeartbeat;

  final WatchdogService _watchdog = WatchdogService();
  final CrashLoggerService _crashLogger = CrashLoggerService();

  int _longPressCount = 0;
  Timer? _longPressResetTimer;
  bool _showExitCounter = false;

  int _tapCount = 0;
  Timer? _tapResetTimer;
  bool _showLogsCounter = false;

  static const Color errorRed = Color(0xFFFF3B30);
  static const Color successGreen = Color(0xFF34C759);

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startWebSocketServer();
    _startGradientAnimation();
    _startWatchdog();
    _initCrashLogger();
  }

  Future<void> _initCrashLogger() async {
    await _crashLogger.initialize();
    print('✅ Crash Logger initialisé (Scanner)');
  }

  void _handleLongPress() {
    _longPressCount++;
    _longPressResetTimer?.cancel();

    if (_longPressCount == 1) {
      setState(() => _showExitCounter = true);
    }

    if (_longPressCount >= 7) {
      _exitApp();
      return;
    }

    _longPressResetTimer = Timer(const Duration(seconds: 3), () {
      setState(() {
        _longPressCount = 0;
        _showExitCounter = false;
      });
    });
  }

  void _handleTap() {
    _tapCount++;
    _tapResetTimer?.cancel();

    if (_tapCount == 1) {
      setState(() => _showLogsCounter = true);
    }

    if (_tapCount >= 5) {
      _openCrashLogs();
      return;
    }

    _tapResetTimer = Timer(const Duration(seconds: 3), () {
      setState(() {
        _tapCount = 0;
        _showLogsCounter = false;
      });
    });
  }

  Future<void> _exitApp() async {
    _longPressResetTimer?.cancel();
    setState(() {
      _longPressCount = 0;
      _showExitCounter = false;
    });

    try {
      print('🚪 Sortie de l\'application (7 long press détectés)');
      SystemNavigator.pop();
    } catch (e) {
      print('❌ Erreur sortie app: $e');
      _showSnackBar("Erreur lors de la sortie", errorRed);
    }
  }

  void _openCrashLogs() {
    print('📋 Ouverture des Crash Logs (5 taps détectés)');

    setState(() {
      _tapCount = 0;
      _showLogsCounter = false;
    });
    _tapResetTimer?.cancel();

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CrashLogsScreen()),
    );
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(14),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _initAnimations() {
    _fadeController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);
    _scaleController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _slideController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _pulseController = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this)..repeat(reverse: true);
    _connectionPulseController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat(reverse: true);

    _gradientController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _opacityController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat(reverse: true);

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

    _gradientAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _gradientController,
      curve: Curves.easeInOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _opacityController,
      curve: Curves.easeInOut,
    ));

    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 300), () => _scaleController.forward());
    Future.delayed(const Duration(milliseconds: 600), () => _slideController.forward());
  }

  void _startGradientAnimation() {
    _gradientTrigger = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && showLanding) {
        _gradientController.forward(from: 0.0).then((_) {
          if (mounted) {
            _gradientController.reverse();
          }
        });
      }
    });
  }

  void _startWatchdog() {
    _watchdog.start();

    _watchdogHeartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      _watchdog.heartbeat();
    });

    _watchdog.logInfo('Scanner app démarrée');
  }

  Future<void> _startWebSocketServer() async {
    try {
      _localIP = await _getLocalIPv4() ?? "Inconnue";
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _serverPort);

      setState(() => _isServerRunning = true);

      print('✅ ========================================');
      print('✅ SCANNER - Serveur WebSocket démarré');
      print('✅ Adresse: ws://$_localIP:$_serverPort');
      print('✅ ========================================');

      _watchdog.logInfo('Serveur WebSocket démarré sur $_localIP:$_serverPort');

      _server!.transform(WebSocketTransformer()).listen((WebSocket socket) {
        print('🔗 BORNE connectée !');

        setState(() {
          _borneSocket = socket;
          _borneConnected = true;
        });

        _watchdog.logInfo('Borne connectée');

        _broadcastStream = socket.asBroadcastStream();

        _broadcastStream!.listen(
          _handleBorneMessage,
          onDone: () {
            print('🔌 BORNE déconnectée');
            _watchdog.logInfo('Borne déconnectée');
            setState(() {
              _borneConnected = false;
              _borneSocket = null;
              _broadcastStream = null;
              _autoNavigated = false;
            });
          },
          onError: (error) {
            _watchdog.logError('WebSocket', error);
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
      _watchdog.logError('Démarrage serveur', e);
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
      _watchdog.logError('Récupération IP', e);
    }
    return null;
  }

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
      _watchdog.heartbeat();

      if (action == 'start_checkin') {
        print('🚀 Demande de check-in reçue');

        if (!_autoNavigated && mounted && showLanding) {
          _autoNavigated = true;
          _currentScreen = 'checkin';
          _handleNavigation();
        }
        return;
      }

      if (action == 'start_checkout') {
        print('🚀 Demande de checkout reçue');

        if (!_autoNavigated && mounted && showLanding) {
          _autoNavigated = true;
          _currentScreen = 'checkout';
          _handleNavigation();
        }
        return;
      }

      print('⚠️ Action non gérée: $action');

    } catch (e) {
      _watchdog.logError('handleBorneMessage', e);
    }
  }

  void _sendToBorne(Map<String, dynamic> data) {
    if (_borneSocket == null || _borneSocket!.readyState != WebSocket.open) {
      print('❌ Borne non connectée');
      return;
    }

    try {
      _borneSocket!.add(jsonEncode(data));
      print('📤 SCANNER → BORNE : ${data['action']}');
      _watchdog.heartbeat();
    } catch (e) {
      _watchdog.logError('Envoi message', e);
    }
  }

  void _handleNavigation() {
    setState(() {
      showLanding = false;
    });
    _watchdog.logInfo('Navigation vers ${_currentScreen == 'checkout' ? 'CheckoutScreen' : 'IdScannerScreen'}');
  }

  void _returnToSplash() {
    setState(() {
      showLanding = true;
      _autoNavigated = false;
      _currentScreen = 'checkin';
    });
    _watchdog.logInfo('Retour au splash screen');
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _connectionPulseController.dispose();
    _gradientController.dispose();
    _opacityController.dispose();
    _gradientTrigger?.cancel();
    _watchdogHeartbeat?.cancel();
    _longPressResetTimer?.cancel();
    _tapResetTimer?.cancel();
    _server?.close();
    _borneSocket?.close();
    _watchdog.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: showLanding ? _handleLongPress : null,
      onTap: showLanding ? _handleTap : null,
      child: Scaffold(
        body: showLanding
            ? _buildSplashScreen()
            : _currentScreen == 'checkout'
            ? CheckoutScreen(
          socket: _borneSocket,
          isConnected: _borneConnected,
          onReturnToSplash: _returnToSplash,
        )
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
        AnimatedBuilder(
          animation: _gradientAnimation,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(
                      const Color(0xFF1e3c72),
                      const Color(0xFF2a5298),
                      _gradientAnimation.value,
                    )!,
                    Color.lerp(
                      const Color(0xFF2a5298),
                      const Color(0xFF7e22ce),
                      _gradientAnimation.value,
                    )!,
                    Color.lerp(
                      const Color(0xFF7e22ce),
                      const Color(0xFF1e3c72),
                      _gradientAnimation.value,
                    )!,
                  ],
                ),
              ),
            );
          },
        ),

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

        if (_showExitCounter)
          Positioned(
            top: 120,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(
                'Exit: $_longPressCount/7',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

        if (_showLogsCounter)
          Positioned(
            top: 120,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(
                'Logs: $_tapCount/5',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: AnimatedBuilder(
                  animation: _opacityAnimation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _opacityAnimation.value,
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
                    );
                  },
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
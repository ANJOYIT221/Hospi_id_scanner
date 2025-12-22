// =======================
// splash_wrapper.dart (Scanner) - Cache IP pour optimiser découverte UDP
// ✅ CORRIGÉ : Cache utilisé uniquement pour accélérer la découverte UDP
// =======================

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  WebSocket? _socket;
  Stream<dynamic>? _broadcastStream;
  bool _isConnected = false;
  String _receiverIP = "0.0.0.0";
  int _receiverPort = 3000;

  bool _autoNavigated = false;

  static const String _cachedIpKey = 'cached_receiver_ip';
  static const String _cachedPortKey = 'cached_receiver_port';
  static const String _cachedMacKey = 'cached_receiver_mac';

  static const int _discoveryPort = 3001;
  static const String _wantedMac = "DC:62:94:38:3C:C0";
  static final InternetAddress _mcastAddr = InternetAddress('239.255.255.250');
  RawDatagramSocket? _mcastListenSocket;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startMulticastListener();
    _runDiscoveryAndConnect();
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

  Future<String?> _getLocalIPv4() async {
    final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in ifaces) {
      for (final a in iface.addresses) {
        if (a.type == InternetAddressType.IPv4 && !a.address.startsWith('127.')) {
          return a.address;
        }
      }
    }
    return null;
  }

  InternetAddress _guessBroadcast(String localIp) {
    final parts = localIp.split('.');
    if (parts.length == 4) {
      return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    return InternetAddress('255.255.255.255');
  }

  Future<void> _startMulticastListener() async {
    try {
      _mcastListenSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _discoveryPort);
      _mcastListenSocket!.joinMulticast(_mcastAddr);
      print("👂 Écoute heartbeat multicast sur ${_mcastAddr.address}:$_discoveryPort");

      _mcastListenSocket!.listen((evt) {
        if (evt == RawSocketEvent.read) {
          final d = _mcastListenSocket!.receive();
          if (d == null) return;
          try {
            final payload = utf8.decode(d.data);
            final parsed = jsonDecode(payload);
            if (parsed is Map && parsed['action'] == 'LOUNA_HEARTBEAT') {
              final mac = parsed['mac']?.toString();
              final ip = parsed['ip']?.toString() ?? d.address.address;
              final int port = parsed['port'] is int
                  ? parsed['port']
                  : int.tryParse(parsed['port']?.toString() ?? '3000') ?? 3000;

              print("💓 Heartbeat: mac=$mac ip=$ip port=$port");

              if (mac != null && (_wantedMac.isEmpty || mac == _wantedMac)) {
                final changed = (_receiverIP != ip || _receiverPort != port);
                if (changed) {
                  setState(() {
                    _receiverIP = ip;
                    _receiverPort = port;
                  });
                  if (!_isConnected) {
                    _connectWebSocket();
                  }
                }
              }
            }
          } catch (_) {}
        }
      });
    } catch (e) {
      print("❌ Multicast listener KO: $e");
    }
  }

  Future<void> _saveConnection({String? mac}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedIpKey, _receiverIP);
      await prefs.setInt(_cachedPortKey, _receiverPort);

      if (mac != null) {
        await prefs.setString(_cachedMacKey, mac);
      }

      print('💾 Connexion sauvegardée en cache: $_receiverIP:$_receiverPort (MAC: ${mac ?? "non spécifié"})');
    } catch (e) {
      print('❌ Erreur sauvegarde connexion: $e');
    }
  }

  Future<Map<String, Map<String, dynamic>>> discoverReceivers({
    int timeoutSeconds = 3,
    int repeats = 3,
  }) async {
    final results = <String, Map<String, dynamic>>{};
    RawDatagramSocket? socket;

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final localIp = await _getLocalIPv4();
      final bcastNet = localIp != null ? _guessBroadcast(localIp) : InternetAddress('255.255.255.255');
      final bcastAll = InternetAddress('255.255.255.255');

      final reqBytes = utf8.encode(jsonEncode({
        'action': 'DISCOVER_LOUNA',
        'time': DateTime.now().toIso8601String(),
      }));

      final prefs = await SharedPreferences.getInstance();
      final cachedIp = prefs.getString(_cachedIpKey);
      final cachedPort = prefs.getInt(_cachedPortKey);

      if (cachedIp != null && cachedPort != null) {
        print('📦 Cache trouvé: $cachedIp:$cachedPort');
        print('🎯 Envoi requête UDP directe à l\'IP en cache...');

        try {
          final cachedAddr = InternetAddress(cachedIp);
          socket.send(reqBytes, cachedAddr, _discoveryPort);
          await Future.delayed(const Duration(milliseconds: 100));
          socket.send(reqBytes, cachedAddr, _discoveryPort);

          print('✅ Requête UDP envoyée au cache, attente réponse...');
        } catch (e) {
          print('⚠️ Erreur envoi UDP au cache: $e');
        }
      } else {
        print('ℹ️ Aucun cache trouvé');
      }

      for (int i = 0; i < repeats; i++) {
        socket.send(reqBytes, bcastNet, _discoveryPort);
        socket.send(reqBytes, bcastAll, _discoveryPort);
        await Future.delayed(const Duration(milliseconds: 120));
      }

      final completer = Completer<void>();
      final timer = Timer(Duration(seconds: timeoutSeconds), () {
        if (!completer.isCompleted) completer.complete();
      });

      socket.listen((evt) {
        if (evt == RawSocketEvent.read) {
          final d = socket!.receive();
          if (d == null) return;
          try {
            final payload = utf8.decode(d.data);
            final parsed = jsonDecode(payload);
            final mac = parsed['mac']?.toString();
            final ip = parsed['ip']?.toString() ?? d.address.address;
            final int port = parsed['port'] is int
                ? parsed['port']
                : int.tryParse(parsed['port']?.toString() ?? '3000') ?? 3000;

            if (mac != null && mac.isNotEmpty) {
              results[mac] = {'ip': ip, 'port': port, 'raw': parsed};

              if (ip == cachedIp && port == cachedPort) {
                print("✅ L'IP en cache a répondu ! ($ip:$port)");
              } else {
                print("🔍 Découverte: mac=$mac ip=$ip port=$port");
              }
            }
          } catch (_) {}
        }
      });

      await completer.future;
      timer.cancel();
    } catch (e) {
      print("❌ discoverReceivers error: $e");
    } finally {
      socket?.close();
    }

    return results;
  }

  Future<void> _runDiscoveryAndConnect() async {
    print("🔎 Lancement découverte UDP (avec cache si disponible)…");
    final discovered = await discoverReceivers(timeoutSeconds: 3, repeats: 3);

    if (discovered.isEmpty) {
      print("😕 Aucun récepteur trouvé.");
      return;
    }

    String selectedIp = discovered.values.first['ip'];
    int selectedPort = discovered.values.first['port'];
    String? selectedMac = discovered.keys.first;

    if (_wantedMac.isNotEmpty && discovered.containsKey(_wantedMac)) {
      selectedIp = discovered[_wantedMac]!['ip'];
      selectedPort = discovered[_wantedMac]!['port'];
      selectedMac = _wantedMac;
      print("✅ Récepteur ciblé: $_wantedMac → $selectedIp:$selectedPort");
    }

    setState(() {
      _receiverIP = selectedIp;
      _receiverPort = selectedPort;
    });

    await _connectWebSocket();

    if (_isConnected) {
      await _saveConnection(mac: selectedMac);
    }
  }

  Future<void> _connectWebSocket() async {
    if (_receiverIP == "0.0.0.0" || _receiverIP.trim().isEmpty) {
      print("⏭️ IP inconnue, on ne tente pas la connexion.");
      return;
    }

    for (;;) {
      try {
        final uri = 'ws://$_receiverIP:$_receiverPort';
        print("🔗 [SPLASH] Connexion WebSocket sur $uri …");
        _socket = await WebSocket.connect(uri);

        setState(() => _isConnected = true);
        print("✅ [SPLASH] WebSocket connecté");

        _broadcastStream = _socket!.asBroadcastStream();

        if (!_autoNavigated && mounted) {
          _autoNavigated = true;
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted && showLanding) {
              print("🚀 Navigation automatique vers IdScannerScreen");
              _handleTap();
            }
          });
        }

        _broadcastStream!.listen(
              (msg) {
            final data = jsonDecode(msg);
            if (data is Map && data["action"] == "start_checkin") {
              _handleTap();
            }
          },
          onDone: () {
            setState(() {
              _isConnected = false;
              _broadcastStream = null;
            });
            print("🔌 [SPLASH] WebSocket déconnecté");
            _reconnect();
          },
          onError: (_) {
            setState(() {
              _isConnected = false;
              _broadcastStream = null;
            });
            _reconnect();
          },
        );
        break;
      } catch (e) {
        print("❌ [SPLASH] WebSocket impossible ($e). Pause 2s…");
        await Future.delayed(const Duration(seconds: 2));
        if (_receiverIP == "0.0.0.0") return;
      }
    }
  }

  void _reconnect() {
    if (mounted) _connectWebSocket();
  }

  Future<void> _promptManualConnect() async {
    final ipCtl = TextEditingController(text: _receiverIP == "0.0.0.0" ? "" : _receiverIP);
    final portCtl = TextEditingController(text: _receiverPort.toString());
    String? error;

    bool isValidIp(String s) {
      final parts = s.trim().split('.');
      if (parts.length != 4) return false;
      for (final p in parts) {
        final n = int.tryParse(p);
        if (n == null || n < 0 || n > 255) return false;
      }
      return true;
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Colors.white,
            title: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.settings_input_antenna, color: Color(0xFF1E3A8A), size: 24),
              ),
              const SizedBox(width: 12),
              const Text("Connexion à la borne", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ipCtl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Adresse IP",
                    hintText: "ex: 192.168.1.10",
                    prefixIcon: const Icon(Icons.router, color: Color(0xFF1E3A8A)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Color(0xFF1E3A8A), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: portCtl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Port",
                    hintText: "ex: 3000",
                    prefixIcon: const Icon(Icons.input, color: Color(0xFF1E3A8A)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Color(0xFF1E3A8A), width: 2),
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE63946).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE63946).withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Color(0xFFE63946), size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(error!, style: const TextStyle(color: Color(0xFFE63946), fontWeight: FontWeight.w500)))
                    ]),
                  )
                ]
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Annuler", style: TextStyle(color: Colors.grey.shade600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () {
                  final ip = ipCtl.text.trim();
                  final p = int.tryParse(portCtl.text.trim()) ?? 0;
                  if (!isValidIp(ip)) {
                    setSt(() => error = "Adresse IP invalide");
                    return;
                  }
                  if (p <= 0 || p > 65535) {
                    setSt(() => error = "Port invalide (1-65535)");
                    return;
                  }
                  setState(() {
                    _receiverIP = ip;
                    _receiverPort = p;
                  });
                  Navigator.pop(ctx);
                  _connectWebSocket();
                },
                child: const Text("Connecter", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

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
    _socket?.close();
    _mcastListenSocket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: showLanding ? _handleTap : null,
      child: Scaffold(
        body: showLanding
            ? _buildSplashScreen()
            : IdScannerScreen(
          broadcastStream: _broadcastStream,
          webSocket: _socket,
          isConnected: _isConnected,
          onReturnToSplash: _returnToSplash,
        ),
      ),
    );
  }

  Widget _buildSplashScreen() {
    return Stack(
      children: [
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
        Positioned(
          top: 28,
          right: 14,
          child: GestureDetector(
            onTap: _promptManualConnect,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _isConnected
                      ? const Color(0xFF10B981).withOpacity(0.6)
                      : const Color(0xFFE63946).withOpacity(0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _connectionPulseAnimation,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isConnected ? const Color(0xFF10B981) : const Color(0xFFE63946),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isConnected ? const Color(0xFF10B981) : const Color(0xFFE63946))
                                .withOpacity(0.55),
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 1),
                      Text(
                        _isConnected ? "Connecté" : "Hors ligne",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (_isConnected && _receiverIP != "0.0.0.0")
                        SizedBox(
                          width: 90,
                          child: Text(
                            _receiverIP,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 9,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.settings,
                    color: Colors.white.withOpacity(0.9),
                    size: 14,
                  ),
                ],
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
                    Icons.badge_outlined,
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
                        "Identity",
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
                        child: Text(
                          _isConnected ? "Connexion établie ✓" : "Connexion en cours...",
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white.withOpacity(0.95),
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1,
                          ),
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
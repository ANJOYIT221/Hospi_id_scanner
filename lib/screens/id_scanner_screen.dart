// =======================
// id_scanner_screen.dart
// (Gravure NFC -> envoi à la borne uniquement APRÈS succès)
// ✅ LANCEMENT AUTOMATIQUE DE L'APPAREIL PHOTO
// =======================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'document_camera_screen.dart'; // ← AJOUTEZ CETTE LIGNE
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import '../services/ocr_service.dart';

class IdScannerScreen extends StatefulWidget {
  final WebSocket? socket;
  final bool isConnected;
  final VoidCallback? onReturnToSplash;

  const IdScannerScreen({
    super.key,
    this.socket,
    this.isConnected = false,
    this.onReturnToSplash,
  });

  @override
  State<IdScannerScreen> createState() => _IdScannerScreenState();
}

class _IdScannerScreenState extends State<IdScannerScreen>
    with TickerProviderStateMixin {
  // ====== Services ======
  final OCRService _ocrService = OCRService();
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  final MethodChannel _nfcChannel = const MethodChannel('com.hospi_id_scan.nfc');

  // ====== Réseau ======
  WebSocket? _socket;
  bool _isConnected = false;
  bool _ownsSocket = false;

  // Découverte
  String _receiverIP = "0.0.0.0";
  int _receiverPort = 3000;
  static const int _discoveryPort = 3001;
  static const String _wantedMac = "DC:62:94:38:3C:C0";
  static final InternetAddress _mcastAddr = InternetAddress('239.255.255.250');
  RawDatagramSocket? _mcastListenSocket;

  // ====== OCR / UI ======
  File? _selectedImage;
  Map<String, String>? _extracted;
  bool _isProcessing = false;
  bool _isSpeaking = false;
  bool _isWritingNfc = false;

  // ✅ Réservation validée à envoyer APRÈS gravure NFC
  Map<String, String>? _pendingBooking;

  // ====== Animations ======
  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final AnimationController _nfcController;
  late final AnimationController _pulseController;

  // ====== Inactivité ======
  Timer? _inactivityTimer;

  // ====== Palette ======
  static const Color primaryBlue = Color(0xFF0A84FF);
  static const Color darkBlue = Color(0xFF0066CC);
  static const Color softBlue = Color(0xFF64B5F6);
  static const Color accentPurple = Color(0xFF7C3AED);
  static const Color successGreen = Color(0xFF34C759);
  static const Color warningAmber = Color(0xFFFFB800);
  static const Color errorRed = Color(0xFFFF3B30);
  static const Color bgLight = Color(0xFFF5F7FA);
  static const Color cardWhite = Colors.white;
  static const Color textDark = Color(0xFF1C1C1E);
  static const Color textMuted = Color(0xFF8E8E93);

  bool get _connected =>
      (_socket?.readyState == WebSocket.open) || _isConnected || widget.isConnected;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initTts();
    _resetInactivityTimer();

    if (widget.socket != null) {
      _socket = widget.socket;
      _isConnected = widget.isConnected || (_socket?.readyState == WebSocket.open);
      _ownsSocket = false;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // ✅ Lancement IMMÉDIAT de l'appareil photo
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          _pickImage(ImageSource.camera);
        }
        // Message vocal en parallèle
        _speak("Placez votre carte d'identité sur l'espace prévu.");
      });
    } else {
      _ownsSocket = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // ✅ Lancement IMMÉDIAT de l'appareil photo
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          _pickImage(ImageSource.camera);
        }
        // Message vocal et connexion en parallèle
        _speak("Placez votre carte d'identité sur l'espace prévu.");
        await _startMulticastListener();
        await _runDiscoveryAndConnect();
        if (!_isConnected && _receiverIP != "0.0.0.0") {
          await _connectWebSocket();
        }
      });
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _tts.stop();
    _player.dispose();
    if (_ownsSocket) _socket?.close();
    _mcastListenSocket?.close();
    _fadeController.dispose();
    _slideController.dispose();
    _nfcController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ====== Inactivité ======
  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 5), () {
      widget.onReturnToSplash?.call();
    });
  }
  void _onUserActivity() => _resetInactivityTimer();

  // ====== TTS ======
  Future<void> _initTts() async {
    await _tts.setLanguage("fr-FR");
    await _tts.setSpeechRate(0.9);
    await _tts.setVolume(0.9);
    await _tts.setPitch(1.0);
    _tts.setStartHandler(() => setState(() => _isSpeaking = true));
    _tts.setCompletionHandler(() => setState(() => _isSpeaking = false));
    _tts.setErrorHandler((_) => setState(() => _isSpeaking = false));
  }

  Future<void> _speak(String text) async {
    if (_isSpeaking) await _tts.stop();
    try {
      await _tts.speak(text);
    } catch (_) {
      setState(() => _isSpeaking = false);
    }
  }

  // ====== Animations ======
  void _setupAnimations() {
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _nfcController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  // ==================== RÉSEAU ====================
  Future<String?> _getLocalIPv4() async {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    for (final iface in ifaces) {
      for (final a in iface.addresses) {
        if (a.type == InternetAddressType.IPv4 && !a.address.startsWith('127.')) return a.address;
      }
    }
    return null;
  }

  InternetAddress _guessBroadcast(String localIp) {
    final parts = localIp.split('.');
    if (parts.length == 4) return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
    return InternetAddress('255.255.255.255');
  }

  Future<void> _startMulticastListener() async {
    try {
      _mcastListenSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _discoveryPort);
      _mcastListenSocket!.joinMulticast(_mcastAddr);
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

              if (mac != null && (_wantedMac.isEmpty || mac == _wantedMac)) {
                final changed = (_receiverIP != ip || _receiverPort != port);
                if (changed) {
                  setState(() { _receiverIP = ip; _receiverPort = port; });
                  if (!_isConnected && _ownsSocket) _connectWebSocket();
                }
              }
            }
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint("❌ Multicast listener KO: $e");
    }
  }

  Future<Map<String, Map<String, dynamic>>> _discoverReceivers({int timeoutSeconds = 3, int repeats = 3}) async {
    final results = <String, Map<String, dynamic>>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final localIp = await _getLocalIPv4();
      final bcastNet = localIp != null ? _guessBroadcast(localIp) : InternetAddress('255.255.255.255');
      final bcastAll = InternetAddress('255.255.255.255');
      final reqBytes = utf8.encode(jsonEncode({'action': 'DISCOVER_LOUNA', 'time': DateTime.now().toIso8601String()}));

      for (int i = 0; i < repeats; i++) {
        socket.send(reqBytes, bcastNet, _discoveryPort);
        socket.send(reqBytes, bcastAll, _discoveryPort);
        await Future.delayed(const Duration(milliseconds: 120));
      }

      final completer = Completer<void>();
      final timer = Timer(Duration(seconds: timeoutSeconds), () { if (!completer.isCompleted) completer.complete(); });

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
            if (mac != null && mac.isNotEmpty) results[mac] = {'ip': ip, 'port': port, 'raw': parsed};
          } catch (_) {}
        }
      });

      await completer.future; timer.cancel();
    } catch (e) {
      debugPrint("❌ discoverReceivers error: $e");
    } finally {
      socket?.close();
    }
    return results;
  }

  Future<void> _runDiscoveryAndConnect() async {
    final discovered = await _discoverReceivers(timeoutSeconds: 3, repeats: 3);
    if (discovered.isEmpty) return;
    String selectedIp = discovered.values.first['ip'];
    int selectedPort = discovered.values.first['port'];
    if (_wantedMac.isNotEmpty && discovered.containsKey(_wantedMac)) {
      selectedIp = discovered[_wantedMac]!['ip']; selectedPort = discovered[_wantedMac]!['port'];
    }
    setState(() { _receiverIP = selectedIp; _receiverPort = selectedPort; });
    if (_ownsSocket) await _connectWebSocket();
  }

  Future<void> _connectWebSocket() async {
    if (!_ownsSocket) return;
    if (_receiverIP == "0.0.0.0" || _receiverIP.trim().isEmpty) return;
    for (;;) {
      try {
        final uri = 'ws://$_receiverIP:$_receiverPort';
        _socket = await WebSocket.connect(uri);
        _isConnected = true;
        if (!mounted) return; setState(() {});
        _socket!.listen((msg) {
          _onUserActivity();
          final data = jsonDecode(msg);
          if (data is Map && data["action"] == "start_nfc") {
            _writeToNfc();
          }
        }, onDone: () {
          _isConnected = false; if (!mounted) return; setState(() {}); _reconnect();
        }, onError: (_) {
          _isConnected = false; if (!mounted) return; setState(() {}); _reconnect();
        });
        break;
      } catch (_) {
        await Future.delayed(const Duration(seconds: 2));
        if (_receiverIP == "0.0.0.0") return;
      }
    }
  }

  void _reconnect() { if (_ownsSocket && mounted) _connectWebSocket(); }

  void _sendToReceiver(Map<String, dynamic> data) {
    if (_socket == null || _socket!.readyState != WebSocket.open) return;
    _socket!.add(jsonEncode(data));
  }

  // ==================== NFC ====================
  Future<void> _writeToNfc() async {
    _onUserActivity();
    if (_extracted == null) return;
    setState(() => _isWritingNfc = true);
    _nfcController.forward();
    await _speak("Approchez la carte fournie de la zone orange.");
    final jsonText = jsonEncode(_extracted);
    try {
      await _nfcChannel.invokeMethod('writeTag', {'text': jsonText});
      if (!mounted) return;
      setState(() => _isWritingNfc = false);
      _nfcController.reverse();
      _showSnackBar("✅ Carte de chambre obtenue !", successGreen);
      await _speak("Parfait !.");

      // ✅ ENVOI À LA BORNE APRÈS SUCCÈS DE LA GRAVURE
      // (on peut optionnellement prévenir la borne que le check-in démarre)
      _sendToReceiver({"action": "start_checkin"});

      if (_pendingBooking != null) {
        _sendToReceiver({
          "action": "booking_retrieved",
          "booking": Map<String, dynamic>.from(_pendingBooking!),
        });
      } else {
        // Filet de sécurité minimal si jamais la réservation n'a pas été trouvée/stockée
        _sendToReceiver({
          "action": "booking_retrieved",
          "booking": {
            "name": _extracted!['name'] ?? '',
            "surname": _extracted!['surname'] ?? '',
          },
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _isWritingNfc = false);
      _nfcController.reverse();
      _showSnackBar("❌ Erreur NFC : ${e.message}", errorRed);
      await _speak("Erreur, veuillez réessayer.");
    }
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

  // ==================== OCR ====================
// ==================== OCR ====================
  Future<void> _pickImage(ImageSource src) async {
    _onUserActivity();

    if (src == ImageSource.camera) {
      // ✅ Ouvrir l'écran de caméra intelligent avec détection automatique
      final File? photo = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DocumentCameraScreen()),
      );

      if (photo == null) return; // Utilisateur a annulé

      setState(() {
        _selectedImage = photo;
        _extracted = null;
        _isProcessing = true;
      });

      _fadeController.forward();
      _slideController.forward();

      try {
        final raw = await _ocrService.scanTextFromImage(_selectedImage!);

        final hasValidData = raw['nom'] != 'INCONNU' &&
            raw['nom'] != 'ERREUR' &&
            (raw['prenoms'] != 'INCONNU' || raw['idNumber'] != 'INCONNU');

        if (!hasValidData) {
          if (!mounted) return;
          setState(() => _isProcessing = false);
          _showSnackBar("❌ Aucune donnée extraite. Réessayez avec une meilleure photo.", errorRed);
          await _speak("Je n'ai pas pu lire le document. Réessayez avec une photo plus nette.");
          return;
        }

        final normalized = <String, String>{
          'name': (raw['nom'] ?? raw['nomUsage'] ?? '').toString(),
          'surname': (raw['prenoms'] ?? raw['givenNames'] ?? '').toString(),
          'idNumber': (raw['idNumber'] ?? '').toString(),
          'nationality': (raw['nationalite'] ?? raw['nationality'] ?? '').toString(),
          ...raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
        };

        if (!mounted) return;
        setState(() {
          _extracted = Map<String, String>.from(normalized);
          _isProcessing = false;
        });

        _sendToReceiver(Map<String, dynamic>.from(normalized));
        await _verifyBookingAndNotifyPeer(_extracted!);
        await _speak("Scan terminé.");

      } catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        _showSnackBar("❌ Erreur de traitement : $e", errorRed);
        await _speak("Erreur de traitement, veuillez réessayer.");
      }

    } else {
      // ==================== GALERIE ====================
      final picker = ImagePicker();
      final img = await picker.pickImage(
          source: src,
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1080
      );

      if (img == null) return;

      setState(() {
        _selectedImage = File(img.path);
        _extracted = null;
        _isProcessing = true;
      });

      _fadeController.forward();
      _slideController.forward();

      try {
        final raw = await _ocrService.scanTextFromImage(_selectedImage!);

        final hasValidData = raw['nom'] != 'INCONNU' &&
            raw['nom'] != 'ERREUR' &&
            (raw['prenoms'] != 'INCONNU' || raw['idNumber'] != 'INCONNU');

        if (!hasValidData) {
          if (!mounted) return;
          setState(() => _isProcessing = false);
          _showSnackBar("❌ Aucune donnée extraite. Réessayez avec une meilleure photo.", errorRed);
          await _speak("Je n'ai pas pu lire le document. Réessayez avec une photo plus nette.");
          return;
        }

        final normalized = <String, String>{
          'name': (raw['nom'] ?? raw['nomUsage'] ?? '').toString(),
          'surname': (raw['prenoms'] ?? raw['givenNames'] ?? '').toString(),
          'idNumber': (raw['idNumber'] ?? '').toString(),
          'nationality': (raw['nationalite'] ?? raw['nationality'] ?? '').toString(),
          ...raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
        };

        if (!mounted) return;
        setState(() {
          _extracted = Map<String, String>.from(normalized);
          _isProcessing = false;
        });

        _sendToReceiver(Map<String, dynamic>.from(normalized));
        await _verifyBookingAndNotifyPeer(_extracted!);
        await _speak("Scan terminé.");

      } catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        _showSnackBar("❌ Erreur de traitement : $e", errorRed);
        await _speak("Erreur de traitement, veuillez réessayer.");
      }
    }
  }
  // ==================== HELPERS UI ====================
  InputDecoration _modernInput(String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label, hintText: hint,
      prefixIcon: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, color: primaryBlue, size: 18)),
      labelStyle: const TextStyle(fontSize: 12), hintStyle: const TextStyle(fontSize: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: primaryBlue, width: 1.8)),
      filled: true, fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  Map<String, String> _formatForDisplay(Map<String, String> raw) {
    return {
      'Nom': raw['nom'] ?? raw['nomUsage'] ?? raw['name'] ?? 'INCONNU',
      'Prénoms': raw['prenoms'] ?? raw['givenNames'] ?? raw['surname'] ?? 'INCONNU',
      'N° Document': raw['idNumber'] ?? 'INCONNU',
      'Nationalité': raw['nationalite'] ?? raw['nationality'] ?? 'Inconnue',
    };
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onUserActivity, onPanDown: (_) => _onUserActivity(),
      child: Scaffold(
        backgroundColor: bgLight,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    _buildWelcomeSection(),
                    const SizedBox(height: 12),
                    _buildActionButtons(),
                    if (_selectedImage != null) ...[
                      const SizedBox(height: 12),
                      _buildImagePreview(),
                    ],
                    if (_isProcessing) ...[
                      const SizedBox(height: 12),
                      _buildProcessingCard(),
                    ],
                    if (_extracted != null && !_isProcessing) ...[
                      const SizedBox(height: 12),
                      _buildExtractedCard(),
                    ],
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: _extracted != null && !_isProcessing
            ? _buildFloatingButton()
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: bgLight, foregroundColor: textDark, elevation: 0,
      titleSpacing: 0, toolbarHeight: 52, leadingWidth: 48,
      leading: widget.onReturnToSplash == null ? null : IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18), tooltip: "Retour",
        onPressed: () => widget.onReturnToSplash?.call(),
      ),
      title: const Text("HOSPI SMART", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4, fontSize: 16)),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _connected ? successGreen.withOpacity(0.15) : errorRed.withOpacity(0.15),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _connected ? successGreen.withOpacity(0.35) : errorRed.withOpacity(0.35), width: 1.2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: _connected ? successGreen : errorRed, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(_connected ? "Connecté" : "Hors ligne", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _connected ? successGreen : errorRed)),
          ]),
        ),
      ],
    );
  }

  Widget _buildWelcomeSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primaryBlue, accentPurple], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.22), blurRadius: 14, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cardWhite.withOpacity(0.25), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.document_scanner_outlined, color: cardWhite, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "L'appareil photo va se lancer automatiquement pour scanner votre pièce d'identité.",
              style: TextStyle(color: cardWhite, fontSize: 13, fontWeight: FontWeight.w700, height: 1.2),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _speak("L'appareil photo va se lancer automatiquement pour scanner votre pièce d'identité."),
            icon: const Icon(Icons.volume_up_rounded, size: 18, color: cardWhite),
            label: const Text("Écouter", style: TextStyle(color: cardWhite, fontWeight: FontWeight.w700, fontSize: 12)),
            style: TextButton.styleFrom(
              backgroundColor: cardWhite.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        if (isNarrow) {
          return Column(children: [
            _buildGalleryButton(height: 110),
            const SizedBox(height: 10),
            _buildScanButton(height: 110),
          ]);
        }
        return Row(children: [
          Expanded(child: _buildGalleryButton(height: 120)),
          const SizedBox(width: 10),
          Expanded(child: _buildScanButton(height: 120)),
        ]);
      },
    );
  }

  Widget _buildGalleryButton({double height = 120}) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _pickImage(ImageSource.gallery),
            borderRadius: BorderRadius.circular(18),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_outlined, size: 26, color: softBlue),
                  SizedBox(height: 8),
                  Text("Galerie", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textDark)),
                  SizedBox(height: 2),
                  Text("Choisir", style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanButton({double height = 120}) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [primaryBlue, darkBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _pickImage(ImageSource.camera),
            borderRadius: BorderRadius.circular(18),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.document_scanner_outlined, size: 26, color: cardWhite),
                  SizedBox(height: 8),
                  Text("Scan", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: cardWhite)),
                  SizedBox(height: 2),
                  Text("Photo", style: TextStyle(fontSize: 11, color: cardWhite, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return FadeTransition(
      opacity: _fadeController,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
            .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Image.file(_selectedImage!, height: 210, width: double.infinity, fit: BoxFit.cover),
              Positioned(
                top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: successGreen, borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: successGreen.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))],
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_rounded, color: cardWhite, size: 16),
                    SizedBox(width: 6),
                    Text("Photo chargée", style: TextStyle(color: cardWhite, fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingCard() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cardWhite, borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 8))]),
      child: Column(children: const [
        SizedBox(width: 64, height: 64, child: CircularProgressIndicator(strokeWidth: 5, valueColor: AlwaysStoppedAnimation<Color>(primaryBlue))),
        SizedBox(height: 10),
        Text("Analyse en cours...", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textDark)),
        SizedBox(height: 4),
        Text("Extraction des données…", style: TextStyle(fontSize: 12, color: textMuted, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildExtractedCard() {
    if (_extracted == null) return const SizedBox.shrink();
    final display = _formatForDisplay(_extracted!);
    final hasErrors = display.values.any((v) => v.contains('INCONNU') || v.contains('ERREUR') || v.contains('Inconnue'));

    return Container(
      width: double.infinity, padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardWhite, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hasErrors ? warningAmber.withOpacity(0.25) : bgLight, width: 1.5),
        boxShadow: [BoxShadow(color: successGreen.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          ...display.entries.map((e) => _buildDataField(e.key, e.value)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _editExtractedData,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text("Modifier", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              style: TextButton.styleFrom(
                foregroundColor: primaryBlue, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                backgroundColor: primaryBlue.withOpacity(0.1), minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataField(String label, String value) {
    final isError = value.contains('INCONNU') || value.contains('ERREUR') || value.contains('Inconnue');
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? warningAmber.withOpacity(0.08) : bgLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isError ? warningAmber.withOpacity(0.25) : bgLight, width: 1.2),
      ),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: textMuted))),
        Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: isError ? warningAmber : textDark), maxLines: 2, overflow: TextOverflow.ellipsis)),
        if (!isError) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.check_circle_rounded, color: successGreen, size: 16)),
      ]),
    );
  }

  Widget _buildFloatingButton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16), width: double.infinity, height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [accentPurple, primaryBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: accentPurple.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isWritingNfc ? null : _writeToNfc,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _isWritingNfc
                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: cardWhite, strokeWidth: 3)),
              SizedBox(width: 12),
              Text("Gravure…", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cardWhite)),
            ])
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              Icon(Icons.nfc_rounded, size: 20, color: cardWhite),
              SizedBox(width: 10),
              Text("Obtenir la carte", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: cardWhite)),
            ]),
          ),
        ),
      ),
    );
  }

  // ==================== ÉDITION MANUELLE ====================
  Future<void> _editExtractedData() async {
    _onUserActivity();
    if (_extracted == null) return;

    String _cleanName(String s) {
      final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
      return t.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
    }

    final nomCtl = TextEditingController(text: _extracted!['nom'] ?? _extracted!['nomUsage'] ?? _extracted!['name'] ?? '');
    final prenomsCtl = TextEditingController(text: _extracted!['prenoms'] ?? _extracted!['givenNames'] ?? _extracted!['surname'] ?? '');
    final idNumberCtl = TextEditingController(text: _extracted!['idNumber'] ?? '');
    final natCtl = TextEditingController(text: _extracted!['nationalite'] ?? _extracted!['nationality'] ?? '');

    await showDialog(
      context: context,
      builder: (ctx) {
        String? errorMsg;
        return StatefulBuilder(builder: (ctx, setSt) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            actionsPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            title: Row(children: const [
              Icon(Icons.edit_outlined, color: primaryBlue, size: 18),
              SizedBox(width: 8),
              Text("Corriger les informations", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ]),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nomCtl, textCapitalization: TextCapitalization.words, decoration: _modernInput("Nom", "ex: DUPONT", Icons.person_outline)),
                const SizedBox(height: 10),
                TextField(controller: prenomsCtl, textCapitalization: TextCapitalization.words, decoration: _modernInput("Prénoms", "ex: Jean Pierre", Icons.badge_outlined)),
                const SizedBox(height: 10),
                TextField(controller: idNumberCtl, textCapitalization: TextCapitalization.characters, decoration: _modernInput("N° Document", "ex: X123456", Icons.confirmation_number_outlined)),
                const SizedBox(height: 10),
                TextField(controller: natCtl, textCapitalization: TextCapitalization.words, decoration: _modernInput("Nationalité", "ex: Française", Icons.public_outlined)),
                if (errorMsg != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: errorRed.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: errorRed.withOpacity(0.3))),
                    child: Text(errorMsg!, style: const TextStyle(color: errorRed, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text("Valider", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue, foregroundColor: cardWhite,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final newNom = _cleanName(nomCtl.text);
                  final newPrenoms = _cleanName(prenomsCtl.text);
                  final newId = idNumberCtl.text.trim();
                  final newNat = _cleanName(natCtl.text);

                  if (newNom.isEmpty || (newPrenoms.isEmpty && newId.isEmpty)) {
                    setSt(() => errorMsg = "Nom obligatoire, et au moins Prénoms ou N° Document.");
                    return;
                  }

                  setState(() {
                    _extracted!['nom'] = newNom; _extracted!['nomUsage'] = newNom; _extracted!['name'] = newNom;
                    _extracted!['prenoms'] = newPrenoms; _extracted!['givenNames'] = newPrenoms; _extracted!['surname'] = newPrenoms;
                    _extracted!['idNumber'] = newId;
                    _extracted!['nationalite'] = newNat; _extracted!['nationality'] = newNat;
                  });

                  _sendToReceiver(Map<String, dynamic>.from(_extracted!)); // état live
                  Navigator.pop(ctx);
                  _showSnackBar("✅ Informations mises à jour", successGreen);
                  _speak("Informations mises à jour.");
                  await _verifyBookingAndNotifyPeer(_extracted!); // stocke _pendingBooking
                },
              ),
            ],
          );
        });
      },
    );
  }

  // ================== PMS (Google Sheet) =================
  static const String _sheetUrl = "https://docs.google.com/spreadsheets/d/11ZQMo5T7R5KnZC1tZ77ytAGknS_l1WrNUHxOof56_gE/export?format=csv&gid=0";

  Future<List<Map<String, String>>> _fetchReservations() async {
    try {
      final response = await http.get(Uri.parse(_sheetUrl));
      if (response.statusCode != 200) throw Exception("Erreur réseau (${response.statusCode})");
      final lines = response.body.split('\n');
      if (lines.isEmpty) return [];
      final headers = lines.first.split(',').map((e) => e.trim()).toList();
      final data = lines.skip(1).where((line) => line.trim().isNotEmpty).map((line) {
        final values = line.split(',').map((e) => e.trim()).toList();
        while (values.length < headers.length) { values.add(''); }
        return Map<String, String>.fromIterables(headers, values);
      }).toList();
      return data;
    } catch (e) {
      debugPrint("❌ Erreur fetch reservations: $e");
      return [];
    }
  }

  String _normalize(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-zàâäéèêëîïôöùûüç\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<Map<String, String>?> _findBooking(String name, String surname) async {
    final reservations = await _fetchReservations();
    final normalizedName = _normalize(name);
    final normalizedSurname = _normalize(surname);

    for (final r in reservations) {
      final storedName = _normalize(r["name"] ?? "");
      final storedSurname = _normalize(r["surname"] ?? "");
      if (storedName == normalizedName && storedSurname == normalizedSurname) return r;
    }
    return null;
  }

  // ✅ Vérifie + stocke seulement (_pendingBooking). AUCUN envoi ici.
  Future<void> _verifyBookingAndNotifyPeer(Map<String, String> extracted) async {
    final name = (extracted['name'] ?? '').trim();
    final surname = (extracted['surname'] ?? '').trim();

    if (name.isEmpty || surname.isEmpty) {
      _showSnackBar("ℹ️ Nom/Prénoms insuffisants pour vérifier la réservation.", warningAmber);
      return;
    }

    _showSnackBar("🔍 Vérification de la réservation…", primaryBlue);
    try {
      final booking = await _findBooking(name, surname);
      if (booking == null || booking.isEmpty) {
        _showSnackBar("❌ Aucune réservation trouvée pour $surname $name.", errorRed);
        await _speak("Aucune réservation trouvée pour $surname $name.");
        _pendingBooking = null;
        return;
      }

      _pendingBooking = booking;
      _showSnackBar("✅ Réservation confirmée. Veuillez graver la carte.", successGreen);
      await _speak("Réservation confirmée. Veuillez graver la carte pour finaliser l'accès.");

      // ✅ Attendre 1 seconde puis lancer automatiquement la gravure
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        _writeToNfc(); // ← Lance automatiquement la gravure
      }
    } catch (e) {
      _showSnackBar("❌ Erreur durant la vérification: $e", errorRed);
    }
  }
}
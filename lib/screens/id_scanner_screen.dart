// =======================
// id_scanner_screen.dart - SCANNER PROPRE
// OCR → Envoie données → Attend réservation → Grave NFC
// =======================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'document_camera_screen.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ocr_service.dart';

class IdScannerScreen extends StatefulWidget {
  final Stream<dynamic>? broadcastStream; // ← Stream partagé pour RECEVOIR
  final WebSocket? webSocket; // ← WebSocket pour ENVOYER
  final bool isConnected;
  final VoidCallback? onReturnToSplash;

  const IdScannerScreen({
    super.key,
    this.broadcastStream,
    this.webSocket,
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
  // ✅ Pas de WebSocket ici - on utilise le broadcast stream partagé
  StreamSubscription<dynamic>? _streamSubscription;
  bool get _isConnected => widget.isConnected;

  // ====== OCR / UI ======
  File? _selectedImage;
  Map<String, String>? _extracted;
  bool _isProcessing = false;
  bool _isSpeaking = false;
  bool _isWritingNfc = false;

  // ✅ Réservation reçue de la borne (à graver)
  Map<String, String>? _bookingToWrite;

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

  bool get _connected => _isConnected;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initTts();
    _resetInactivityTimer();

    // ✅ S'abonner au broadcast stream partagé
    if (widget.broadcastStream != null) {
      _streamSubscription = widget.broadcastStream!.listen(_handleBorneMessage);
    }

    // Lancement automatique de la caméra
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) _pickImage(ImageSource.camera);
      _speak("Placez votre carte d'identité sur l'espace prévu.");
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _tts.stop();
    _player.dispose();
    _streamSubscription?.cancel(); // ✅ Annuler la subscription (pas fermer le socket)
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

  void _sendToReceiver(Map<String, dynamic> data) {
    if (widget.webSocket == null || widget.webSocket!.readyState != WebSocket.open) {
      print('❌ WebSocket non connecté');
      return;
    }
    print('📤 SCANNER → BORNE : ${data['action']}');
    widget.webSocket!.add(jsonEncode(data));
  }

  // ============================================
  // 🆕 GESTION DES MESSAGES DE LA BORNE
  // ============================================

  void _handleBorneMessage(dynamic message) {
    _onUserActivity();
    try {
      print('📨 SCANNER ← BORNE : Message reçu');

      final data = jsonDecode(message);
      if (data is! Map) return;

      final action = data['action'];
      print('📨 Action: $action');

      // ===== RÉSERVATION VALIDÉE (la borne a trouvé) =====
      if (action == 'booking_retrieved') {
        final rawBooking = data['booking'];
        if (rawBooking is! Map) {
          print('⚠️ Booking invalide');
          return;
        }

        _bookingToWrite = Map<String, String>.from(rawBooking as Map);

        if (_bookingToWrite == null || _bookingToWrite!.isEmpty) {
          print('⚠️ Booking vide');
          return;
        }

        print('✅ Réservation reçue: ${_bookingToWrite!['surname']} ${_bookingToWrite!['name']}');
        _showSnackBar("✅ Réservation confirmée !", successGreen);

        // ✅ LANCER LA GRAVURE IMMÉDIATEMENT
        _writeToNfc();
        return;
      }

    } catch (e) {
      print('❌ Erreur handleBorneMessage: $e');
    }
  }

  // ==================== OCR ====================

  Future<void> _pickImage(ImageSource src) async {
    _onUserActivity();

    if (src == ImageSource.camera) {
      final File? photo = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DocumentCameraScreen()),
      );

      if (photo == null) return;

      setState(() {
        _selectedImage = photo;
        _extracted = null;
        _isProcessing = true;
      });

      _fadeController.forward();
      _slideController.forward();

      try {
        print('📸 Scan OCR...');
        final raw = await _ocrService.scanTextFromImage(_selectedImage!);

        final hasValidData = raw['nom'] != 'INCONNU' &&
            raw['nom'] != 'ERREUR' &&
            (raw['prenoms'] != 'INCONNU' || raw['idNumber'] != 'INCONNU');

        if (!hasValidData) {
          if (!mounted) return;
          setState(() => _isProcessing = false);
          _showSnackBar("❌ Aucune donnée extraite. Réessayez.", errorRed);
          await _speak("Je n'ai pas pu lire le document.");
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

        print('✅ OCR terminé: ${_extracted!['surname']} ${_extracted!['name']}');

        // ✅ ENVOYER LES DONNÉES À LA BORNE (pour vérification PMS)
        _sendToReceiver(Map<String, dynamic>.from(normalized));
        await _speak("Données envoyées, vérification en cours.");

      } catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        _showSnackBar("❌ Erreur : $e", errorRed);
        await _speak("Erreur de traitement.");
      }

    } else {
      // Galerie
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
          _showSnackBar("❌ Aucune donnée extraite.", errorRed);
          await _speak("Je n'ai pas pu lire le document.");
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
        await _speak("Données envoyées.");

      } catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        _showSnackBar("❌ Erreur : $e", errorRed);
      }
    }
  }

  // ==================== NFC ====================

  Future<void> _writeToNfc() async {
    _onUserActivity();

    if (_bookingToWrite == null) {
      print('⚠️ Aucune réservation à graver');
      _showSnackBar("⚠️ Aucune réservation validée", warningAmber);
      return;
    }

    print('🔥 ========== GRAVURE NFC ==========');
    print('📝 Réservation: ${_bookingToWrite!['surname']} ${_bookingToWrite!['name']}');

    setState(() => _isWritingNfc = true);
    _nfcController.forward();

    await _speak("Approchez la carte fournie de la zone orange.");

    final jsonText = jsonEncode(_bookingToWrite);

    try {
      await _nfcChannel.invokeMethod('writeTag', {'text': jsonText});

      if (!mounted) return;
      setState(() => _isWritingNfc = false);
      _nfcController.reverse();

      print('✅ Gravure NFC réussie !');
      _showSnackBar("✅ Carte de chambre obtenue !", successGreen);
      await _speak("Parfait ! Votre carte de chambre est prête.");

      // ✅ ENVOYER À LA BORNE QUE LA GRAVURE EST TERMINÉE
      _sendToReceiver({
        "action": "nfc_write_success",
        "booking": Map<String, dynamic>.from(_bookingToWrite!),
      });

      print('📤 Envoi confirmation gravure à la borne');

      // ✅ RETOUR AU SPLASH APRÈS 3 SECONDES
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        widget.onReturnToSplash?.call();
      }

    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _isWritingNfc = false);
      _nfcController.reverse();

      print('❌ Erreur NFC: ${e.message}');
      _showSnackBar("❌ Erreur NFC : ${e.message}", errorRed);
      await _speak("Erreur, veuillez réessayer.");

    } catch (e) {
      if (!mounted) return;
      setState(() => _isWritingNfc = false);
      _nfcController.reverse();

      print('❌ Erreur inattendue: $e');
      _showSnackBar("❌ Erreur : $e", errorRed);
    }

    print('🔥 ========== FIN GRAVURE ==========');
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
      title: const Text("SCANNER HOSPI", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4, fontSize: 16)),
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
              "Scannez la pièce d'identité du client",
              style: TextStyle(color: cardWhite, fontSize: 13, fontWeight: FontWeight.w700, height: 1.2),
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
        Text("Traitement en cours...", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textDark)),
        SizedBox(height: 4),
        Text("Analyse du document…", style: TextStyle(fontSize: 12, color: textMuted, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildExtractedCard() {
    if (_extracted == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity, padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardWhite, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: successGreen.withOpacity(0.3), width: 2),
        boxShadow: [BoxShadow(color: successGreen.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.check_circle, color: successGreen, size: 24),
            SizedBox(width: 10),
            Text("Données extraites", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textDark)),
          ]),
          const SizedBox(height: 12),
          _buildDataRow("Nom", _extracted!['name'] ?? 'N/A'),
          _buildDataRow("Prénom", _extracted!['surname'] ?? 'N/A'),
          _buildDataRow("N° Document", _extracted!['idNumber'] ?? 'N/A'),
          _buildDataRow("Nationalité", _extracted!['nationality'] ?? 'N/A'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: const [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Vérification de la réservation en cours...",
                    style: TextStyle(
                      color: primaryBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 100, child: Text("$label :", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textMuted))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textDark))),
      ]),
    );
  }
}
// =======================
// checkout_screen.dart
// Effacement NFC automatique dès ouverture (Check-out)
// =======================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class CheckoutScreen extends StatefulWidget {
  final WebSocket? socket;
  final bool isConnected;
  final VoidCallback? onReturnToSplash;

  const CheckoutScreen({
    super.key,
    this.socket,
    this.isConnected = false,
    this.onReturnToSplash,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen>
    with TickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  final MethodChannel _nfcChannel = const MethodChannel('com.hospi_id_scan.nfc');

  bool _isProcessing = false;
  bool _isSpeaking = false;
  bool _checkoutSuccess = false;
  WebSocket? _socket;
  bool _isConnected = false;
  Timer? _inactivityTimer;

  late final AnimationController _fadeController;
  late final AnimationController _pulseController;
  late final AnimationController _successController;

  static const Color primaryBlue = Color(0xFF0A84FF);
  static const Color successGreen = Color(0xFF34C759);
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

    _socket = widget.socket;
    _isConnected = widget.isConnected || (_socket?.readyState == WebSocket.open);

    // Lecture automatique dès ouverture
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _speak("Bienvenue au check-out. Approchez votre carte de chambre maintenant.");
      await Future.delayed(const Duration(seconds: 1));
      _performCheckout(); // 🚀 lancement auto
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _tts.stop();
    _player.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    _successController.dispose();
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 5), () {
      widget.onReturnToSplash?.call();
    });
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("fr-FR");
    await _tts.setSpeechRate(0.9);
    await _tts.setVolume(0.9);
    await _tts.setPitch(1.0);
    _tts.setStartHandler(() => setState(() => _isSpeaking = true));
    _tts.setCompletionHandler(() => setState(() => _isSpeaking = false));
  }

  Future<void> _speak(String text) async {
    if (_isSpeaking) await _tts.stop();
    try {
      await _tts.speak(text);
    } catch (_) {
      setState(() => _isSpeaking = false);
    }
  }

  void _setupAnimations() {
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _successController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  }

  // ======================================================
  // 🚀 Check-out automatique : dès qu’on ouvre la page
  // ======================================================
  Future<void> _performCheckout() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _checkoutSuccess = false;
    });

    _fadeController.forward();

    try {
      await _nfcChannel.invokeMethod('eraseTag'); // 🔥 efface dès scan

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _checkoutSuccess = true;
      });

      _successController.forward();
      _showSnackBar("✅ Check-out effectué avec succès !", successGreen);
      await _speak("Check-out effectué avec succès. Merci de votre séjour !");
      _sendToReceiver({"action": "checkout_complete"});

      await Future.delayed(const Duration(seconds: 3));
      widget.onReturnToSplash?.call();
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _fadeController.reverse();

      if (e.code == 'TAG_NOT_FOUND') {
        _showSnackBar("⚠️ Aucune carte détectée. Réessayez.", errorRed);
        await _speak("Aucune carte détectée. Veuillez réessayer.");
        // 🔁 relancer écoute automatiquement
        await Future.delayed(const Duration(seconds: 2));
        _performCheckout();
      } else {
        _showSnackBar("❌ Erreur NFC : ${e.message}", errorRed);
        await _speak("Erreur technique. Veuillez réessayer.");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _fadeController.reverse();
      _showSnackBar("❌ Erreur inattendue : $e", errorRed);
      await _speak("Erreur inattendue. Veuillez réessayer.");
    }
  }

  void _showSnackBar(String msg, Color color) {
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

  void _sendToReceiver(Map<String, dynamic> data) {
    if (_socket == null || _socket!.readyState != WebSocket.open) return;
    _socket!.add(jsonEncode(data));
  }

  // ======================================================
  // UI
  // ======================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        backgroundColor: bgLight,
        elevation: 0,
        title: const Text(
          "CHECK-OUT",
          style: TextStyle(fontWeight: FontWeight.bold, color: textDark),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.15).animate(
                CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
              ),
              child: Icon(
                _isProcessing ? Icons.nfc_rounded : Icons.logout_rounded,
                size: 100,
                color: _isProcessing ? primaryBlue : Colors.orange,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isProcessing ? "Approchez votre carte..." : "En attente du tag",
              style: TextStyle(
                color: _isProcessing ? primaryBlue : textDark,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (_checkoutSuccess)
              const Icon(Icons.check_circle_rounded, color: successGreen, size: 60),
          ],
        ),
      ),
    );
  }
}

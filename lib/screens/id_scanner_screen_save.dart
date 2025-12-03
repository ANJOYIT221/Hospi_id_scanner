import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

import '../services/ocr_service.dart';
import '../global_config.dart'; // contient openAIApiKey

class IdScannerScreen extends StatefulWidget {
  @override
  _IdScannerScreenState createState() => _IdScannerScreenState();
}

class _IdScannerScreenState extends State<IdScannerScreen> with TickerProviderStateMixin {
  final OCRService _ocrService = OCRService();
  final AudioPlayer player = AudioPlayer();
  File? _selectedImage;
  Map<String, String>? extractedData;
  bool isSpeaking = false;
  bool isProcessing = false;
  WebSocket? _socket;
  late AnimationController _pulseController;
  late AnimationController _fadeController;

  final String serverIp = "192.168.144.8"; // IP du récepteur
  final int serverPort = 3000;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _speakText("Bonjour, je suis LOUNA ! et Je suis là pour vous aider à valider votre identité ! Appuyez sur le bouton caméra");
      await _connectToReceiver();
    });
  }

  Future<void> _connectToReceiver() async {
    try {
      _socket = await WebSocket.connect('ws://$serverIp:$serverPort');
      print("✅ Connecté automatiquement au récepteur");

      // Envoyer les données si elles ont déjà été extraites
      if (extractedData != null) {
        _socket!.add(jsonEncode(extractedData));
        print("📤 Données envoyées automatiquement");
      }
    } catch (e) {
      print("❌ Échec de connexion au récepteur : $e");
    }
  }

  Future<void> _speakText(String message) async {
    if (isSpeaking) return;

    setState(() {
      isSpeaking = true;
    });

    const voice = "nova";
    final apiKey = GlobalConfig.openAIApiKey;

    try {
      final response = await http.post(
        Uri.parse("https://api.openai.com/v1/audio/speech"),
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": "tts-1",
          "voice": voice,
          "input": message,
        }),
      );

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final audioFile = File("${tempDir.path}/louna_intro.mp3");
        await audioFile.writeAsBytes(response.bodyBytes);
        await player.stop();
        await player.play(DeviceFileSource(audioFile.path));
      } else {
        debugPrint("❌ TTS Error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Exception TTS: $e");
    }

    setState(() {
      isSpeaking = false;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        extractedData = null;
        isProcessing = true;
      });

      _fadeController.forward();
      await _scanImageWithOCR();
    }
  }

  Future<void> _scanImageWithOCR() async {
    if (_selectedImage == null) return;

    final data = await _ocrService.scanTextFromImage(_selectedImage!);
    setState(() {
      extractedData = data;
      isProcessing = false;
    });

    print("📤 Données extraites : $data");

    // Envoi automatique
    if (_socket != null) {
      _socket!.add(jsonEncode(data));
      print("📤 Données envoyées via WebSocket");
    } else {
      print("⚠️ WebSocket non connecté");
    }
  }

  Widget _buildLounaAvatar() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 120 + (_pulseController.value * 10),
          height: 120 + (_pulseController.value * 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Colors.blue.shade400,
                Colors.purple.shade400,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: _pulseController.value * 5,
              ),
            ],
          ),
          child: const Icon(
            Icons.smart_toy_rounded,
            size: 60,
            color: Colors.white,
          ),
        );
      },
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStyledButton(
                  icon: Icons.photo_library_rounded,
                  label: "Galerie",
                  color: Colors.orange,
                  onPressed: () => _pickImage(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildStyledButton(
                  icon: Icons.camera_alt_rounded,
                  label: "Caméra",
                  color: Colors.blue,
                  onPressed: () => _pickImage(ImageSource.camera),
                ),
              ),
            ],
          ),
          if (isSpeaking) ...[
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "LOUNA parle...",
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStyledButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        elevation: 3,
        shadowColor: color.withOpacity(0.3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return FadeTransition(
      opacity: _fadeController,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.file(
            _selectedImage!,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Analyse en cours...",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "LOUNA traite votre document",
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedData() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: Colors.green.shade600,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                "Données extraites",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ...extractedData!.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 100,
                    child: Text(
                      "${entry.key}:",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    player.dispose();
    _socket?.close();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          "Validation d'identité",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blue.shade600,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Avatar LOUNA
            _buildLounaAvatar(),
            const SizedBox(height: 20),

            // Message de bienvenue
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    "Bonjour ! Je suis LOUNA 🤖",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Scannez votre carte d'identité pour commencer la validation",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Boutons d'action
            _buildActionButtons(),

            // Image sélectionnée
            if (_selectedImage != null) _buildImagePreview(),

            // Indicateur de traitement
            if (isProcessing) ...[
              const SizedBox(height: 20),
              _buildProcessingIndicator(),
            ],

            // Données extraites
            if (extractedData != null && !isProcessing) ...[
              const SizedBox(height: 20),
              _buildExtractedData(),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:math';

class StyledCameraScreen extends StatefulWidget {
  final Function(XFile) onCaptured;
  const StyledCameraScreen({Key? key, required this.onCaptured}) : super(key: key);

  @override
  State<StyledCameraScreen> createState() => _StyledCameraScreenState();
}

class _StyledCameraScreenState extends State<StyledCameraScreen> {
  CameraController? _controller;
  bool _isReady = false;
  bool _isDetecting = false;
  bool _showCaptureHint = true;
  late List<CameraDescription> _cameras;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    final camera = _cameras.first;
    _controller = CameraController(camera, ResolutionPreset.high);
    await _controller!.initialize();
    if (!mounted) return;
    setState(() => _isReady = true);

    // Petite animation d'apparition du cadre
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showCaptureHint = false);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final file = await _controller!.takePicture();
    widget.onCaptured(file);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // === Flux caméra ===
          CameraPreview(_controller!),

          // === Cadre de détection ===
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 300,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isDetecting ? Colors.greenAccent : Colors.cyanAccent,
                  width: 4,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (_isDetecting ? Colors.greenAccent : Colors.cyanAccent)
                        .withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),

          // === Texte d’instructions ===
          Positioned(
            bottom: 180,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showCaptureHint ? 1 : 0.7,
              duration: const Duration(milliseconds: 500),
              child: Text(
                _isDetecting
                    ? "✅ Carte détectée — capture automatique..."
                    : "Placez la carte d'identité dans le cadre",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isDetecting ? Colors.greenAccent : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.6),
                      offset: const Offset(1, 1),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // === Bouton de capture ===
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _capture,
                onLongPress: () {
                  // Simulation d’auto-détection (pour test)
                  setState(() => _isDetecting = true);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) _capture();
                  });
                },
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 5),
                    gradient: const RadialGradient(
                      colors: [Colors.cyanAccent, Colors.blueAccent],
                      radius: 0.9,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withOpacity(0.6),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.black, size: 38),
                ),
              ),
            ),
          ),

          // === Bouton retour ===
          Positioned(
            top: 40,
            left: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

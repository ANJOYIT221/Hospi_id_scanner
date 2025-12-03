import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';

class DocumentCameraScreen extends StatefulWidget {
  const DocumentCameraScreen({Key? key}) : super(key: key);

  @override
  State<DocumentCameraScreen> createState() => _DocumentCameraScreenState();
}

class _DocumentCameraScreenState extends State<DocumentCameraScreen>
    with SingleTickerProviderStateMixin {

  CameraController? _camera;
  bool _isReady = false;
  bool _isScanning = true;
  bool _isDetecting = false;
  int _countdown = 0;
  Timer? _countdownTimer;
  File? _capturedPhoto;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    _camera = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _camera!.initialize();

    if (!mounted) return;
    setState(() => _isReady = true);

    await Future.delayed(const Duration(seconds: 3));

    if (mounted && _isScanning) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    setState(() {
      _isDetecting = true;
      _countdown = 3;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        _captureFinalPhoto();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _isDetecting = false;
      _countdown = 0;
    });
  }

  Future<void> _captureFinalPhoto() async {
    try {
      final XFile photo = await _camera!.takePicture();

      setState(() {
        _capturedPhoto = File(photo.path);
        _isScanning = false;
        _isDetecting = false;
      });

    } catch (e) {
      debugPrint('Erreur capture: $e');
      _cancelCountdown();
    }
  }

  void _validatePhoto() {
    if (_capturedPhoto != null) {
      Navigator.pop(context, _capturedPhoto);
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedPhoto = null;
      _isScanning = true;
    });
    _initCamera();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _camera == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.cyan),
        ),
      );
    }

    if (!_isScanning && _capturedPhoto != null) {
      return _buildPreviewScreen();
    }

    return _buildCameraScreen();
  }

  Widget _buildCameraScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: CameraPreview(_camera!),
          ),

          _buildOverlay(),

          Center(child: _buildFrame()),

          if (_isDetecting)
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.3),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green, width: 3),
                ),
                child: Center(
                  child: Text(
                    '$_countdown',
                    style: const TextStyle(
                      fontSize: 60,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.black, blurRadius: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            bottom: 150,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _isDetecting
                    ? Colors.green.withOpacity(0.3)
                    : Colors.cyan.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isDetecting ? Colors.green : Colors.cyan,
                  width: 2,
                ),
              ),
              child: Text(
                _isDetecting
                    ? '📸 Photo dans $_countdown...'
                    : '📄 Placez votre carte dans le cadre',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 10),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            top: 40,
            left: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),

          if (_isDetecting)
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onTap: _cancelCountdown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, color: Colors.white, size: 20),
                      SizedBox(width: 6),
                      Text(
                        'Annuler',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Image.file(
              _capturedPhoto!,
              fit: BoxFit.contain,
            ),
          ),

          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.cyan, width: 2),
              ),
              child: const Text(
                '📸 Photo capturée !\nVérifiez que le document est lisible',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 50,
            left: 20,
            right: 20,
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _retakePhoto,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.refresh, color: Colors.white, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Recommencer',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: GestureDetector(
                    onTap: _validatePhoto,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: Colors.white, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Valider',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildOverlay() {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withOpacity(0.6),
        BlendMode.srcOut,
      ),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.black,
              backgroundBlendMode: BlendMode.dstOut,
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 300,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrame() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 300,
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(
              color: _isDetecting
                  ? Colors.green
                  : Colors.cyan.withOpacity(0.5 + _pulseController.value * 0.5),
              width: _isDetecting ? 5 : 3,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: (_isDetecting ? Colors.green : Colors.cyan).withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _camera?.dispose();
    _pulseController.dispose();
    super.dispose();
  }
}
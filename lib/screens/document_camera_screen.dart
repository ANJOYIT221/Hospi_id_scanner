import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

class DocumentCameraScreen extends StatefulWidget {
  const DocumentCameraScreen({Key? key}) : super(key: key);

  @override
  State<DocumentCameraScreen> createState() => _DocumentCameraScreenState();
}

enum DocumentType {
  none,
  newId,
  oldId,
  passport,
}

class _DocumentCameraScreenState extends State<DocumentCameraScreen>
    with TickerProviderStateMixin {

  CameraController? _camera;
  bool _isReady = false;
  bool _isScanning = true;
  bool _isDetecting = false;
  bool _isProcessingFrame = false;
  int _countdown = 0;
  Timer? _countdownTimer;
  Timer? _detectionTimer;
  File? _capturedPhoto;

  DocumentType _detectedType = DocumentType.none;

  late AnimationController _pulseController;
  late AnimationController _progressController;

  Timer? _autoValidateTimer;
  int _autoValidateCountdown = 5;

  TextRecognizer? _textRecognizer;

  int _consecutiveDetections = 0;
  static const int _requiredDetections = 3;

  static const int _analysisPeriodMs = 800;

  Timer? _inactivityTimer;
  static const Duration _inactivityDuration = Duration(minutes: 5);

  static const Map<DocumentType, Map<String, double>> _frameSizes = {
    DocumentType.newId: {'width': 300, 'height': 190},
    DocumentType.oldId: {'width': 340, 'height': 240},
    DocumentType.passport: {'width': 380, 'height': 270},
  };

  static const Map<DocumentType, Color> _frameColors = {
    DocumentType.newId: Colors.cyan,
    DocumentType.oldId: Colors.purpleAccent,
    DocumentType.passport: Colors.blue,
  };

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _textRecognizer = GoogleMlKit.vision.textRecognizer();

    _initCamera();
    _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityDuration, () {
      if (mounted) {
        print('⏰ Inactivité détectée - Retour au splash');
        Navigator.pop(context);
      }
    });
  }

  void _onUserActivity() {
    _resetInactivityTimer();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      _camera = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _camera!.initialize();

      if (!mounted) return;
      setState(() => _isReady = true);

      _startDocumentDetection();
    } catch (e) {
      debugPrint('❌ Erreur initialisation caméra: $e');
    }
  }

  void _startDocumentDetection() {
    _detectionTimer = Timer.periodic(
      const Duration(milliseconds: _analysisPeriodMs),
          (timer) async {
        if (!_isScanning || _isDetecting || _isProcessingFrame || _camera == null) return;
        await _analyzeFrame();
      },
    );
  }

  Future<void> _analyzeFrame() async {
    if (_camera == null || !_camera!.value.isInitialized) return;
    if (_isProcessingFrame || _textRecognizer == null) return;

    _isProcessingFrame = true;

    String? tempFilePath;

    try {
      final XFile imageFile = await _camera!.takePicture();
      tempFilePath = imageFile.path;

      final inputImage = InputImage.fromFilePath(tempFilePath);
      final RecognizedText recognizedText = await _textRecognizer!.processImage(inputImage);

      try {
        await File(tempFilePath).delete();
      } catch (_) {}

      final analysisResult = _analyzeDocument(recognizedText);
      final bool documentDetected = analysisResult['detected'] as bool;
      final DocumentType detectedType = analysisResult['type'] as DocumentType;

      if (!mounted) return;

      if (documentDetected) {
        _consecutiveDetections++;

        setState(() {
          _detectedType = detectedType;
        });

        debugPrint('📄 Document détecté (${_consecutiveDetections}/$_requiredDetections)');

        if (_consecutiveDetections >= _requiredDetections && !_isDetecting) {
          _startCountdown();
        }
      } else {
        if (_consecutiveDetections > 0) {
          debugPrint('❌ Document sorti du cadre');
        }
        _consecutiveDetections = 0;

        setState(() {
          _detectedType = DocumentType.none;
        });

        if (_isDetecting) {
          _cancelCountdown();
        }
      }
    } catch (e) {
      debugPrint('Erreur analyse frame: $e');
      if (tempFilePath != null) {
        try {
          await File(tempFilePath).delete();
        } catch (_) {}
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  Map<String, dynamic> _analyzeDocument(RecognizedText recognizedText) {
    if (recognizedText.blocks.isEmpty) {
      return {'detected': false, 'type': DocumentType.none};
    }

    int totalTextLength = 0;
    int blockCount = recognizedText.blocks.length;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = 0;
    double maxY = 0;

    for (final block in recognizedText.blocks) {
      totalTextLength += block.text.length;

      final boundingBox = block.boundingBox;
      if (boundingBox != null) {
        minX = math.min(minX, boundingBox.left);
        minY = math.min(minY, boundingBox.top);
        maxX = math.max(maxX, boundingBox.right);
        maxY = math.max(maxY, boundingBox.bottom);
      }
    }

    final bool hasEnoughBlocks = blockCount >= 2;
    final bool hasEnoughText = totalTextLength >= 20;

    final String allText = recognizedText.text.toUpperCase();
    final bool hasIdKeywords = allText.contains('NOM') ||
        allText.contains('PRENOM') ||
        allText.contains('SURNAME') ||
        allText.contains('GIVEN') ||
        allText.contains('BIRTH') ||
        allText.contains('NATIONALITY') ||
        allText.contains('NATIONALITE') ||
        allText.contains('REPUBLIC') ||
        allText.contains('CARTE') ||
        allText.contains('IDENTITY') ||
        allText.contains('IDENTITE') ||
        allText.contains('PASSPORT') ||
        allText.contains('TITRE') ||
        allText.contains('SEJOUR') ||
        allText.contains('PERMIT');

    final bool documentDetected = (hasEnoughBlocks && hasEnoughText) || hasIdKeywords;

    if (!documentDetected) {
      return {'detected': false, 'type': DocumentType.none};
    }

    DocumentType detectedType = _determineDocumentType(
      recognizedText: recognizedText,
      allText: allText,
      textWidth: maxX - minX,
      textHeight: maxY - minY,
      totalTextLength: totalTextLength,
      blockCount: blockCount,
    );

    return {'detected': true, 'type': detectedType};
  }

  DocumentType _determineDocumentType({
    required RecognizedText recognizedText,
    required String allText,
    required double textWidth,
    required double textHeight,
    required int totalTextLength,
    required int blockCount,
  }) {
    final bool isPassport = allText.contains('PASSEPORT') ||
        allText.contains('PASSPORT') ||
        allText.contains('P<FRA') ||
        allText.contains('P<') ||
        (allText.contains('REPUBLIC') && allText.contains('FRANCAISE') && totalTextLength > 200);

    if (isPassport) {
      return DocumentType.passport;
    }

    final bool isNewId = allText.contains('IDFRA') ||
        allText.contains('TITRE DE SEJOUR') ||
        allText.contains('RESIDENCE PERMIT') ||
        allText.contains('CARTE NATIONALE') ||
        allText.contains('IDENTITY CARD');

    if (totalTextLength > 150 && blockCount > 5) {
      int mrzIndicators = '<'.allMatches(allText).length;
      if (mrzIndicators > 10) {
        return DocumentType.passport;
      }
    }

    if (textWidth > 600 && textHeight > 400) {
      if (totalTextLength > 120) {
        return DocumentType.passport;
      } else {
        return DocumentType.oldId;
      }
    }

    if (textWidth > 450 && textHeight > 300) {
      return DocumentType.oldId;
    }

    if (isNewId || (textWidth < 500 && textHeight < 350)) {
      return DocumentType.newId;
    }

    return DocumentType.newId;
  }

  void _startCountdown() {
    _detectionTimer?.cancel();

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
      _consecutiveDetections = 0;
    });

    _startDocumentDetection();
  }

  Future<void> _captureFinalPhoto() async {
    _onUserActivity();
    try {
      final XFile photo = await _camera!.takePicture();

      setState(() {
        _capturedPhoto = File(photo.path);
        _isScanning = false;
        _isDetecting = false;
      });

      _startAutoValidateTimer();

    } catch (e) {
      debugPrint('Erreur capture: $e');
      _cancelCountdown();
    }
  }

  void _startAutoValidateTimer() {
    _autoValidateCountdown = 5;
    _progressController.forward(from: 0);

    _autoValidateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_autoValidateCountdown > 1) {
        setState(() => _autoValidateCountdown--);
      } else {
        timer.cancel();
        _validatePhoto();
      }
    });
  }

  void _cancelAutoValidateTimer() {
    _autoValidateTimer?.cancel();
    _progressController.stop();
    _progressController.reset();
  }

  void _validatePhoto() {
    _onUserActivity();
    _cancelAutoValidateTimer();
    if (_capturedPhoto != null) {
      Navigator.pop(context, _capturedPhoto);
    }
  }

  void _retakePhoto() {
    _onUserActivity();
    _cancelAutoValidateTimer();

    setState(() {
      _capturedPhoto = null;
      _isScanning = true;
      _consecutiveDetections = 0;
      _autoValidateCountdown = 5;
      _detectedType = DocumentType.none;
    });
    _initCamera();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _camera == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.cyan),
              SizedBox(height: 20),
              Text(
                'Initialisation de la caméra...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isScanning && _capturedPhoto != null) {
      return _buildPreviewScreen();
    }

    return _buildCameraScreen();
  }

  Widget _buildCameraScreen() {
    return GestureDetector(
      onTap: _onUserActivity,
      onPanDown: (_) => _onUserActivity(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: CameraPreview(_camera!),
            ),

            _buildOverlay(),

            Center(child: _buildMultiFrames()),

            // 🆕 PAS DE COMPTE À REBOURS PENDANT LA DÉTECTION

            Positioned(
              bottom: 180,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: _isDetecting
                      ? (_frameColors[_detectedType] ?? Colors.green).withOpacity(0.3)
                      : Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isDetecting
                        ? (_frameColors[_detectedType] ?? Colors.green)
                        : Colors.white30,
                    width: 2,
                  ),
                ),
                child: Text(
                  _isDetecting
                      ? '📸 Document détecté ! Capture en cours...'
                      : '📄 Placez votre pièce dans le cadre',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 10),
                    ],
                  ),
                ),
              ),
            ),

            if (!_isDetecting && _detectedType == DocumentType.none)
              Positioned(
                bottom: 250,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.cyan),
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Recherche de document...',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            Positioned(
              top: 40,
              left: 20,
              child: GestureDetector(
                onTap: () {
                  _onUserActivity();
                  Navigator.pop(context);
                },
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
                  onTap: () {
                    _onUserActivity();
                    _cancelCountdown();
                  },
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
      ),
    );
  }

  Widget _buildMultiFrames() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            _buildSingleFrame(
              type: DocumentType.passport,
              isActive: _detectedType == DocumentType.passport,
            ),
            _buildSingleFrame(
              type: DocumentType.oldId,
              isActive: _detectedType == DocumentType.oldId,
            ),
            _buildSingleFrame(
              type: DocumentType.newId,
              isActive: _detectedType == DocumentType.newId,
            ),
          ],
        );
      },
    );
  }

  Widget _buildSingleFrame({
    required DocumentType type,
    required bool isActive,
  }) {
    final size = _frameSizes[type]!;
    final color = _frameColors[type]!;

    final double opacity = isActive ? 1.0 : (0.15 + _pulseController.value * 0.1);
    final double borderWidth = isActive ? 3.0 : 1.5;
    final double shadowSpread = isActive ? 3.0 : 0.5;
    final double shadowBlur = isActive ? 20.0 : 8.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size['width'],
      height: size['height'],
      decoration: BoxDecoration(
        border: Border.all(
          color: color.withOpacity(opacity),
          width: borderWidth,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isActive ? 0.4 : 0.15),
            blurRadius: shadowBlur,
            spreadRadius: shadowSpread,
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    final passportSize = _frameSizes[DocumentType.passport]!;

    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withOpacity(0.5),
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
              width: passportSize['width']! + 20,
              height: passportSize['height']! + 20,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewScreen() {
    return GestureDetector(
      onTap: _onUserActivity,
      onPanDown: (_) => _onUserActivity(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: Image.file(
                _capturedPhoto!,
                fit: BoxFit.contain,
              ),
            ),

            // 🆕 PREVIEW AVEC BARRE VERTE (SANS CHIFFRE)
            Positioned(
              top: 60,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.8),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Colors.green,
                          size: 28,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Document capturé !',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 🆕 CADENAS + "Vérification sécurisée"
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.4),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.lock_outline_rounded,
                              color: Colors.green,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Vérification sécurisée',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 🆕 BARRE DE PROGRESSION VERTE (SANS TEXTE DE COMPTE À REBOURS)
                    AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, child) {
                        return Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade900,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.green.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: _progressController.value,
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.green.shade400,
                              ),
                              minHeight: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              bottom: 50,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _retakePhoto,
                    child: Container(
                      width: double.infinity,
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
                          SizedBox(width: 10),
                          Text(
                            '🔄 Recommencer la photo',
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

                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: _validatePhoto,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.green.withOpacity(0.8),
                            Colors.green,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
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
                          SizedBox(width: 10),
                          Text(
                            '✅ Valider maintenant',
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

                  const SizedBox(height: 16),

                  // 🆕 TEXTE ÉLÉGANT "VALIDATION AUTOMATIQUE"
                  AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, child) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.4),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: Colors.green.shade300,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Validation automatique si aucune action',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.95),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _detectionTimer?.cancel();
    _autoValidateTimer?.cancel();
    _inactivityTimer?.cancel();
    _camera?.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    _textRecognizer?.close();
    super.dispose();
  }
}
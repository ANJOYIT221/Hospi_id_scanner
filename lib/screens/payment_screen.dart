import 'dart:async';
import 'package:flutter/material.dart';
import '../services/payment_service.dart';

class PaymentScreen extends StatefulWidget {
  final Map<String, String> booking;
  final double taxAmount;
  final Function(PaymentResult)? onPaymentComplete;

  const PaymentScreen({
    Key? key,
    required this.booking,
    this.taxAmount = 0.0,
    this.onPaymentComplete,
  }) : super(key: key);

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with TickerProviderStateMixin {
  final PaymentService _paymentService = PaymentService();

  bool _isProcessing = false;
  bool _isInitialized = false;
  PaymentResult? _paymentResult;
  String _statusMessage = 'Initialisation...';
  String _selectedMethod = 'any'; // 'chip', 'contactless', 'any'

  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  Timer? _timeoutTimer;
  static const int _paymentTimeoutSeconds = 60;

  static const Color primaryBlue = Color(0xFF0A84FF);
  static const Color darkBlue = Color(0xFF0066CC);
  static const Color accentPurple = Color(0xFF7C3AED);
  static const Color successGreen = Color(0xFF34C759);
  static const Color warningAmber = Color(0xFFFFB800);
  static const Color errorRed = Color(0xFFFF3B30);
  static const Color bgLight = Color(0xFFF5F7FA);
  static const Color cardWhite = Colors.white;
  static const Color textDark = Color(0xFF1C1C1E);
  static const Color textMuted = Color(0xFF8E8E93);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializePaymentTerminal();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _fadeController.forward();
  }

  Future<void> _initializePaymentTerminal() async {
    setState(() {
      _statusMessage = 'Initialisation du terminal...';
    });

    final initialized = await _paymentService.initialize();

    if (!mounted) return;

    setState(() {
      _isInitialized = initialized;
      _statusMessage = initialized
          ? 'Terminal prêt'
          : 'Erreur d\'initialisation du terminal';
    });

    if (!initialized) {
      _showErrorDialog('Erreur Terminal',
          'Impossible d\'initialiser le terminal de paiement. Veuillez contacter le personnel.');
    }
  }

  Future<void> _startPayment(String method) async {
    if (!_isInitialized) {
      _showSnackBar('Terminal non prêt', errorRed);
      return;
    }

    setState(() {
      _isProcessing = true;
      _selectedMethod = method;
      _statusMessage = method == 'contactless'
          ? 'Approchez votre carte sans contact...'
          : 'Insérez votre carte...';
      _paymentResult = null;
    });

    // Timeout de sécurité
    _timeoutTimer = Timer(const Duration(seconds: _paymentTimeoutSeconds), () {
      if (_isProcessing && mounted) {
        _cancelPayment();
        _showSnackBar('Timeout - Aucune carte détectée', warningAmber);
      }
    });

    try {
      final result = await _paymentService.processPayment(
        amount: widget.taxAmount,
        currency: 'EUR',
        paymentMethod: method,
      );

      _timeoutTimer?.cancel();

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
        _paymentResult = result;
        _statusMessage = result.success
            ? 'Paiement accepté !'
            : 'Paiement refusé : ${result.errorMessage}';
      });

      if (result.success) {
        _showSuccessDialog(result);
      } else {
        _showErrorDialog('Paiement refusé', result.errorMessage ?? 'Erreur inconnue');
      }
    } catch (e) {
      _timeoutTimer?.cancel();

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
        _statusMessage = 'Erreur : $e';
      });

      _showErrorDialog('Erreur', 'Une erreur est survenue : $e');
    }
  }

  Future<void> _cancelPayment() async {
    final cancelled = await _paymentService.cancelPayment();

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _statusMessage = cancelled ? 'Paiement annulé' : 'Terminal prêt';
    });
  }

  void _showSuccessDialog(PaymentResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: cardWhite,
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: successGreen, size: 32),
            SizedBox(width: 12),
            Text('Paiement accepté', style: TextStyle(color: successGreen, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Montant', '${result.amount} ${result.currency}'),
            _buildInfoRow('Transaction', result.transactionId ?? 'N/A'),
            _buildInfoRow('Carte', '${result.cardType ?? 'N/A'} ${result.cardNumber ?? '****'}'),
            _buildInfoRow('Méthode', result.paymentMethod == 'contactless' ? 'Sans contact' : 'Puce'),
            if (result.receiptPrinted == true)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: const [
                    Icon(Icons.print, color: successGreen, size: 16),
                    SizedBox(width: 6),
                    Text('Reçu imprimé', style: TextStyle(fontSize: 12, color: textMuted, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Ferme le dialog
              Navigator.pop(context, result); // Retourne à IdScannerScreen
              widget.onPaymentComplete?.call(result);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: successGreen,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continuer', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: cardWhite,
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: errorRed, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(color: errorRed, fontWeight: FontWeight.w800))),
          ],
        ),
        content: Text(message, style: const TextStyle(color: textDark)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(color: textDark, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        backgroundColor: bgLight,
        foregroundColor: textDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: _isProcessing
              ? null
              : () => Navigator.pop(context),
        ),
        title: const Text(
          'PAIEMENT TAXE HÔTELIÈRE',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4, fontSize: 16),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildBookingInfoCard(),
              const SizedBox(height: 16),
              _buildAmountCard(),
              const SizedBox(height: 24),
              if (!_isProcessing) _buildPaymentMethodsCard(),
              if (_isProcessing) _buildProcessingCard(),
              if (_paymentResult != null && !_isProcessing) _buildResultCard(),
              const SizedBox(height: 24),
              _buildStatusCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookingInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.person_outline, color: primaryBlue, size: 20),
              SizedBox(width: 8),
              Text('Informations client', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textDark)),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Nom', widget.booking['surname'] ?? 'N/A'),
          _buildInfoRow('Prénom', widget.booking['name'] ?? 'N/A'),
          _buildInfoRow('Chambre', widget.booking['roomType'] ?? 'Standard'),
          _buildInfoRow('Séjour', '${widget.booking['nights'] ?? '0'} nuit(s)'),
        ],
      ),
    );
  }

  Widget _buildAmountCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryBlue, accentPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: primaryBlue.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'MONTANT À PAYER',
            style: TextStyle(color: cardWhite, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.taxAmount.toStringAsFixed(2)} €',
            style: const TextStyle(color: cardWhite, fontSize: 48, fontWeight: FontWeight.w900, height: 1),
          ),
          const SizedBox(height: 4),
          const Text(
            'Taxe de séjour',
            style: TextStyle(color: cardWhite, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.payment, color: primaryBlue, size: 20),
              SizedBox(width: 8),
              Text('Choisissez un mode de paiement', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textDark)),
            ],
          ),
          const SizedBox(height: 16),
          _buildPaymentButton(
            icon: Icons.credit_card,
            label: 'Insérer la carte',
            subtitle: 'Puce EMV',
            method: 'chip',
            gradient: const LinearGradient(colors: [primaryBlue, darkBlue]),
          ),
          const SizedBox(height: 12),
          _buildPaymentButton(
            icon: Icons.contactless,
            label: 'Sans contact',
            subtitle: 'NFC',
            method: 'contactless',
            gradient: const LinearGradient(colors: [accentPurple, primaryBlue]),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required String method,
    required Gradient gradient,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isInitialized ? () => _startPayment(method) : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: cardWhite, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(color: cardWhite, fontSize: 16, fontWeight: FontWeight.w800)),
                      Text(subtitle, style: TextStyle(color: cardWhite.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: cardWhite, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingCard() {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: primaryBlue.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(color: primaryBlue.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                strokeWidth: 6,
                valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textDark),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedMethod == 'contactless'
                  ? 'Maintenez la carte sur le lecteur'
                  : 'Ne retirez pas la carte',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: textMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _cancelPayment,
              child: const Text('Annuler', style: TextStyle(color: errorRed, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final isSuccess = _paymentResult?.success == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSuccess ? successGreen.withOpacity(0.3) : errorRed.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isSuccess ? successGreen : errorRed).withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            isSuccess ? Icons.check_circle : Icons.error_outline,
            color: isSuccess ? successGreen : errorRed,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            isSuccess ? 'Paiement accepté !' : 'Paiement refusé',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isSuccess ? successGreen : errorRed,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: textMuted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primaryBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            _isInitialized ? Icons.check_circle : Icons.info_outline,
            color: _isInitialized ? successGreen : warningAmber,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                color: _isInitialized ? successGreen : warningAmber,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
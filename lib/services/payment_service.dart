import 'package:flutter/services.dart';

/// Service de gestion des paiements via le lecteur de carte Sunmi
/// Utilise le plugin itc_sunmi_card_reader pour :
/// - Lire les cartes (EMV, sans contact, piste magnétique)
/// - Traiter les paiements
/// - Imprimer les reçus
class PaymentService {
  static const MethodChannel _channel = MethodChannel('itc_sunmi_card_reader');

  /// Initialise le lecteur de carte Sunmi
  Future<bool> initialize() async {
    try {
      final result = await _channel.invokeMethod('initialize');
      print('✅ Lecteur de carte initialisé: $result');
      return result == true;
    } catch (e) {
      print('❌ Erreur initialisation lecteur: $e');
      return false;
    }
  }

  /// Lance un paiement avec le montant spécifié
  ///
  /// [amount] : Montant en euros (ex: 1.50 pour 1,50€)
  /// [currency] : Code devise (EUR par défaut)
  /// [paymentMethod] : 'chip' pour puce, 'contactless' pour sans contact, 'any' pour les deux
  ///
  /// Retourne un [PaymentResult] avec les détails de la transaction
  Future<PaymentResult> processPayment({
    required double amount,
    String currency = 'EUR',
    String paymentMethod = 'any',
  }) async {
    try {
      print('💳 ========== DÉBUT PAIEMENT ==========');
      print('💰 Montant: $amount $currency');
      print('📱 Méthode: $paymentMethod');

      final args = {
        'amount': amount,
        'currency': currency,
        'paymentMethod': paymentMethod,
      };

      final result = await _channel.invokeMethod('processPayment', args);

      if (result == null) {
        print('❌ Résultat null du plugin');
        return PaymentResult.error('Aucune réponse du terminal');
      }

      print('📥 Résultat brut: $result');

      // Parse du résultat
      final status = result['status'] ?? 'error';

      if (status == 'success') {
        final paymentResult = PaymentResult.success(
          transactionId: result['transactionId'] ?? _generateTransactionId(),
          amount: amount,
          currency: currency,
          cardType: result['cardType'] ?? 'Unknown',
          cardNumber: result['cardNumber'] ?? '****',
          paymentMethod: result['paymentMethod'] ?? paymentMethod,
          timestamp: DateTime.now(),
          receiptPrinted: result['receiptPrinted'] ?? false,
        );

        print('✅ ========== PAIEMENT RÉUSSI ==========');
        print('📝 Transaction ID: ${paymentResult.transactionId}');
        print('💳 Carte: ${paymentResult.cardType} ${paymentResult.cardNumber}');
        print('========================================');

        return paymentResult;
      } else {
        final errorMessage = result['message'] ?? 'Erreur inconnue';
        print('❌ ========== PAIEMENT ÉCHOUÉ ==========');
        print('📝 Raison: $errorMessage');
        print('========================================');

        return PaymentResult.error(errorMessage);
      }

    } on PlatformException catch (e) {
      print('❌ PlatformException: ${e.code} - ${e.message}');
      return PaymentResult.error('Erreur terminal: ${e.message}');
    } catch (e) {
      print('❌ Erreur inattendue: $e');
      return PaymentResult.error('Erreur inattendue: $e');
    }
  }

  /// Imprime un reçu pour une transaction
  ///
  /// Utilisé si l'impression automatique a échoué
  Future<bool> printReceipt({
    required String transactionId,
    required double amount,
    required String currency,
    String? cardType,
    String? cardNumber,
    String? merchantName,
    DateTime? timestamp,
  }) async {
    try {
      print('🖨️ Impression du reçu...');

      final args = {
        'transactionId': transactionId,
        'amount': amount,
        'currency': currency,
        'cardType': cardType,
        'cardNumber': cardNumber,
        'merchantName': merchantName ?? 'HospiSmart Hotel',
        'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
      };

      final result = await _channel.invokeMethod('printReceipt', args);

      if (result == true) {
        print('✅ Reçu imprimé avec succès');
        return true;
      } else {
        print('⚠️ Échec impression reçu');
        return false;
      }

    } catch (e) {
      print('❌ Erreur impression: $e');
      return false;
    }
  }

  /// Annule une transaction en cours
  Future<bool> cancelPayment() async {
    try {
      print('🚫 Annulation du paiement...');
      final result = await _channel.invokeMethod('cancelPayment');
      print(result == true ? '✅ Paiement annulé' : '⚠️ Échec annulation');
      return result == true;
    } catch (e) {
      print('❌ Erreur annulation: $e');
      return false;
    }
  }

  /// Vérifie si le terminal est prêt
  Future<bool> isReady() async {
    try {
      final result = await _channel.invokeMethod('isReady');
      return result == true;
    } catch (e) {
      print('❌ Erreur vérification terminal: $e');
      return false;
    }
  }

  /// Génère un ID de transaction unique (fallback)
  String _generateTransactionId() {
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    return 'TXN${timestamp}${(timestamp % 10000).toString().padLeft(4, '0')}';
  }
}

/// Résultat d'une transaction de paiement
class PaymentResult {
  final bool success;
  final String? transactionId;
  final double? amount;
  final String? currency;
  final String? cardType;
  final String? cardNumber;
  final String? paymentMethod;
  final DateTime? timestamp;
  final bool? receiptPrinted;
  final String? errorMessage;

  PaymentResult._({
    required this.success,
    this.transactionId,
    this.amount,
    this.currency,
    this.cardType,
    this.cardNumber,
    this.paymentMethod,
    this.timestamp,
    this.receiptPrinted,
    this.errorMessage,
  });

  /// Crée un résultat de succès
  factory PaymentResult.success({
    required String transactionId,
    required double amount,
    required String currency,
    String? cardType,
    String? cardNumber,
    String? paymentMethod,
    DateTime? timestamp,
    bool receiptPrinted = false,
  }) {
    return PaymentResult._(
      success: true,
      transactionId: transactionId,
      amount: amount,
      currency: currency,
      cardType: cardType,
      cardNumber: cardNumber,
      paymentMethod: paymentMethod,
      timestamp: timestamp ?? DateTime.now(),
      receiptPrinted: receiptPrinted,
    );
  }

  /// Crée un résultat d'erreur
  factory PaymentResult.error(String message) {
    return PaymentResult._(
      success: false,
      errorMessage: message,
    );
  }

  /// Convertit en Map pour l'envoi WebSocket
  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'transactionId': transactionId,
      'amount': amount,
      'currency': currency,
      'cardType': cardType,
      'cardNumber': cardNumber,
      'paymentMethod': paymentMethod,
      'timestamp': timestamp?.toIso8601String(),
      'receiptPrinted': receiptPrinted,
      'errorMessage': errorMessage,
    };
  }

  @override
  String toString() {
    if (success) {
      return 'PaymentResult(SUCCESS, txn: $transactionId, amount: $amount $currency)';
    } else {
      return 'PaymentResult(ERROR: $errorMessage)';
    }
  }
}
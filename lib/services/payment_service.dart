import 'package:flutter/services.dart';

class PaymentService {
  static const MethodChannel _channel = MethodChannel('com.hospi_id_scanner/payment');

  Future<bool> initialize() async {
    try {
      final result = await _channel.invokeMethod<bool>('initialize');
      print('✅ Terminal de paiement initialisé: $result');
      return result ?? false;
    } on PlatformException catch (e) {
      print('❌ Erreur initialisation terminal: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('❌ Erreur inattendue initialisation: $e');
      return false;
    }
  }

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

      final result = await _channel.invokeMethod<Map>('processPayment', args);

      if (result == null) {
        print('❌ Résultat null du plugin');
        return PaymentResult.error('Aucune réponse du terminal');
      }

      print('📥 Résultat brut: $result');

      final resultMap = Map<String, dynamic>.from(result);
      final status = resultMap['status'] ?? 'error';

      if (status == 'success') {
        final paymentResult = PaymentResult.success(
          transactionId: resultMap['transactionId'] ?? _generateTransactionId(),
          amount: amount,
          currency: currency,
          cardType: resultMap['cardType'] ?? 'Unknown',
          cardNumber: resultMap['cardNumber'] ?? '****',
          paymentMethod: resultMap['paymentMethod'] ?? paymentMethod,
          timestamp: DateTime.now(),
          receiptPrinted: resultMap['receiptPrinted'] ?? false,
        );

        print('✅ ========== PAIEMENT RÉUSSI ==========');
        print('📝 Transaction ID: ${paymentResult.transactionId}');
        print('💳 Carte: ${paymentResult.cardType} ${paymentResult.cardNumber}');
        print('========================================');

        return paymentResult;
      } else {
        final errorMessage = resultMap['message'] ?? 'Erreur inconnue';
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

      final result = await _channel.invokeMethod<bool>('printReceipt', args);

      if (result == true) {
        print('✅ Reçu imprimé avec succès');
        return true;
      } else {
        print('⚠️ Échec impression reçu');
        return false;
      }

    } on PlatformException catch (e) {
      print('❌ Erreur impression: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('❌ Erreur inattendue impression: $e');
      return false;
    }
  }

  Future<bool> cancelPayment() async {
    try {
      print('🚫 Annulation du paiement...');
      final result = await _channel.invokeMethod<bool>('cancelPayment');
      print(result == true ? '✅ Paiement annulé' : '⚠️ Échec annulation');
      return result == true;
    } on PlatformException catch (e) {
      print('❌ Erreur annulation: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('❌ Erreur inattendue annulation: $e');
      return false;
    }
  }

  Future<bool> isReady() async {
    try {
      final result = await _channel.invokeMethod<bool>('isReady');
      return result ?? false;
    } on PlatformException catch (e) {
      print('❌ Erreur vérification terminal: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('❌ Erreur inattendue vérification: $e');
      return false;
    }
  }

  String _generateTransactionId() {
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    return 'TXN${timestamp}${(timestamp % 10000).toString().padLeft(4, '0')}';
  }
}

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

  factory PaymentResult.error(String message) {
    return PaymentResult._(
      success: false,
      errorMessage: message,
    );
  }

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
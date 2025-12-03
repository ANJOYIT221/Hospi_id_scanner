import 'package:flutter/services.dart';

class WriteRfidService {
  // Le nom du channel doit être le même côté Android
  static const MethodChannel _channel = MethodChannel('sunmi_rfid');

  /// Initialise et connecte le service RFID
  static Future<void> connect() async {
    try {
      await _channel.invokeMethod('connect');
      print('✅ RFID service connected');
    } catch (e) {
      print('❌ RFID connect error: $e');
      rethrow;
    }
  }

  /// Ecrit les données [epcData] sur la carte RFID
  /// [memBank] : 1=EPC, 2=TID, 3=USER
  /// [wordAdd] : adresse de début en mots, souvent 2 pour EPC
  /// [password] : mot de passe (4 octets) au format hexadécimal string, ex "00000000"
  static Future<void> writeTag({
    required String epcData,
    int memBank = 1,
    int wordAdd = 2,
    String password = '00000000',
  }) async {
    try {
      final args = {
        'password': password,
        'memBank': memBank,
        'wordAdd': wordAdd,
        'epcData': epcData,
      };
      await _channel.invokeMethod('writeTag', args);
      print('✅ RFID writeTag invoked');
    } catch (e) {
      print('❌ RFID writeTag error: $e');
      rethrow;
    }
  }

  /// Déconnecte proprement le service
  static Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
      print('✅ RFID service disconnected');
    } catch (e) {
      print('❌ RFID disconnect error: $e');
      rethrow;
    }
  }
}

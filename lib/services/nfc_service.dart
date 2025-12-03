import 'package:flutter/services.dart';

class NfcService {
  static const _channel = MethodChannel('com.hospi_id_scan.nfc');

  /// Lit le contenu textuel d’un tag NFC
  Future<String> readTag() async {
    try {
      final String content = await _channel.invokeMethod('readTag');
      return content;
    } catch (e) {
      return 'ERROR: $e';
    }
  }

  /// Écrit [text] sur un tag NFC
  Future<String> writeTag(String text) async {
    try {
      final String res = await _channel.invokeMethod('writeTag', {'text': text});
      return res;
    } catch (e) {
      return 'ERROR: $e';
    }
  }
}

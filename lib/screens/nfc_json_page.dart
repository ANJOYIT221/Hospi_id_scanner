import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RfidJsonPage extends StatefulWidget {
  @override
  _RfidJsonPageState createState() => _RfidJsonPageState();
}

class _RfidJsonPageState extends State<RfidJsonPage> {
  static const MethodChannel _ch = MethodChannel('com.hospi_id_scan.rfid');
  String _status = 'Prêt';

  Future<void> _openNfc() async {
    setState(() => _status = '→ NFC en cours…');
    try {
      final result = await _ch.invokeMethod<String>('openNfc');
      setState(() => _status = 'Résultat NFC: $result');
    } on PlatformException catch (e) {
      setState(() => _status = 'Erreur NFC: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text('RFID UHF JSON')),
    body: Center(
      child: ElevatedButton(
        onPressed: _openNfc,
        child: Text('Lire NFC/UHF'),
      ),
    ),
  );
}

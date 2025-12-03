import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';

class NfcJsonPage extends StatefulWidget {
  const NfcJsonPage({Key? key}) : super(key: key);

  @override
  State<NfcJsonPage> createState() => _NfcJsonPageState();
}

class _NfcJsonPageState extends State<NfcJsonPage> {
  String _status = 'Prêt';
  String _readResult = '';

  /// L’objet que l’on veut écrire (ici “hello world” -> on peut remplacer par n’importe quelle Map)
  final Map<String, dynamic> _myData = {
    'message': 'Hello World',
    'timestamp': DateTime.now().toIso8601String(),
  };

  @override
  void initState() {
    super.initState();
    // On s’assure que le plugin est initialisé
    NfcManager.instance.isAvailable().then((available) {
      if (!available) {
        setState(() => _status = 'NFC non disponible sur cet appareil');
      }
    });
  }

  /// 1) Écrire le JSON sur la carte, en formatant si nécessaire
  Future<void> _writeJson() async {
    final jsonString = jsonEncode(_myData);
    setState(() => _status = '→ Approchez la carte pour écrire…');

    try {
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            // Essayer NDEF natif
            final ndef = Ndef.from(tag);
            final msg = NdefMessage([ NdefRecord.createText(jsonString) ]);

            if (ndef != null && ndef.isWritable) {
              // Tag déjà NDEF et writable
              await ndef.write(msg);
              setState(() => _status = '✅ JSON écrit ! (NDEF)');
            } else {
              // Sinon, formater en NDEF puis écrire
              final formatable = NdefFormatable.from(tag);
              if (formatable != null) {
                await formatable.format(msg);
                setState(() => _status = '✅ Tag formaté et JSON écrit !');
              } else {
                throw Exception('Tag non-NDEF et non-formatable');
              }
            }
          } catch (e) {
            setState(() => _status = '❌ Erreur écriture: $e');
          } finally {
            await NfcManager.instance.stopSession();
          }
        },
      );
    } catch (e) {
      setState(() => _status = '❌ Session NFC interrompue: $e');
    }
  }

  /// 2) Relire le JSON depuis la carte
  Future<void> _readJson() async {
    setState(() {
      _status = '→ Approchez la carte pour lire…';
      _readResult = '';
    });
    try {
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            final ndef = Ndef.from(tag);
            if (ndef == null) throw Exception('Tag non-NDEF');

            final cached = await ndef.cachedMessage;
            if (cached == null || cached.records.isEmpty) {
              throw Exception('Aucun enregistrement NDEF');
            }

            final rec = cached.records.first;
            // les 3 premiers octets sont le préfixe de langue, on les saute
            final payload = rec.payload;
            final text = utf8.decode(payload.sublist(3));

            // formatte le JSON pour l’afficher joliment
            final pretty = const JsonEncoder.withIndent('  ')
                .convert(jsonDecode(text));

            setState(() {
              _readResult = pretty;
              _status = '✅ Lecture OK';
            });
          } catch (e) {
            setState(() => _status = '❌ Erreur lecture: $e');
          } finally {
            await NfcManager.instance.stopSession();
          }
        },
      );
    } catch (e) {
      setState(() => _status = '❌ Session NFC interrompue: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test NFC JSON')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              _status,
              style: TextStyle(
                fontSize: 16,
                color: _status.startsWith('❌')
                    ? Colors.red
                    : _status.startsWith('✅')
                    ? Colors.green
                    : Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _writeJson,
              child: const Text('Écrire JSON sur NFC'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _readJson,
              child: const Text('Lire JSON depuis NFC'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Contenu lu :',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _readResult,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

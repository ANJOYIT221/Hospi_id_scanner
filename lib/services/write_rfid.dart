import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class RfidWriter {
  HttpServer? _server;
  final String _host = '192.168.144.9';
  final int _port = 4000;

  /// Démarre le serveur WebSocket pour recevoir les données de réservation
  Future<void> start() async {
    try {
      _server = await HttpServer.bind(_host, _port);
      print('🔌 Serveur RFID Writer démarré sur ws://$_host:$_port');

      await for (HttpRequest request in _server!) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocket webSocket = await WebSocketTransformer.upgrade(request);
          _handleWebSocketConnection(webSocket);
        } else {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.close();
        }
      }
    } catch (e) {
      print('❌ Erreur démarrage serveur: $e');
    }
  }

  /// Gère les connexions WebSocket entrantes
  void _handleWebSocketConnection(WebSocket webSocket) {
    print('📱 Nouvelle connexion WebSocket');

    webSocket.listen(
          (data) async {
        try {
          final bookingData = jsonDecode(data);
          print('📨 Données reçues: $bookingData');

          // Simulation du processus de gravure
          await _processRfidWriting(webSocket, bookingData);

        } catch (e) {
          print('❌ Erreur traitement données: $e');
          _sendError(webSocket, 'Erreur format données: $e');
        }
      },
      onError: (error) {
        print('❌ Erreur WebSocket: $error');
      },
      onDone: () {
        print('🔌 Connexion WebSocket fermée');
      },
    );
  }

  /// Simule le processus de gravure RFID
  Future<void> _processRfidWriting(WebSocket webSocket, Map<String, dynamic> bookingData) async {
    try {
      print('🔄 Début gravure RFID...');

      // Validation des données
      if (!_validateBookingData(bookingData)) {
        _sendError(webSocket, 'Données de réservation invalides');
        return;
      }

      // Simulation de l'attente de la carte RFID
      print('⏳ Attente de la carte RFID...');
      await Future.delayed(Duration(seconds: 2));

      // Génération des données à graver
      final rfidData = _generateRfidData(bookingData);
      print('📝 Données RFID générées: ${rfidData.length} bytes');

      // Simulation de la gravure
      print('✍️ Gravure en cours...');
      await Future.delayed(Duration(seconds: 3));

      // Simulation de la vérification
      print('🔍 Vérification de la gravure...');
      await Future.delayed(Duration(seconds: 1));

      // Succès
      print('✅ Gravure terminée avec succès');
      _sendSuccess(webSocket, rfidData);

    } catch (e) {
      print('❌ Erreur gravure: $e');
      _sendError(webSocket, 'Erreur during gravure: $e');
    }
  }

  /// Valide les données de réservation
  bool _validateBookingData(Map<String, dynamic> data) {
    final requiredFields = ['surname', 'name', 'startDate', 'endDate', 'nights', 'roomType'];

    for (String field in requiredFields) {
      if (!data.containsKey(field) || data[field] == null || data[field].toString().isEmpty) {
        print('❌ Champ manquant ou vide: $field');
        return false;
      }
    }

    return true;
  }

  /// Génère les données à graver sur la carte RFID
  Uint8List _generateRfidData(Map<String, dynamic> bookingData) {
    // Structure des données RFID (exemple simplifié)
    final rfidInfo = {
      'cardId': _generateCardId(),
      'guestName': '${bookingData['surname']} ${bookingData['name']}',
      'roomType': bookingData['roomType'],
      'checkIn': bookingData['startDate'],
      'checkOut': bookingData['endDate'],
      'nights': bookingData['nights'],
      'accessLevel': _determineAccessLevel(bookingData['roomType']),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Conversion en bytes pour la gravure
    final jsonString = jsonEncode(rfidInfo);
    return Uint8List.fromList(utf8.encode(jsonString));
  }

  /// Génère un ID unique pour la carte
  String _generateCardId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'CARD${timestamp.toString().substring(8)}$random';
  }

  /// Détermine le niveau d'accès selon le type de chambre
  String _determineAccessLevel(String roomType) {
    switch (roomType.toLowerCase()) {
      case 'suite':
        return 'VIP';
      case 'deluxe':
        return 'PREMIUM';
      default:
        return 'STANDARD';
    }
  }

  /// Envoie un message de succès
  void _sendSuccess(WebSocket webSocket, Uint8List rfidData) {
    final response = {
      'status': 'ok',
      'message': 'Gravure terminée avec succès',
      'cardId': _extractCardId(rfidData),
      'dataSize': rfidData.length,
      'timestamp': DateTime.now().toIso8601String(),
    };

    webSocket.add(jsonEncode(response));
  }

  /// Envoie un message d'erreur
  void _sendError(WebSocket webSocket, String error) {
    final response = {
      'status': 'error',
      'message': error,
      'timestamp': DateTime.now().toIso8601String(),
    };

    webSocket.add(jsonEncode(response));
  }

  /// Extrait l'ID de la carte des données RFID
  String _extractCardId(Uint8List data) {
    try {
      final jsonString = utf8.decode(data);
      final decoded = jsonDecode(jsonString);
      return decoded['cardId'] ?? 'UNKNOWN';
    } catch (e) {
      return 'UNKNOWN';
    }
  }

  /// Arrête le serveur
  Future<void> stop() async {
    await _server?.close();
    print('🔌 Serveur RFID Writer arrêté');
  }
}

// Fonction principale pour démarrer le serveur
void main() async {
  final writer = RfidWriter();

  // Gestion de l'arrêt propre
  ProcessSignal.sigint.watch().listen((signal) async {
    print('\n🛑 Arrêt du serveur...');
    await writer.stop();
    exit(0);
  });

  // Démarrage du serveur
  await writer.start();
}
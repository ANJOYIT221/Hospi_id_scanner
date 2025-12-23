// lib/services/ocr_service.dart
// ✅ OPTIMISÉ : Fuzzy matching réduit, corrections d'accents gardées, OpenAI activé
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:mrz_parser/mrz_parser.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

const String kOpenAIHardcodedKey = "";

class OCRService {
  final bool useAiPostProcess;
  final String model;
  final String kOpenAIHardcodedKey = dotenv.env['OPENAI_API_KEY'] ?? '';

  static Set<String> _commonFrenchNames = {
    'MARIE', 'JEAN', 'PIERRE', 'MICHEL', 'ANDRÉ', 'PHILIPPE', 'ALAIN',
    'JACQUES', 'BERNARD', 'CHRISTIAN', 'DANIEL', 'PAUL', 'NICOLAS',
    'FRANÇOIS', 'FRÉDÉRIC', 'STÉPHANE', 'LAURENT', 'PATRICK', 'CHRISTOPHE',
    'JULIEN', 'DAVID', 'THOMAS', 'ALEXANDRE', 'OLIVIER', 'SYLVAIN',
    'SÉBASTIEN', 'ÉRIC', 'JÉRÔME', 'GÉRARD', 'CÉDRIC', 'PASCAL',
    'NATHALIE', 'ISABELLE', 'SYLVIE', 'CATHERINE', 'CHRISTINE', 'SOPHIE',
    'MARTINE', 'MONIQUE', 'FRANÇOISE', 'VALÉRIE', 'SANDRINE', 'VÉRONIQUE',
    'CÉLINE', 'AURÉLIE', 'ÉMILIE', 'CAROLINE', 'JULIE', 'STEPHANIE',
    'SÉVERINE', 'HÉLÈNE', 'DELPHINE', 'STÉPHANIE', 'BÉATRICE', 'BRIGITTE',
    'AGNÈS', 'MÉLANIE', 'ÉLISE', 'AMÉLIE', 'LÉA', 'ZOÉ', 'CHLOÉ',
    'JOSÉ', 'RENÉ', 'RAPHAËL', 'MICHAËL', 'JOËL', 'GAËL',
    'LOUNA', 'EMMA', 'JADE', 'LOUISE', 'ALICE', 'INÈS',
  };

  static bool _prenomsLoaded = false;

  static const Map<String, String> _encodingFixMap = {
    'ã©': 'é',
    'ã¨': 'è',
    'ãª': 'ê',
    'ã ': 'à',
    'ã§': 'ç',
    'ã´': 'ô',
    'ã®': 'î',
    'ã¯': 'ï',
    'ã¹': 'ù',
    'ã»': 'û',
    'ã¼': 'ü',
    'Ã©': 'é',
    'Ã¨': 'è',
    'Ãª': 'ê',
    'Ã ': 'à',
    'Ã§': 'ç',
    'Ã´': 'ô',
    'Ã®': 'î',
    'Ã¯': 'ï',
    'Ã¹': 'ù',
    'Ã»': 'û',
    'Ã¼': 'ü',
  };

  static const Map<String, String> _accentFixMap = {
    'ae': 'é',
    'ee': 'é',
    'e0': 'é',
    'é0': 'é',
    'e9': 'é',
    'ea': 'é',
    'eg': 'é',
    'e`': 'è',
    'è0': 'è',
    'e8': 'è',
    'e^': 'ê',
    'ê0': 'ê',
    'e6': 'ê',
    'a`': 'à',
    'à0': 'à',
    'ao': 'à',
    'a8': 'à',
    'a0': 'à',
    'c,': 'ç',
    'ç0': 'ç',
    'c0': 'ç',
    'co': 'ç',
    'c.': 'ç',
    'o^': 'ô',
    'ô0': 'ô',
    'o0': 'ô',
    'oo': 'ô',
    'o6': 'ô',
    'i^': 'î',
    'î0': 'î',
    'i0': 'î',
    'i6': 'î',
    'i:': 'ï',
    'ï0': 'ï',
    'i.': 'ï',
    'u`': 'ù',
    'ù0': 'ù',
    'u0': 'ù',
    'u8': 'ù',
    'u^': 'û',
    'û0': 'û',
    'u6': 'û',
    'u:': 'ü',
    'ü0': 'ü',
    'oe': 'œ',
    '0e': 'œ',
    'ée': 'ée',
    'éé': 'ée',
  };

  OCRService({
    this.useAiPostProcess = true,
    this.model = "gpt-4o-mini",
  }) {
    if (!_prenomsLoaded) {
      _loadPrenomsFromFile();
    }
  }

  static Future<void> _loadPrenomsFromFile() async {
    try {
      final String fileContent = await rootBundle.loadString('assets/prenoms.txt');
      final List<String> lines = fileContent.split('\n');

      for (final line in lines) {
        final trimmed = line.trim().toUpperCase();
        if (trimmed.isNotEmpty) {
          _commonFrenchNames.add(trimmed);
        }
      }

      _prenomsLoaded = true;
      print('✅ ${_commonFrenchNames.length} prénoms chargés depuis prenoms.txt');
    } catch (e) {
      print('⚠️ Impossible de charger prenoms.txt: $e');
    }
  }

  String _fixEncoding(String text) {
    String fixed = text;

    for (final entry in _encodingFixMap.entries) {
      if (fixed.contains(entry.key)) {
        fixed = fixed.replaceAll(entry.key, entry.value);
        print('🔧 Correction encodage: "${entry.key}" → "${entry.value}"');
      }
    }

    return fixed;
  }

  Future<Map<String, String>> scanTextFromImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final textRecognizer = GoogleMlKit.vision.textRecognizer();

    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      final fullText = recognizedText.text;
      print('🔍 ========== OCR BRUT ==========');
      print(fullText);
      print('=====================================');

      final encodingFixed = _fixEncoding(fullText);
      print('🔧 ========== ENCODAGE CORRIGÉ ==========');
      print(encodingFixed);
      print('=====================================');

      final correctedText = _correctCommonOcrErrors(encodingFixed);
      print('🔧 ========== OCR CORRIGÉ ==========');
      print(correctedText);
      print('=====================================');

      final mrzMap = _tryMRZ(correctedText);
      if (mrzMap.isNotEmpty) {
        print('📤 MRZ trouvée → $mrzMap');
        final base = _withDefaultsAndClean(mrzMap);
        return await _maybeAiRefine(correctedText, base);
      }

      final sejour = _extractFrenchResidencePermit(correctedText);
      if (sejour.isNotEmpty) {
        print('📤 Titre de séjour → $sejour');
        final base = _withDefaultsAndClean(sejour);
        return await _maybeAiRefine(correctedText, base);
      }

      final newCni = _extractNewFrenchID(correctedText);
      if (newCni.isNotEmpty) {
        print('📤 Nouvelle CNI → $newCni');
        final base = _withDefaultsAndClean(newCni);
        return await _maybeAiRefine(correctedText, base);
      }

      final classic = _extractDataFromText(correctedText);
      print('📤 Fallback labels → $classic');
      final base = _withDefaultsAndClean(classic);
      return await _maybeAiRefine(correctedText, base);
    } finally {
      await textRecognizer.close();
    }
  }

  String _correctCommonOcrErrors(String text) {
    final words = text.split(RegExp(r'\s+'));
    final correctedWords = <String>[];

    for (var word in words) {
      print('🔍 Analyse mot: "$word"');
      String correctedWord = _fixAccents(word);
      correctedWords.add(correctedWord);
    }

    return correctedWords.join(' ');
  }

  String _fixAccents(String word) {
    if (word.isEmpty || word.length < 3) {
      print('   ⏭️ Mot trop court, ignoré');
      return word;
    }

    String fixed = word.toLowerCase();
    String original = fixed;
    bool wasModified = false;

    for (final entry in _accentFixMap.entries) {
      if (fixed.contains(entry.key)) {
        fixed = fixed.replaceAll(entry.key, entry.value);
        wasModified = true;
      }
    }

    if (wasModified) {
      print('   🔧 Après correction accents: "$original" → "$fixed"');
    }

    final fixedUpper = fixed.toUpperCase();
    if (_commonFrenchNames.contains(fixedUpper)) {
      print('   ✅ Match exact trouvé: "$word" → "${_titleCase(fixed)}"');
      return _titleCase(fixed);
    }

    // ✅ OPTIMISATION : Fuzzy matching réduit
    if (wasModified || fixed.length >= 4) {
      final fuzzyMatch = _findClosestFrenchNameOptimized(fixed);
      if (fuzzyMatch != null) {
        return fuzzyMatch;
      }
    }

    if (wasModified) {
      print('   ⚠️ Aucun prénom trouvé, garde la correction: "${_titleCase(fixed)}"');
      return _titleCase(fixed);
    }

    print('   ⏭️ Aucune correction: "$word"');
    return word;
  }

  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
      }
      List<int> temp = v0;
      v0 = v1;
      v1 = temp;
    }

    return v0[s2.length];
  }

  // ✅ NOUVELLE MÉTHODE OPTIMISÉE : Fuzzy matching réduit
  String? _findClosestFrenchNameOptimized(String input) {
    if (input.length < 4) return null;

    final inputUpper = input.toUpperCase();

    // ✅ OPTIMISATION 1 : On cherche uniquement les noms qui ont une distance de 1
    const int MAX_DISTANCE = 1;

    // ✅ OPTIMISATION 2 : Similarité minimale augmentée à 80%
    const double MIN_SIMILARITY = 0.8;

    for (final name in _commonFrenchNames) {
      // ✅ OPTIMISATION 3 : Skip les noms trop différents en longueur
      final lengthDiff = (inputUpper.length - name.length).abs();
      if (lengthDiff > MAX_DISTANCE) continue;

      final distance = _levenshteinDistance(inputUpper, name);

      // ✅ OPTIMISATION 4 : Arrêt dès qu'on trouve un match valide
      if (distance == MAX_DISTANCE) {
        final similarity = _calculateSimilarity(inputUpper, name);
        if (similarity >= MIN_SIMILARITY) {
          print('   🔍 Fuzzy match trouvé: "$input" → "$name" (distance: $distance, similarité: ${(similarity * 100).toStringAsFixed(0)}%)');
          return _titleCase(name);
        }
      }
    }

    return null;
  }

  double _calculateSimilarity(String s1, String s2) {
    final longer = s1.length > s2.length ? s1 : s2;
    final shorter = s1.length > s2.length ? s2 : s1;

    if (longer.isEmpty) return 1.0;

    final distance = _levenshteinDistance(s1, s2);
    return (longer.length - distance) / longer.length;
  }

  Future<Map<String, String>> _maybeAiRefine(
      String ocr,
      Map<String, String> base,
      ) async {
    if (!useAiPostProcess || kOpenAIHardcodedKey.trim().isEmpty) {
      return _postProcessWithDictionary(base);
    }
    try {
      final refined = await _aiRefine(ocr, base);
      if (refined.isNotEmpty) return _postProcessWithDictionary(refined);
    } catch (e) {
      print('⚠️ AI refine error: $e');
    }
    return _postProcessWithDictionary(base);
  }

  Map<String, String> _postProcessWithDictionary(Map<String, String> data) {
    final result = Map<String, String>.from(data);

    print('🔍 ========== POST-TRAITEMENT ==========');

    final prenoms = result['prenoms'] ?? '';
    if (prenoms.isNotEmpty && prenoms != 'INCONNU') {
      print('📝 Prénoms avant: "$prenoms"');

      final encodingFixed = _fixEncoding(prenoms);
      print('🔧 Après correction encodage: "$encodingFixed"');

      final words = encodingFixed.split(RegExp(r'\s+'));
      final correctedWords = <String>[];

      for (final word in words) {
        final fixed = _fixAccents(word);
        correctedWords.add(fixed);
      }

      result['prenoms'] = correctedWords.join(' ');
      result['givenNames'] = correctedWords.join(' ');
      print('✅ Prénoms après: "${result['prenoms']}"');
    }

    final nom = result['nom'] ?? '';
    if (nom.isNotEmpty && nom != 'INCONNU') {
      print('📝 Nom avant: "$nom"');

      final encodingFixed = _fixEncoding(nom);
      print('🔧 Après correction encodage: "$encodingFixed"');

      final fixed = _fixAccents(encodingFixed);
      result['nom'] = fixed;
      result['nomUsage'] = fixed;
      print('✅ Nom après: "${result['nom']}"');
    }

    print('=========================================');
    return result;
  }

  Future<Map<String, String>> _aiRefine(
      String ocrText,
      Map<String, String> current,
      ) async {
    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');

    final system = '''
Tu es un expert en correction d'erreurs OCR sur des documents d'identité français.

⚠️ ERREURS OCR FRÉQUENTES À CORRIGER ABSOLUMENT :

ACCENTS É :
- "ae" → "é" (Saevine → Séverine)
- "ee" → "é" (Andree → André)
- "e0" → "é" (Jose0 → José)

ACCENTS È :
- "e\`" → "è" (Helene\` → Hélène)

CÉDILLE Ç :
- "c," → "ç" (Franc,ois → François)

ENCODAGE UTF-8 :
- "ã©" → "é" (Sã©verine → Séverine)
- "Ã©" → "é"

INSTRUCTIONS STRICTES :
1. Détecte et corrige UNIQUEMENT les erreurs OCR évidentes (accents manquants/mal reconnus)
2. NE CHANGE PAS un prénom s'il est déjà lisible et cohérent
3. PRÉSERVE TOUS LES ACCENTS français
4. Ne substitue JAMAIS un prénom par un autre complètement différent
5. Si un prénom est illisible, laisse-le tel quel plutôt que de deviner

PRÉNOMS FRANÇAIS COURANTS (pour référence) :
Marie, Jean, Pierre, Michel, André, Philippe, Jacques, Bernard, Paul, Nicolas, François,
Nathalie, Isabelle, Sophie, Christine, Caroline, Julie, Stéphanie, Séverine, Hélène,
Louna, Emma, Jade, Louise, Alice, Chloé, Inès

Retourne EXCLUSIVEMENT un JSON avec :
- nom (string, MAJUSCULES, accents corrigés)
- prenoms (string, Title Case avec accents corrigés)
- idNumber (string)
- nationalite (string, code ISO-3)
- birthDate (string, JJ/MM/AAAA ou vide)
- validUntil (string, JJ/MM/AAAA ou vide)
''';

    final user = '''
OCR brut :
"""
$ocrText
"""

Base JSON (NE CHANGE QUE LES ERREURS D'ACCENTS ÉVIDENTES) :
${jsonEncode(current)}

IMPORTANT : Ne remplace PAS un prénom par un autre ! Corrige seulement les accents mal lus !
''';

    final body = {
      "model": model,
      "temperature": 0,
      "response_format": {"type": "json_object"},
      "messages": [
        {"role": "system", "content": system},
        {"role": "user", "content": user}
      ]
    };

    final resp = await http.post(
      uri,
      headers: {
        "Authorization": "Bearer $kOpenAIHardcodedKey",
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('OpenAI error ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    final content = data["choices"]?[0]?["message"]?["content"];
    if (content is! String || content.trim().isEmpty) {
      print('⚠️ OpenAI empty content – fallback to base');
      return current;
    }

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      print('⚠️ OpenAI returned non-JSON – fallback to base');
      return current;
    }

    return {
      'nom': _cleanName((parsed['nom'] ?? current['nom'] ?? '').toString()),
      'prenoms': _cleanName((parsed['prenoms'] ?? current['prenoms'] ?? '').toString()),
      'idNumber': ((parsed['idNumber'] ?? current['idNumber'] ?? '').toString())
          .replaceAll(RegExp(r'\s'), ''),
      'nationalite': _cleanNat((parsed['nationalite'] ?? current['nationalite'] ?? '').toString()),
      'birthDate': _normDate((parsed['birthDate'] ?? current['birthDate'] ?? '').toString()),
      'validUntil': _normDate((parsed['validUntil'] ?? current['validUntil'] ?? '').toString()),
    };
  }

  Map<String, String> _tryMRZ(String text) {
    final rawLines = text.split('\n');
    final lines = <String>[];
    for (final l in rawLines) {
      if (l != null) {
        final t = l.trim();
        if (t.isNotEmpty) lines.add(t);
      }
    }

    final mrzLines = <String>[];
    for (final line in lines) {
      final cleaned = line.replaceAll(RegExp(r'[^A-Z0-9<]'), '');
      if (cleaned.length >= 30 &&
          (cleaned.startsWith('IDFRA') ||
              cleaned.startsWith('P<FRA') ||
              cleaned.startsWith('PSFRA') ||
              cleaned.startsWith('I<FRA'))) {
        mrzLines.add(cleaned);
      }
    }

    if (mrzLines.length < 2) {
      print('⚠️ MRZ incomplète (${mrzLines.length} lignes trouvées)');
      return {};
    }

    try {
      final result = MRZParser.parse(mrzLines.take(3).toList());
      if (result.documentNumber == null || result.surnames == null) {
        print('⚠️ MRZ parsing incomplet');
        return {};
      }
      return {
        'nom': (result.surnames ?? '').replaceAll('<', ' ').trim(),
        'nomUsage': (result.surnames ?? '').replaceAll('<', ' ').trim(),
        'prenoms': (result.givenNames ?? '').replaceAll('<', ' ').trim(),
        'givenNames': (result.givenNames ?? '').replaceAll('<', ' ').trim(),
        'idNumber': result.documentNumber ?? '',
        'nationalite': result.nationalityCountryCode ?? 'FRA',
      };
    } catch (e) {
      print('❌ Erreur parsing MRZ: $e');
      return {};
    }
  }

  Map<String, String> _extractFrenchResidencePermit(String raw) {
    final rawLines = raw.split('\n');
    final lines = <String>[];
    final uppers = <String>[];
    for (final l in rawLines) {
      if (l == null) continue;
      final t = l.trim();
      if (t.isEmpty) continue;
      lines.add(t);
      uppers.add(_uc(t));
    }

    bool looksLikeSejour = false;
    for (final u in uppers) {
      if (u.contains('TITRE DE S') || u.contains('TITRE DE SEJOUR') || u.contains('RESIDENCE PERMIT')) {
        looksLikeSejour = true;
        break;
      }
    }
    if (!looksLikeSejour) return {};

    String surname = '';
    String given = '';
    String id = '';
    String nat = '';
    String birth = '';
    String validUntil = '';

    int headerIdx = -1;
    for (int i = 0; i < uppers.length; i++) {
      final u = uppers[i];
      final hasNom = u.contains('NOM') || u.contains('NOMS') || u.contains('SURNAME');
      final hasPrenom = u.contains('PRENOM') || u.contains('PRÉNOM') || u.contains('FORENAME') || u.contains('GIVEN') || u.contains('FORSNAME') || u.contains('FORSNAMES');
      if (hasNom && hasPrenom) { headerIdx = i; break; }
    }

    if (headerIdx >= 0) {
      int i = headerIdx + 1;
      while (i < uppers.length && _isLabelLine(uppers[i])) i++;

      if (i < lines.length) {
        final maybeSurname = _cleanName(lines[i]);
        if (_looksLikeName(maybeSurname)) { surname = maybeSurname; i++; }
      }
      while (i < uppers.length && _isLabelLine(uppers[i])) i++;
      if (i < lines.length) {
        final maybeGiven = _cleanName(lines[i]);
        if (_looksLikeName(maybeGiven)) { given = maybeGiven; }
      }
    }

    if (surname.isEmpty) {
      for (int i = 0; i < uppers.length - 1; i++) {
        final u = uppers[i];
        if (u.contains('SURNAME') || u.contains('NOM')) {
          final cand = _cleanName(lines[i + 1]);
          if (_looksLikeName(cand)) { surname = cand; break; }
        }
      }
    }

    if (given.isEmpty) {
      for (int i = 0; i < uppers.length - 1; i++) {
        final u = uppers[i];
        if (u.contains('FORENAME') || u.contains('GIVEN') || u.contains('PRENOM') || u.contains('PRÉNOM')) {
          final cand = _cleanName(lines[i + 1]);
          if (_looksLikeName(cand)) { given = cand; break; }
        }
      }
    }

    for (int i = 0; i < uppers.length; i++) {
      final u = uppers[i];
      if (u.contains(' NAT')) {
        if (i + 1 < uppers.length) {
          final natLine = uppers[i + 1];
          final m = RegExp(r'\b([A-Z]{3})\b').firstMatch(natLine);
          if (m != null && m.group(1) != null) {
            final code = m.group(1)!;
            if (code != 'NOM') nat = code;
          }
          if (i + 2 < lines.length) {
            final d = _parseDate(lines[i + 2]);
            if (d != null) birth = d;
          }
        }
        break;
      }
    }

    for (int i = 0; i < uppers.length; i++) {
      final u = uppers[i];
      if (u.contains('PERSON') && u.contains('NUM')) {
        final same = RegExp(r'\b(\d{9,14})\b').firstMatch(u);
        if (same != null && same.group(1) != null) { id = same.group(1)!; break; }
        if (i + 1 < uppers.length) {
          final next = uppers[i + 1];
          final m = RegExp(r'\b(\d{9,14})\b').firstMatch(next);
          if (m != null && m.group(1) != null) { id = m.group(1)!; break; }
        }
      }
    }
    if (id.isEmpty) {
      final flat = _uc(raw).replaceAll(' ', '');
      final all = RegExp(r'\b\d{9,14}\b').allMatches(flat);
      int bestLen = 0;
      for (final m in all) {
        final s = m.group(0);
        if (s != null && s.length > bestLen) { bestLen = s.length; id = s; }
      }
    }

    for (int i = 0; i < uppers.length; i++) {
      final u = uppers[i];
      if (u.contains('RESIDENCE PERMIT') || u.contains('VALABLE')) {
        if (i + 1 < lines.length) {
          final d = _parseDate(lines[i + 1]);
          if (d != null) { validUntil = d; break; }
        }
      }
    }

    final hasAny = surname.isNotEmpty || given.isNotEmpty || id.isNotEmpty;
    if (!hasAny) return {};

    return {
      'nom': surname.isNotEmpty ? surname : 'INCONNU',
      'nomUsage': surname.isNotEmpty ? surname : 'INCONNU',
      'prenoms': given.isNotEmpty ? given : 'INCONNU',
      'givenNames': given.isNotEmpty ? given : 'INCONNU',
      'idNumber': id.isNotEmpty ? id : 'INCONNU',
      'nationalite': nat.isNotEmpty ? nat : 'Inconnue',
      'birthDate': birth,
      'validUntil': validUntil,
    };
  }

  Map<String, String> _extractNewFrenchID(String txt) {
    final tUpper = _uc(txt);
    String nom = '', prenoms = '', id = '', nat = '', nomUsage = '';

    final nomMatch = RegExp(
      "(?:\\bNOM(?:S)?\\b|\\bSURNAME(?:S)?\\b)\\s*[:\\-]\\s*([A-ZÀÂÄÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝŸ\\s\\-']{2,40})",
      caseSensitive: false,
    ).firstMatch(tUpper);
    if (nomMatch != null && nomMatch.group(1) != null) {
      nom = _cleanName(nomMatch.group(1)!);
    }

    final prenomMatch = RegExp(
      "(?:\\bPR[ÉE]NOM(?:S)?\\b|\\bGIVEN\\s+NAME(?:S)?\\b|\\bFORENAME(?:S)?\\b)\\s*[:\\-]\\s*([A-ZÀÂÄÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝŸ\\s\\-']{2,80})",
      caseSensitive: false,
    ).firstMatch(tUpper);
    if (prenomMatch != null && prenomMatch.group(1) != null) {
      prenoms = _cleanName(prenomMatch.group(1)!);
    }

    final idLabelMatch =
    RegExp(r'PERSON\w*\s+NUM\w*\s*[:\-]?\s*([0-9]{9,14})').firstMatch(tUpper);
    if (idLabelMatch != null && idLabelMatch.group(1) != null) {
      id = idLabelMatch.group(1)!.replaceAll(' ', '');
    } else {
      final numMatch =
      RegExp(r'\b([0-9]{10,14})\b').firstMatch(tUpper.replaceAll(' ', ''));
      if (numMatch != null && numMatch.group(1) != null) id = numMatch.group(1)!;
    }

    final natAnchor =
    RegExp(r'(NATIONALIT[ÉE]|NATIONALITY|NAT\.?)').firstMatch(tUpper);
    if (natAnchor != null) {
      final m = RegExp(r'\b([A-Z]{3})\b').firstMatch(tUpper.substring(natAnchor.start));
      if (m != null && m.group(1) != null && m.group(1) != 'NOM') nat = m.group(1)!;
    }

    final usageMatch = RegExp("NOM\\s+D['']?USAGE\\s*[:\\-]\\s*([A-ZÀÂÄÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝŸ\\s\\-']{2,40})")
        .firstMatch(tUpper);
    if (usageMatch != null && usageMatch.group(1) != null) {
      nomUsage = _cleanName(usageMatch.group(1)!);
    }

    if (nom.isNotEmpty || prenoms.isNotEmpty || id.isNotEmpty) {
      return {
        'nom': nom.isNotEmpty ? nom : 'INCONNU',
        'nomUsage': nomUsage.isNotEmpty ? nomUsage : (nom.isNotEmpty ? nom : 'INCONNU'),
        'prenoms': prenoms.isNotEmpty ? prenoms : 'INCONNU',
        'givenNames': prenoms.isNotEmpty ? prenoms : 'INCONNU',
        'idNumber': id.isNotEmpty ? id : 'INCONNU',
        'nationalite': nat.isNotEmpty ? nat : 'Inconnue',
      };
    }
    return {};
  }

  Map<String, String> _extractDataFromText(String txt) {
    final rawLines = txt.split('\n');
    final lines = <String>[];
    final uppers = <String>[];
    for (final l in rawLines) {
      if (l == null) continue;
      final t = l.trim();
      if (t.isEmpty) continue;
      lines.add(t);
      uppers.add(_uc(t));
    }

    String nom = '';
    String prenoms = '';
    String id = '';
    String nat = '';

    for (int i = 0; i < uppers.length; i++) {
      final u = uppers[i];

      if (nom.isEmpty && (u.contains('NOM') || u.contains('SURNAME'))) {
        final after = _valueAfterSeparator(lines[i]);
        if (after != null) {
          final c = _cleanName(after);
          if (_looksLikeName(c)) nom = c;
        }
        if (nom.isEmpty && i + 1 < lines.length && !_isLabelLine(uppers[i + 1])) {
          final c = _cleanName(lines[i + 1]);
          if (_looksLikeName(c)) nom = c;
        }
      }

      if (prenoms.isEmpty &&
          (u.contains('PRÉNOM') || u.contains('PRENOM') || u.contains('FORENAME') || u.contains('GIVEN'))) {
        final after = _valueAfterSeparator(lines[i]);
        if (after != null) {
          final c = _cleanName(after);
          if (_looksLikeName(c)) prenoms = c;
        }
        if (prenoms.isEmpty && i + 1 < lines.length && !_isLabelLine(uppers[i + 1])) {
          final c = _cleanName(lines[i + 1]);
          if (_looksLikeName(c)) prenoms = c;
        }
      }
    }

    final flat = _uc(txt).replaceAll(' ', '');
    final all = RegExp(r'\b\d{9,14}\b').allMatches(flat);
    int bestLen = 0;
    for (final m in all) {
      final s = m.group(0);
      if (s != null && s.length > bestLen) { bestLen = s.length; id = s; }
    }

    final natM = RegExp(r'\b([A-Z]{3})\b').allMatches(_uc(txt));
    for (final m in natM) {
      final cand = m.group(1);
      if (cand != null && cand != 'NOM') { nat = cand; break; }
    }

    return {
      'nom': nom.isNotEmpty ? nom : 'INCONNU',
      'nomUsage': nom.isNotEmpty ? nom : 'INCONNU',
      'prenoms': prenoms.isNotEmpty ? prenoms : 'INCONNU',
      'givenNames': prenoms.isNotEmpty ? prenoms : 'INCONNU',
      'idNumber': id.isNotEmpty ? id : 'INCONNU',
      'nationalite': nat.isNotEmpty ? nat : 'Inconnue',
    };
  }

  String _uc(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  bool _isLabelLine(String u) {
    return RegExp(
      r'(NOM|SURNAME|PR[ÉE]NOM|FORENAME|GIVEN|NATIONAL|NAT\.?|DATE|BIRTH|CAT|PERMIT|VALABLE|VALID|NUM|NUMBER|DOCUMENT|RESIDENCE)',
    ).hasMatch(u);
  }

  String _cleanName(String s) {
    var out = s.replaceAll(RegExp(r'[*•.,;:]+'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    out = out.replaceAll(
        RegExp(r'\b(NOM|SURNAME|PRENOM|PRÉNOM|FORENAME|GIVEN|NAME|NAMES)\b', caseSensitive: false),
        ''
    ).trim();

    if (out.isEmpty || RegExp(r'\d').hasMatch(out)) return 'INCONNU';

    final allUpper = out == out.toUpperCase();
    if (allUpper) return out;

    return _titleCase(out);
  }

  bool _looksLikeName(String s) {
    if (s.isEmpty) return false;
    if (RegExp(r'\d').hasMatch(s)) return false;
    final words = s.split(RegExp(r'\s+'));
    if (words.isEmpty) return false;
    for (final w in words) {
      if (w.length < 2) return false;
    }
    return true;
  }

  String _titleCase(String s) {
    final parts = s.split(RegExp(r'\s+'));
    final buf = <String>[];
    for (final w in parts) {
      if (w.isEmpty) continue;
      buf.add(w[0].toUpperCase() + w.substring(1).toLowerCase());
    }
    return buf.join(' ');
  }

  String? _valueAfterSeparator(String original) {
    final idx = original.indexOf(':');
    final dashIdx = original.indexOf('-');
    final cut = (idx >= 0) ? idx : (dashIdx >= 0 ? dashIdx : -1);
    if (cut < 0) return null;
    final tail = original.substring(cut + 1).trim();
    return tail.isEmpty ? null : tail;
  }

  String? _parseDate(String s) {
    final t = s.replaceAll(RegExp(r'[^0-9]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final parts = t.split(' ');
    if (parts.length >= 3) {
      final d = parts[0].padLeft(2, '0');
      final m = parts[1].padLeft(2, '0');
      final y = parts[2].length == 2 ? '20${parts[2]}' : parts[2];
      final dOk = RegExp(r'^\d{2}$').hasMatch(d);
      final mOk = RegExp(r'^\d{2}$').hasMatch(m);
      final yOk = RegExp(r'^\d{4}$').hasMatch(y);
      if (dOk && mOk && yOk) return '$d/$m/$y';
    }
    return null;
  }

  String _normDate(String s) {
    if (s.trim().isEmpty) return '';
    final t = s.trim();
    final m1 = RegExp(r'^(\d{2})[\/\-](\d{2})[\/\-](\d{4})$').firstMatch(t);
    if (m1 != null) return '${m1.group(1)}/${m1.group(2)}/${m1.group(3)}';
    final m2 = RegExp(r'^(\d{4})[\/\-](\d{2})[\/\-](\d{2})$').firstMatch(t);
    if (m2 != null) return '${m2.group(3)}/${m2.group(2)}/${m2.group(1)}';
    return t;
  }

  Map<String, String> _withDefaultsAndClean(Map<String, String> m) {
    final nom = _cleanName((m['nom'] ?? m['nomUsage'] ?? '').toString());
    final prenoms = _cleanName((m['prenoms'] ?? m['givenNames'] ?? '').toString());
    final id = ((m['idNumber'] ?? '').toString()).replaceAll(RegExp(r'\s'), '');
    final nat = _cleanNat((m['nationalite'] ?? '').toString());
    final birth = _normDate((m['birthDate'] ?? '').toString());
    final valid = _normDate((m['validUntil'] ?? '').toString());

    return {
      'nom': nom.isNotEmpty ? nom : 'INCONNU',
      'nomUsage': nom.isNotEmpty ? nom : 'INCONNU',
      'prenoms': prenoms.isNotEmpty ? prenoms : 'INCONNU',
      'givenNames': prenoms.isNotEmpty ? prenoms : 'INCONNU',
      'idNumber': id.isNotEmpty ? id : 'INCONNU',
      'nationalite': nat.isNotEmpty ? nat : 'Inconnue',
      'birthDate': birth,
      'validUntil': valid,
    };
  }

  String _cleanNat(String s) {
    final v = s.trim().toUpperCase();
    if (v.isEmpty) return 'Inconnue';
    const bad = {'NOM', 'PRENOM', 'PRENOMS', 'NAME', 'NAMES'};
    if (bad.contains(v)) return 'Inconnue';
    const map = {'FRA': 'FRA', 'FR': 'FRA', 'SEN': 'SEN'};
    return map[v] ?? v;
  }
}
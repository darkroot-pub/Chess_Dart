import '../../models/models.dart';
import '../stockfish_service/engine_service.dart';
import 'chess_game.dart';

/// Result of reading a pasted PGN: either a [record] ready for review, or a human-readable [error].
class PgnImportResult {
  final GameRecord? record;
  final String? error;
  final int gamesFound;
  const PgnImportResult.ok(GameRecord this.record, this.gamesFound) : error = null;
  const PgnImportResult.fail(String this.error, [this.gamesFound = 0]) : record = null;
}

/// Reads standard PGN text (headers, move numbers, comments, variations, NAGs, results) into a [GameRecord].
/// Only the main line is used. Every move is validated against the rules, so a broken PGN is reported, never guessed.
class PgnImport {
  static const maxChars = 200000;
  static const maxPlies = 600; // same bound the analysis uses

  static final _header = RegExp(r'\[\s*(\w+)\s+"((?:[^"\\]|\\.)*)"\s*\]');
  static final _result = RegExp(r'^(1-0|0-1|1/2-1/2|\*)$');

  static PgnImportResult parse(String raw, {String? userName}) {
    var text = raw.replaceAll('﻿', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) return const PgnImportResult.fail('Paste a PGN first.');
    if (text.length > maxChars) return const PgnImportResult.fail('This PGN is too large (limit 200,000 characters).');

    // several games pasted together: use the first one that has moves
    final parts = text.split(RegExp(r'\n\s*(?=\[Event\s)')).where((p) => p.trim().isNotEmpty).toList();
    final games = parts.isEmpty ? [text] : parts;
    PgnImportResult? firstError;
    for (final part in games) {
      final r = _parseOne(part);
      if (r.record != null) return PgnImportResult.ok(r.record!, games.length);
      firstError ??= r;
    }
    return PgnImportResult.fail(firstError?.error ?? 'No game found in this text.', games.length);
  }

  static PgnImportResult _parseOne(String text) {
    final headers = <String, String>{};
    for (final m in _header.allMatches(text)) {
      headers[m.group(1)!] = m.group(2)!.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    }
    var body = text.replaceAll(_header, ' ');
    body = body.replaceAll(RegExp(r'\{[^}]*\}'), ' ').replaceAll(RegExp(r';[^\n]*'), ' ');
    // remove (nested) variations
    var prev = '';
    while (prev != body) {
      prev = body;
      body = body.replaceAll(RegExp(r'\([^()]*\)'), ' ');
    }
    body = body.replaceAll(RegExp(r'\$\d+'), ' ');

    var startFen = ChessGame.startFen;
    final fenHeader = headers['FEN'];
    if (fenHeader != null && fenHeader.trim().isNotEmpty) {
      final f = fenHeader.trim();
      if (!EngineService.validFen(f)) return const PgnImportResult.fail('The FEN in this PGN header is not valid.');
      startFen = f;
    }

    final g = ChessGame.fromFen(startFen);
    final ucis = <String>[];
    String? endToken;
    for (var tok in body.split(RegExp(r'\s+'))) {
      if (tok.isEmpty) continue;
      if (_result.hasMatch(tok)) { endToken = tok; continue; }
      tok = tok.replaceFirst(RegExp(r'^\d+\.+'), ''); // "12." / "12..." / "1.e4"
      if (tok.isEmpty) continue;
      tok = tok.replaceAll(RegExp(r'[!?]+$'), '').replaceAll('0-0-0', 'O-O-O').replaceAll('0-0', 'O-O');
      if (tok.isEmpty || tok == '--') continue;
      if (ucis.length >= maxPlies) return const PgnImportResult.fail('This game is longer than 600 half-moves, which is the limit for analysis.');
      final want = tok.replaceAll(RegExp(r'[+#]+$'), '');
      Move? found;
      for (final m in g.legalMoves()) {
        if (g.san(m).replaceAll(RegExp(r'[+#]+$'), '') == want) { found = m; break; }
      }
      if (found == null) {
        final n = ucis.length;
        return PgnImportResult.fail('Move "$tok" (move ${n ~/ 2 + 1}${n.isEven ? '' : '...'}) is not legal in this position. Check the PGN.');
      }
      ucis.add(found.uci);
      g.play(found);
    }
    if (ucis.isEmpty) return const PgnImportResult.fail('No moves were found in this PGN.');

    var result = headers['Result'] ?? endToken ?? '*';
    if (!_result.hasMatch(result)) result = endToken ?? '*';
    final white = (headers['White'] ?? 'White').trim().isEmpty ? 'White' : headers['White']!.trim();
    final black = (headers['Black'] ?? 'Black').trim().isEmpty ? 'Black' : headers['Black']!.trim();

    var date = DateTime.now().toIso8601String();
    final d = RegExp(r'^(\d{4})\.(\d{2})\.(\d{2})$').firstMatch(headers['Date'] ?? '');
    if (d != null) date = '${d.group(1)}-${d.group(2)}-${d.group(3)}T00:00:00.000';

    final id = 'imp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    return PgnImportResult.ok(
      GameRecord(
        id: id, date: date, white: white, black: black, result: result,
        reason: headers['Termination'] ?? 'Imported PGN', mode: 'import',
        pgn: text.trim(), startFen: startFen, userColor: kWhite, ratingDelta: 0, ucis: ucis,
      ),
      1,
    );
  }
}

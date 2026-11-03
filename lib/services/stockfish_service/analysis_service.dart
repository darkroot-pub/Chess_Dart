import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../chess_service/chess_game.dart';
import 'engine_service.dart';

enum MoveClass { brilliant, great, best, excellent, good, book, inaccuracy, mistake, miss, blunder }

extension MoveClassX on MoveClass {
  String get label => const {
        MoveClass.brilliant: 'Brilliant', MoveClass.great: 'Great move', MoveClass.best: 'Best',
        MoveClass.excellent: 'Excellent', MoveClass.good: 'Good', MoveClass.book: 'Book',
        MoveClass.inaccuracy: 'Inaccuracy', MoveClass.mistake: 'Mistake', MoveClass.miss: 'Miss',
        MoveClass.blunder: 'Blunder',
      }[this]!;
  String get symbol => const {
        MoveClass.brilliant: '!!', MoveClass.great: '!', MoveClass.best: '★', MoveClass.excellent: '👍',
        MoveClass.good: '✓', MoveClass.book: '📖', MoveClass.inaccuracy: '?!', MoveClass.mistake: '?',
        MoveClass.miss: '✗', MoveClass.blunder: '??',
      }[this]!;
  Color get color => const {
        MoveClass.brilliant: Color(0xFF1BACA6), MoveClass.great: Color(0xFF5B8BB9), MoveClass.best: Color(0xFF16A34A),
        MoveClass.excellent: Color(0xFF65A30D), MoveClass.good: Color(0xFF8DA36B), MoveClass.book: Color(0xFFA88865),
        MoveClass.inaccuracy: Color(0xFFF2B01E), MoveClass.mistake: Color(0xFFE58F2A), MoveClass.miss: Color(0xFFDB7B7B),
        MoveClass.blunder: Color(0xFFEF4444),
      }[this]!;
}

class PlyAnalysis {
  final int ply; // 1-based
  final int mover;
  final String san, uci;
  final int evalBefore, evalAfter; // white cp
  final String? bestUci, bestSan;
  final MoveClass cls;
  final double winLoss;
  PlyAnalysis(this.ply, this.mover, this.san, this.uci, this.evalBefore, this.evalAfter, this.bestUci,
      this.bestSan, this.cls, this.winLoss);

  Map<String, dynamic> toJson() => {
        'p': ply, 'm': mover, 's': san, 'u': uci, 'eb': evalBefore, 'ea': evalAfter, 'bu': bestUci, 'bs': bestSan,
        'c': cls.name, 'w': winLoss,
      };
  static PlyAnalysis fromJson(Map<String, dynamic> j) => PlyAnalysis(
        j['p'] as int, j['m'] as int, j['s'] as String, j['u'] as String, j['eb'] as int, j['ea'] as int,
        j['bu'] as String?, j['bs'] as String?, MoveClass.values.firstWhere((c) => c.name == j['c']),
        (j['w'] as num).toDouble(),
      );
}

class GameAnalysis {
  final List<String> fens; // fens[0] start ... fens[n] final
  final List<int> evals; // white cp per position
  final List<PlyAnalysis> plies;
  final double accWhite, accBlack;
  final int depth; // search depth used (14 normal, 18 deep)
  GameAnalysis(this.fens, this.evals, this.plies, this.accWhite, this.accBlack, {this.depth = 14});

  Map<String, dynamic> toJson() => {
        'v': 2, 'fens': fens, 'evals': evals, 'plies': plies.map((e) => e.toJson()).toList(),
        'aw': accWhite, 'ab': accBlack, 'd': depth,
      };

  /// Returns null when the stored data is damaged or from an incompatible version (it is then simply recomputed).
  static GameAnalysis? tryFromJson(Map<String, dynamic> j) {
    try {
      if (j['v'] != 2) return null; // v1 results were classified by an older, less accurate method
      final fens = List<String>.from(j['fens'] as List);
      final evals = List<int>.from((j['evals'] as List).map((e) => (e as num).toInt()));
      final plies = (j['plies'] as List).map((e) => PlyAnalysis.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (fens.length != evals.length || plies.length != fens.length - 1) return null;
      return GameAnalysis(fens, evals, plies, (j['aw'] as num).toDouble(), (j['ab'] as num).toDouble(), depth: (j['d'] as num?)?.toInt() ?? 14);
    } catch (_) {
      return null;
    }
  }

  int count(int color, MoveClass c) => plies.where((p) => p.mover == color && p.cls == c).length;
  bool get hasBrilliant => plies.any((p) => p.cls == MoveClass.brilliant);
}

double winPct(int cp) => 50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1);

class AnalysisService {
  // Opening book: every position reached by one of the 3,865 named openings of the public-domain lichess
  // chess-openings list (assets/data/openings.txt holds 32-bit hashes of "placement turn castling").
  // A move is "book" when the position it leads to is in that set, so transpositions are recognised.
  static Set<int>? _bookSet;

  static int _hash(String s) {
    var h = 0x811C9DC5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static int _posHash(String fen) => _hash(fen.split(' ').take(3).join(' '));

  /// Exposed so a test can check that Dart and the generator of openings.txt hash positions identically.
  static int positionHashForTest(String fen) => _posHash(fen);

  static Future<Set<int>> _loadBook() async {
    final c = _bookSet;
    if (c != null) return c;
    try {
      final txt = await rootBundle.loadString('assets/data/openings.txt');
      _bookSet = {for (final l in txt.split('\n')) if (l.trim().isNotEmpty) int.parse(l.trim(), radix: 16)};
    } catch (_) {
      _bookSet = <int>{}; // no book: moves are then simply judged by the engine
    }
    return _bookSet!;
  }

  /// Piece sacrifice: a minor/major piece moves to a square where it can be taken for net material loss.
  static bool isSacrifice(ChessGame before, Move m) {
    final t = pieceType(m.piece);
    if (t == kP || t == kK) return false;
    final g = ChessGame.fromFen(before.fen);
    final us = g.turn;
    g.play(m);
    final movedVal = kPieceValue[t]!;
    final capVal = m.captured != 0 ? kPieceValue[pieceType(m.captured)]! : 0;
    var opp = g.attackerValues(m.to, 1 - us)..sort();
    final def = g.attackerValues(m.to, us);
    if (opp.isEmpty) return false;
    if (opp.first >= 100 && def.isNotEmpty) {
      opp = opp.where((v) => v < 100).toList();
      if (opp.isEmpty) return false;
    }
    final minAtt = opp.first;
    int netLoss;
    if (minAtt < movedVal) {
      netLoss = movedVal - minAtt;
    } else if (def.isEmpty) {
      netLoss = movedVal;
    } else {
      netLoss = 0;
    }
    return netLoss - capVal >= 2;
  }

  /// Analyse a game given its start FEN and UCI moves.
  static Future<GameAnalysis?> analyse(
    String startFen,
    List<String> ucis, {
    int movetimeMs = 3000,
    int depth = 14,
    void Function(double progress)? onProgress,
    void Function(int index, int whiteCp)? onPosition, // each position's evaluation as soon as it is known
    Future<void> Function()? gate, // awaited before every position (lets a game in progress pause the analysis)
    bool Function()? cancelled,
  }) async {
    final g = ChessGame.fromFen(startFen);
    final fens = <String>[g.fen];
    final sacs = <bool>[];
    final moves = <Move>[];
    final sans = <String>[];
    final beforeFens = <String>[];
    if (!EngineService.validFen(startFen) || ucis.length > 600) return null; // bad input / unbounded work
    for (final u in ucis) {
      final m = g.findUci(u);
      if (m == null) return null; // an illegal move in the record: refuse instead of analysing a truncated game
      beforeFens.add(g.fen);
      sacs.add(isSacrifice(g, m));
      sans.add(g.play(m));
      moves.add(m);
      fens.add(g.fen);
    }
    if (moves.isEmpty) return null;

    final evals = <int>[];
    final bestUcis = <String?>[];
    final seconds = <int?>[];
    final secondUcis = <String?>[];
    final legalCounts = <int>[];
    for (int i = 0; i < fens.length; i++) {
      if (cancelled != null && cancelled()) return null;
      if (gate != null) {
        await gate();
        if (cancelled != null && cancelled()) return null;
      }
      final pos = ChessGame.fromFen(fens[i]);
      final legal = pos.legalMoves();
      legalCounts.add(legal.length);
      if (legal.isEmpty) {
        evals.add(pos.inCheck ? (pos.turn == kWhite ? -10000 : 10000) : 0);
        bestUcis.add(null);
        seconds.add(null);
        secondUcis.add(null);
      } else {
        var lines = await EngineService.instance.analyse(fens[i], movetimeMs: movetimeMs, multiPv: 2, depth: depth);
        if (lines.isEmpty && !(cancelled != null && cancelled())) {
          // engine crashed / hung: restart it once and retry this position before giving up
          await EngineService.instance.restart();
          lines = await EngineService.instance.analyse(fens[i], movetimeMs: movetimeMs, multiPv: 2, depth: depth);
        }
        if (lines.isEmpty) return null; // never classify moves from missing or incomplete analysis
        evals.add(lines.first.whiteCp);
        bestUcis.add(lines.first.best);
        seconds.add(lines.length > 1 ? lines[1].whiteCp : null);
        secondUcis.add(lines.length > 1 ? lines[1].best : null);
      }
      onPosition?.call(i, evals.last);
      onProgress?.call((i + 1) / fens.length);
    }

    final book = await _loadBook();
    final plies = <PlyAnalysis>[];
    final losses = <double>[];
    final classes = <MoveClass>[];
    for (int i = 0; i < moves.length; i++) {
      final mover = pieceColor(moves[i].piece);
      int pov(int cp) => mover == kWhite ? cp : -cp;
      final wBefore = winPct(pov(evals[i]));
      final isBest = bestUcis[i] != null && bestUcis[i] == moves[i].uci;
      // If the played move is the engine's 2nd choice, its value comes from the SAME search as the best move
      // (apples to apples); otherwise from the search of the resulting position.
      final playedCp = (!isBest && secondUcis[i] == moves[i].uci && seconds[i] != null) ? seconds[i]! : evals[i + 1];
      final wAfter = winPct(pov(playedCp));
      // the engine's own best move never loses anything, whatever the next (independent) search says
      final loss = isBest ? 0.0 : max(0.0, wBefore - wAfter);
      // Quality classes follow chess.com's published structure (expected-points lost):
      //   Best = the engine's top move, Excellent < 2, Good < 5, Inaccuracy < 10, Mistake < 20, Blunder >= 20.
      //   Miss  = a mistake or worse right after the OPPONENT's mistake/blunder (you failed to punish it).
      final prevClass = i > 0 ? classes[i - 1] : null;
      final opponentErred = prevClass == MoveClass.mistake || prevClass == MoveClass.blunder;
      MoveClass cls;
      if (legalCounts[i] == 1) {
        cls = MoveClass.best; // forced move
      } else if (book.contains(_posHash(fens[i + 1])) && loss < 10) {
        cls = MoveClass.book;
      } else if (loss <= 2 && sacs[i] && wAfter >= 50 && wBefore < 92) {
        cls = MoveClass.brilliant;
      } else if (isBest && seconds[i] != null && wBefore - winPct(pov(seconds[i]!)) >= 15 && wBefore < 92) {
        cls = MoveClass.great;
      } else if (isBest) {
        cls = MoveClass.best;
      } else if (loss < 2) {
        cls = MoveClass.excellent;
      } else if (loss < 5) {
        cls = MoveClass.good;
      } else if (loss < 10) {
        cls = MoveClass.inaccuracy;
      } else if (opponentErred) {
        cls = MoveClass.miss;
      } else {
        cls = loss < 20 ? MoveClass.mistake : MoveClass.blunder;
      }
      classes.add(cls);
      losses.add(loss);
      String? bestSan;
      if (bestUcis[i] != null) {
        final p = ChessGame.fromFen(fens[i]);
        final bm = p.findUci(bestUcis[i]!);
        if (bm != null) bestSan = p.san(bm);
      }
      plies.add(PlyAnalysis(i + 1, mover, sans[i], moves[i].uci, evals[i], evals[i + 1], bestUcis[i], bestSan, cls, loss));
    }

    // Game accuracy, same method as lichess/chess.com-style review: each move's accuracy from the win% it lost,
    // then the average of (a) a mean weighted by how volatile the position was around that move and
    // (b) the harmonic mean, which punishes a few terrible moves harder than a plain average does.
    final List<double> wp = [for (final e in evals) winPct(e)]; // White's win% per position
    final int ws = (wp.length ~/ 10).clamp(2, 8).toInt();
    double sd(List<double> xs) {
      final m = xs.reduce((a, b) => a + b) / xs.length;
      return sqrt(xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / xs.length);
    }
    final windows = <List<double>>[
      for (int k = 0; k < ws - 2; k++) wp.sublist(0, min(ws, wp.length)),
      for (int k = 0; k + ws <= wp.length; k++) wp.sublist(k, k + ws),
    ];
    double weight(int i) => (windows.isEmpty ? 1.0 : sd(windows[min(i, windows.length - 1)])).clamp(0.5, 12.0).toDouble();
    double acc(int color) {
      double sw = 0, sx = 0, inv = 0;
      int n = 0;
      for (int i = 0; i < plies.length; i++) {
        if (plies[i].mover != color) continue;
        final double x = (103.1668 * exp(-0.04354 * losses[i]) - 3.1669).clamp(0.0, 100.0).toDouble();
        final w = weight(i);
        sw += w;
        sx += x * w;
        inv += 1 / max(x, 0.5).toDouble();
        n++;
      }
      if (n == 0) return 100;
      return ((sx / sw) + (n / inv)) / 2;
    }

    return GameAnalysis(fens, evals, plies, acc(kWhite), acc(kBlack), depth: depth);
  }
}
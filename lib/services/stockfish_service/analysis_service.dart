import 'dart:math';
import 'package:flutter/material.dart';
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
}

class GameAnalysis {
  final List<String> fens; // fens[0] start ... fens[n] final
  final List<int> evals; // white cp per position
  final List<PlyAnalysis> plies;
  final double accWhite, accBlack;
  GameAnalysis(this.fens, this.evals, this.plies, this.accWhite, this.accBlack);

  int count(int color, MoveClass c) => plies.where((p) => p.mover == color && p.cls == c).length;
  bool get hasBrilliant => plies.any((p) => p.cls == MoveClass.brilliant);
}

double winPct(int cp) => 50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1);

class AnalysisService {
  static const _book = [
    'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7', 'e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3', 'e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5 d5 exd5',
    'e4 e5 Nf3 Nc6 d4 exd4 Nxd4 Nf6 Nxc6 bxc6', 'e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4', 'e4 e5 f4 exf4 Nf3 g5',
    'e4 e5 Nc3 Nf6 f4 d5', 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6', 'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6',
    'e4 c5 Nf3 e6 d4 cxd4 Nxd4 a6', 'e4 c5 c3 d5 exd5 Qxd5 d4 Nf6', 'e4 e6 d4 d5 Nc3 Bb4 e5 c5',
    'e4 e6 d4 d5 Nd2 Nf6 e5 Nfd7', 'e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5', 'e4 c6 d4 d5 e5 Bf5 Nf3 e6',
    'e4 d5 exd5 Qxd5 Nc3 Qa5', 'e4 d6 d4 Nf6 Nc3 g6 f4 Bg7', 'e4 g6 d4 Bg7 Nc3 d6',
    'd4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O', 'd4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4', 'd4 d5 c4 dxc4 Nf3 Nf6 e3 e6',
    'd4 d5 Nf3 Nf6 Bf4 e6 e3 c5', 'd4 Nf6 c4 e6 Nc3 Bb4 e3 O-O Bd3 d5', 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O',
    'd4 Nf6 c4 e6 Nf3 b6 g3 Bb7', 'd4 Nf6 Bg5 Ne4 Bf4 c5', 'd4 f5 Nf3 Nf6 g3 e6', 'c4 e5 Nc3 Nf6 Nf3 Nc6 g3 d5',
    'c4 c5 Nf3 Nf6 Nc3 Nc6', 'c4 Nf6 Nc3 e6 e4', 'Nf3 d5 g3 Nf6 Bg2 e6 O-O Be7', 'Nf3 Nf6 c4 g6 Nc3 Bg7 e4 d6',
    'Nf3 d5 d4 Nf6 c4 e6 Nc3', 'g3 d5 Bg2 Nf6 Nf3', 'b3 e5 Bb2 Nc6 e3 d5', 'f4 d5 Nf3 Nf6 e3 g6',
  ];

  static bool isBook(List<String> sans, int upto) {
    final seq = sans.sublist(0, upto + 1).join(' ');
    return _book.any((l) => l == seq || l.startsWith('$seq '));
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
    int movetimeMs = 250,
    void Function(double progress)? onProgress,
    bool Function()? cancelled,
  }) async {
    final g = ChessGame.fromFen(startFen);
    final fens = <String>[g.fen];
    final sacs = <bool>[];
    final moves = <Move>[];
    final sans = <String>[];
    final beforeFens = <String>[];
    for (final u in ucis) {
      final m = g.findUci(u);
      if (m == null) break;
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
    final legalCounts = <int>[];
    for (int i = 0; i < fens.length; i++) {
      if (cancelled != null && cancelled()) return null;
      final pos = ChessGame.fromFen(fens[i]);
      final legal = pos.legalMoves();
      legalCounts.add(legal.length);
      if (legal.isEmpty) {
        evals.add(pos.inCheck ? (pos.turn == kWhite ? -10000 : 10000) : 0);
        bestUcis.add(null);
        seconds.add(null);
      } else {
        final lines = await EngineService.instance.analyse(fens[i], movetimeMs: movetimeMs, multiPv: 2);
        if (lines.isEmpty) return null; // engine unavailable
        evals.add(lines.first.whiteCp);
        bestUcis.add(lines.first.best);
        seconds.add(lines.length > 1 ? lines[1].whiteCp : null);
      }
      onProgress?.call((i + 1) / fens.length);
    }

    final plies = <PlyAnalysis>[];
    final losses = <double>[];
    final startsStandard = startFen == ChessGame.startFen;
    for (int i = 0; i < moves.length; i++) {
      final mover = pieceColor(moves[i].piece);
      int pov(int cp) => mover == kWhite ? cp : -cp;
      final wBefore = winPct(pov(evals[i]));
      final wAfter = winPct(pov(evals[i + 1]));
      final loss = max(0.0, wBefore - wAfter);
      final isBest = bestUcis[i] != null && bestUcis[i] == moves[i].uci;
      MoveClass cls;
      if (legalCounts[i] == 1) {
        cls = MoveClass.best;
      } else if (startsStandard && isBook(sans, i) && loss < 6) {
        cls = MoveClass.book;
      } else if (loss <= 2 && sacs[i] && wAfter >= 50 && wBefore < 92) {
        cls = MoveClass.brilliant;
      } else if (isBest &&
          seconds[i] != null &&
          wBefore - winPct(pov(seconds[i]!)) >= 15 &&
          wBefore < 92) {
        cls = MoveClass.great;
      } else if (isBest || loss < 0.3) {
        cls = MoveClass.best;
      } else if (loss < 2) {
        cls = MoveClass.excellent;
      } else if (loss < 5) {
        cls = MoveClass.good;
      } else if (loss < 10) {
        cls = MoveClass.inaccuracy;
      } else {
        final prevLoss = i > 0 ? losses[i - 1] : 0.0;
        if (prevLoss >= 10 && loss < 20) {
          cls = MoveClass.miss;
        } else {
          cls = loss < 20 ? MoveClass.mistake : MoveClass.blunder;
        }
      }
      losses.add(loss);
      String? bestSan;
      if (bestUcis[i] != null) {
        final p = ChessGame.fromFen(fens[i]);
        final bm = p.findUci(bestUcis[i]!);
        if (bm != null) bestSan = p.san(bm);
      }
      plies.add(PlyAnalysis(i + 1, mover, sans[i], moves[i].uci, evals[i], evals[i + 1], bestUcis[i], bestSan, cls, loss));
    }

    double acc(int color) {
      final xs = <double>[];
      for (int i = 0; i < plies.length; i++) {
        if (plies[i].mover == color) {
          xs.add((103.1668 * exp(-0.04354 * losses[i]) - 3.1669).clamp(0.0, 100.0));
        }
      }
      return xs.isEmpty ? 100 : xs.reduce((a, b) => a + b) / xs.length;
    }

    return GameAnalysis(fens, evals, plies, acc(kWhite), acc(kBlack));
  }
}

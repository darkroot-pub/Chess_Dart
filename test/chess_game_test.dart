// Run with: flutter test
// (Written for CI; NOT executed in the authoring sandbox because it has no Flutter/Dart SDK.)
import 'package:darkchess/services/chess_service/chess_game.dart';
import 'package:darkchess/services/stockfish_service/analysis_service.dart';
import 'package:darkchess/services/stockfish_service/engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

ChessGame play(List<String> ucis, [String? fen]) {
  final g = fen == null ? ChessGame() : ChessGame.fromFen(fen);
  for (final u in ucis) {
    final m = g.findUci(u);
    expect(m, isNotNull, reason: 'move $u should be legal');
    g.play(m!);
  }
  return g;
}

void main() {
  group('rules', () {
    test("fool's mate is checkmate, black wins", () {
      final g = play(['f2f3', 'e7e5', 'g2g4', 'd8h4']);
      expect(g.isCheckmate, isTrue);
      expect(g.result, GameResult.blackWins);
      expect(g.endReason, 'Checkmate');
    });

    test('stalemate is a draw', () {
      final g = ChessGame.fromFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(g.isStalemate, isTrue);
      expect(g.result, GameResult.draw);
    });

    test('castling is legal when allowed and illegal through check', () {
      final ok = ChessGame.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      expect(ok.findUci('e1g1'), isNotNull);
      expect(ok.findUci('e1c1'), isNotNull);
      final attacked = ChessGame.fromFen('r3k2r/8/8/8/8/8/5r2/R3K2R w KQkq - 0 1');
      expect(attacked.findUci('e1g1'), isNull, reason: 'f1 is attacked by the rook on f2');
    });

    test('castling rights are lost after the king moves', () {
      final g = play(['e1e2', 'e8e7', 'e2e1', 'e7e8'], 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      expect(g.findUci('e1g1'), isNull);
    });

    test('en passant capture is available only immediately', () {
      final g = ChessGame.fromFen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1');
      final ep = g.findUci('e5d6');
      expect(ep, isNotNull);
      g.play(ep!);
      expect(g.board[sqFromName('d5')], 0, reason: 'the captured pawn is removed');
    });

    test('promotion offers Q R B N', () {
      final g = ChessGame.fromFen('8/P6k/8/8/8/8/8/K7 w - - 0 1');
      final promos = g.legalMoves().where((m) => m.from == sqFromName('a7')).map((m) => m.uci).toSet();
      expect(promos, {'a7a8q', 'a7a8r', 'a7a8b', 'a7a8n'});
    });

    test('threefold repetition', () {
      final g = play(['g1f3', 'g8f6', 'f3g1', 'f6g8', 'g1f3', 'g8f6', 'f3g1', 'f6g8']);
      expect(g.threefold, isTrue);
      expect(g.result, GameResult.draw);
    });

    test('fifty-move rule and insufficient material', () {
      expect(ChessGame.fromFen('4k3/8/8/8/8/8/4P3/4K3 w - - 100 80').fiftyMove, isTrue);
      expect(ChessGame.fromFen('4k3/8/8/8/8/8/8/4K3 w - - 0 1').insufficientMaterial, isTrue);
      expect(ChessGame.fromFen('4k3/8/8/8/8/8/8/3QK3 w - - 0 1').insufficientMaterial, isFalse);
    });

    test('moving into check is rejected', () {
      final g = ChessGame.fromFen('4k3/8/8/8/8/8/3r4/4K3 w - - 0 1');
      expect(g.findUci('e1d2'), isNotNull, reason: 'capturing the undefended rook is legal');
      final h = ChessGame.fromFen('4k3/8/8/8/8/8/4r3/3K4 w - - 0 1');
      expect(h.findUci('d1e1'), isNull, reason: 'e1 is attacked by the rook on e2');
    });
  });

  group('pre-move preview', () {
    test('withTurn lets the side that is waiting preview its moves', () {
      final g = play(['e2e4']); // black to move
      final preview = g.withTurn(kWhite);
      expect(preview.turn, kWhite);
      expect(preview.legalMovesFrom(sqFromName('g1')).map((m) => m.uci), containsAll(['g1f3', 'g1h3']));
      expect(g.turn, kBlack, reason: 'the real game is untouched');
    });
  });

  group('FEN / PGN', () {
    test('round trip', () {
      const f = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2';
      expect(ChessGame.fromFen(f).fen, f);
    });

    test('garbage FEN falls back to the start position instead of crashing', () {
      expect(ChessGame().loadFen('not a fen'), isFalse);
      expect(ChessGame.fromFen('x/y/z').fen, ChessGame.startFen);
    });

    test('engine FEN guard rejects injection and malformed input', () {
      expect(EngineService.validFen(ChessGame.startFen), isTrue);
      expect(EngineService.validFen('${ChessGame.startFen}\nquit'), isFalse);
      expect(EngineService.validFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1'), isFalse);
      expect(EngineService.validFen(''), isFalse);
    });

    test('PGN contains the played moves and result', () {
      final g = play(['e2e4', 'e7e5']);
      final pgn = g.pgn(white: 'A', black: 'B', resultStr: '1-0');
      expect(pgn, contains('1. e4 e5'));
      expect(pgn, contains('1-0'));
    });
  });

  group('analysis guards (no engine required)', () {
    test('an illegal move in the record yields no analysis instead of a partial one', () async {
      expect(await AnalysisService.analyse(ChessGame.startFen, ['e2e4', 'e2e4']), isNull);
    });
    test('malformed start FEN yields no analysis', () async {
      expect(await AnalysisService.analyse('garbage', ['e2e4']), isNull);
    });
    test('oversized game is refused', () async {
      expect(await AnalysisService.analyse(ChessGame.startFen, List.filled(700, 'e2e4')), isNull);
    });
    test('win percentage is symmetric and bounded', () {
      expect(winPct(0), closeTo(50, 0.001));
      expect(winPct(500) + winPct(-500), closeTo(100, 0.001));
      expect(winPct(100000), lessThanOrEqualTo(100));
    });
  });
}

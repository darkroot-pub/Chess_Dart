import 'package:flutter_test/flutter_test.dart';
import 'package:darkchess/services/chess_service/chess_game.dart';
import 'package:darkchess/services/stockfish_service/analysis_service.dart';

void main() {
  test('analysis survives a JSON round trip and damaged data is rejected', () {
    final a = GameAnalysis(
      ['f0', 'f1'],
      [10, 35],
      [PlyAnalysis(1, 0, 'e4', 'e2e4', 10, 35, 'e2e4', 'e4', MoveClass.best, 0)],
      97.5,
      88.0,
      depth: 18,
    );
    final b = GameAnalysis.tryFromJson(a.toJson())!;
    expect(b.depth, 18);
    expect(b.plies.single.cls, MoveClass.best);
    expect(b.evals, [10, 35]);
    expect(GameAnalysis.tryFromJson({'v': 1}), isNull);
    expect(GameAnalysis.tryFromJson({'v': 2, 'fens': ['a'], 'evals': [1, 2], 'plies': [], 'aw': 1, 'ab': 1}), isNull);
  });

  test('position hash matches the one used to build assets/data/openings.txt', () {
    final g = ChessGame();
    for (final u in ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5', 'a7a6', 'b5a4', 'g8f6', 'e1g1']) {
      g.play(g.findUci(u)!);
    }
    expect(AnalysisService.positionHashForTest(g.fen).toRadixString(16), '9e7958de');
  });
}

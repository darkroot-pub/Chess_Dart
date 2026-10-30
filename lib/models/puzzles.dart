import 'package:flutter/foundation.dart';
import '../services/chess_service/chess_game.dart';

class Puzzle {
  final String id, title, category, difficulty, fen, explanation;
  final List<String> solution; // UCI: user, reply, user, ...
  final int points;
  final bool mate;
  const Puzzle(this.id, this.title, this.category, this.difficulty, this.points, this.fen, this.solution, this.explanation, {this.mate = true});

  /// Sanity-check at start-up: every stored line must be legal and (for mate puzzles) end in checkmate.
  bool get valid {
    final g = ChessGame.fromFen(fen);
    if (g.fen.split(' ').take(2).join(' ') != fen.split(' ').take(2).join(' ')) return false;
    for (final u in solution) {
      final m = g.findUci(u);
      if (m == null) return false;
      g.play(m);
    }
    return !mate || g.isCheckmate;
  }
}

const List<Puzzle> _all = [
  Puzzle('m1a', 'Back-rank mate', 'Mate in 1', 'Easy', 10, '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', ['a1a8'],
      'The black king is boxed in by its own pawns. Ra8 checks along the back rank and nothing can block or capture it.'),
  Puzzle('m1b', "Scholar's mate", 'Mate in 1', 'Easy', 10, 'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4', ['h5f7'],
      'Qxf7 is protected by the bishop on c4, so the king cannot take, and every escape square is covered or blocked.'),
  Puzzle('m1c', 'Smothered mate', 'Mate in 1', 'Easy', 10, '6rk/6pp/8/6N1/8/8/8/6K1 w - - 0 1', ['g5f7'],
      'Nf7 checks the king on h8. The king is smothered by its own rook and pawns, and knights cannot be blocked.'),
  Puzzle('m1d', 'Rook roller', 'Mate in 1', 'Easy', 10, 'k7/8/1R6/8/8/8/8/1R5K w - - 0 1', ['b1a1'],
      'The rook on b6 seals the b-file; Ra1 then checks on the a-file and the king has no flight squares.'),
  Puzzle('m1e', "Fool's mate", 'Mate in 1', 'Easy', 10, 'rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2', ['d8h4'],
      'White weakened the king with f3 and g4. Qh4 checks along the e1-h4 diagonal and cannot be blocked.'),
  Puzzle('m2a', 'Rook ladder', 'Mate in 2', 'Medium', 20, '7k/8/8/8/8/8/R7/1R4K1 w - - 0 1', ['b1b7', 'h8g8', 'a2a8'],
      '1.Rb7 takes the 7th rank so the king must go to g8 (the only legal move). 2.Ra8# finishes on the back rank.'),
  Puzzle('m2b', "Legal's mate", 'Mate in 2', 'Medium', 20, 'rn1qkbnr/ppp2p1p/3p2p1/4N3/2B1P3/2N5/PPPP1PPP/R1BbK2R w KQkq - 0 6', ['c4f7', 'e8e7', 'c3d5'],
      '1.Bxf7+ is protected by the knight on e5, so only Ke7 is possible. 2.Nd5# is mate: the king is hemmed in by Bf7, Ne5, Nd5 and its own pieces.'),
  Puzzle('m2c', 'Two rooks', 'Mate in 2', 'Medium', 20, '6k1/8/8/8/8/8/8/RR4K1 w - - 0 1', ['a1a7', 'g8f8', 'b1b8'],
      'Ra7 cuts off the 7th rank, then the second rook mates on the back rank whichever way the king steps.'),
  Puzzle('m2d', 'Queen and king', 'Mate in 2', 'Medium', 20, '8/8/8/k7/8/1QK5/8/8 w - - 0 1', ['b3b7', 'a5a4', 'b7a6'],
      'Qb7 builds a cage; after the king goes to a4, Qa6# is mate, supported by the king on c3 covering b4 and b3.'),
  Puzzle('m3a', 'Queen net', 'Mate in 3', 'Hard', 30, '8/8/1K6/3Q4/1k6/8/8/8 w - - 0 1', ['d5d3', 'b4a4', 'b6c5', 'a4a5', 'd3b5'],
      'Qd3 takes away the third rank and the d-file. The king and queen then drive the black king into a corner net and Qb5# finishes.'),
  Puzzle('b1', 'Knight fork', 'Find the best move', 'Medium', 15, '4k3/5q2/8/8/4N3/8/8/4K3 w - - 0 1', ['e4d6'],
      'Nd6+ forks the king and the queen. Black must save the king, then Nxf7 wins the queen.', mate: false),
  Puzzle('b2', 'Skewer', 'Find the best move', 'Medium', 15, '8/1q2k3/8/8/8/8/8/K6R w - - 0 1', ['h1h7'],
      'Rh7+ checks the king along the 7th rank. When the king steps aside, the rook captures the queen behind it.', mate: false),
  Puzzle('b3', 'Pinned queen', 'Find the best move', 'Easy', 10, '4k3/4q3/8/8/8/8/8/4R1K1 w - - 0 1', ['e1e7'],
      'The queen on e7 is pinned to its king by the rook. Rxe7+ wins the queen for the rook.', mate: false),
];

List<Puzzle>? _cache;
List<Puzzle> get kPuzzles => _cache ??= _all.where((p) {
      final ok = p.valid;
      if (!ok) debugPrint('Puzzle ${p.id} failed validation and was skipped');
      return ok;
    }).toList();

Puzzle dailyPuzzle() {
  final days = DateTime.now().difference(DateTime(2024)).inDays;
  final l = kPuzzles;
  return l[days % l.length];
}

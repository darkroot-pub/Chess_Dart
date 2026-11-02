import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/chess_service/chess_game.dart';
import '../../widgets/cards/common.dart';
import '../../widgets/cards/guardian_widgets.dart';
import '../../widgets/chessboard/chess_board.dart';

class LStep {
  final String text, fen;
  final String? focus, arrow; // focus: square whose legal moves are highlighted; arrow: "e2e4"
  const LStep(this.text, this.fen, {this.focus, this.arrow});
}

class Lesson {
  final String title, subtitle, tab;
  final int minutes;
  final IconData icon;
  final List<LStep> steps;
  const Lesson(this.tab, this.title, this.subtitle, this.minutes, this.icon, this.steps);
}

const _start = ChessGame.startFen;
const List<Lesson> kLessons = [
  Lesson('Basics', 'How the Pieces Move', 'Learn the rules', 6, Icons.extension, [
    LStep('Pawns move forward one square, or two from their starting square. They capture diagonally. The highlighted squares are where this pawn can go.', '7k/8/8/8/8/8/4P3/K7 w - - 0 1', focus: 'e2'),
    LStep('Knights jump in an L-shape: two squares one way and one square sideways. They are the only pieces that can jump over others.', '8/8/8/8/3N4/8/8/K6k w - - 0 1', focus: 'd4'),
    LStep('Bishops slide any distance diagonally and always stay on the same colour of square.', '8/8/8/8/3B4/8/8/K6k w - - 0 1', focus: 'd4'),
    LStep('Rooks slide any distance along ranks and files.', '8/8/8/8/3R4/8/8/K6k w - - 0 1', focus: 'd4'),
    LStep('The queen combines the rook and the bishop: the most powerful piece.', '8/8/8/8/3Q4/8/8/K6k w - - 0 1', focus: 'd4'),
    LStep('The king moves one square in any direction but can never move into check.', '8/8/8/8/3K4/8/8/7k w - - 0 1', focus: 'd4'),
  ]),
  Lesson('Basics', 'Chessboard Basics', 'Setup and notation', 4, Icons.grid_view, [
    LStep('The board has 64 squares. Files are the columns a to h, ranks are the rows 1 to 8. A square name is its file and rank, like e4. The bottom-right square for each player is light.', _start),
    LStep('Each side starts with 8 pawns, 2 rooks, 2 knights, 2 bishops, a queen and a king. The queen starts on her own colour: white queen on a light square d1, black queen on a dark square d8.', _start),
  ]),
  Lesson('Basics', 'Check and Checkmate', 'Win the game', 7, Icons.shield, [
    LStep('Check means the king is attacked. You must respond at once: move the king, block the attack, or capture the attacker.', '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', arrow: 'a1a8'),
    LStep('Checkmate means the king is in check and there is no legal way out. Here Ra8 is mate: the king is blocked by its own pawns. The game ends and the checking side wins.', '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', arrow: 'a1a8'),
    LStep('Stalemate is a draw: the side to move has no legal move but is NOT in check.', '7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'),
  ]),
  Lesson('Basics', 'Castling', 'King safety', 4, Icons.security, [
    LStep('Castling moves the king two squares towards a rook and the rook jumps to the other side. It needs: king and rook unmoved, empty squares between them, and the king not in check, passing through, or landing on an attacked square.', 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', focus: 'e1'),
  ]),
  Lesson('Basics', 'En Passant', 'A special pawn capture', 4, Icons.swap_horiz, [
    LStep('If an enemy pawn moves two squares and lands beside your pawn, you may capture it as if it had moved only one square, but only on the very next move. White can play exd6 here.', '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1', focus: 'e5'),
  ]),
  Lesson('Basics', 'Pawn Promotion', 'Turn pawns into queens', 3, Icons.upgrade, [
    LStep('A pawn reaching the last rank must become a queen, rook, bishop or knight. The queen is almost always best.', '8/P6k/8/8/8/8/8/K7 w - - 0 1', focus: 'a7'),
  ]),
  Lesson('Tactics', 'Forks', 'Attack two things at once', 8, Icons.call_split, [
    LStep('A fork attacks two or more pieces at once. Knights are great at it. Nd6+ attacks the king and the queen; Black can only save one.', '4k3/5q2/8/8/4N3/8/8/4K3 w - - 0 1', arrow: 'e4d6'),
  ]),
  Lesson('Tactics', 'Pins', 'Pieces that cannot move', 8, Icons.push_pin, [
    LStep('A pinned piece cannot move without exposing a more valuable piece behind it. The black queen is pinned to its king, so Rxe7+ wins it.', '4k3/4q3/8/8/8/8/8/4R1K1 w - - 0 1', arrow: 'e1e7'),
  ]),
  Lesson('Tactics', 'Skewers', 'The reverse pin', 8, Icons.straighten, [
    LStep('A skewer attacks a valuable piece that must move, exposing a piece behind it. Rh7+ forces the king aside, then the rook takes the queen.', '8/1q2k3/8/8/8/8/8/K6R w - - 0 1', arrow: 'h1h7'),
  ]),
  Lesson('Endgame', 'Endgame Basics', 'Convert your advantage', 6, Icons.flag, [
    LStep('In the endgame the king becomes a fighting piece: bring it to the centre. Two rooks can mate by taking ranks one after another (the ladder): Ra7 then Rb8#.', '6k1/8/8/8/8/8/8/RR4K1 w - - 0 1', arrow: 'a1a7'),
  ]),
  Lesson('Endgame', 'King and Pawn Endgames', 'Opposition and promotion', 6, Icons.keyboard_double_arrow_up, [
    LStep('Win by escorting the pawn with your king in front of it. The key idea is the opposition: kings face each other with one square between them, and the side NOT to move holds it.', '8/8/8/4k3/8/4K3/4P3/8 w - - 0 1'),
    LStep('If the attacking king reaches the square in front of the pawn on the 6th rank (or further), with the defender cannot stop it, the pawn promotes.', '8/8/4k3/8/4K3/4P3/8/8 w - - 0 1'),
  ]),
  Lesson('Strategy', 'Opening Principles', 'Start the game well', 5, Icons.rocket_launch, [
    LStep('1. Control the centre with pawns (e4, d4). 2. Develop knights and bishops quickly. 3. Castle early to protect your king. 4. Do not move the same piece twice without reason or bring the queen out too early.', _start),
  ]),
  Lesson('Strategy', 'Piece Values', 'What is worth what', 3, Icons.balance, [
    LStep('Pawn = 1, Knight = 3, Bishop = 3, Rook = 5, Queen = 9. Trade when ahead in material; keep pieces when behind. Two bishops are usually worth a little more than bishop plus knight.', _start),
  ]),
];

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});
  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  String tab = 'Basics';
  @override
  Widget build(BuildContext context) {
    final list = kLessons.where((l) => l.tab == tab).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final t in ['Basics', 'Tactics', 'Endgame', 'Strategy'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(t), selected: tab == t, onSelected: (_) => setState(() => tab = t), selectedColor: C.primary, showCheckmark: false, side: BorderSide.none, backgroundColor: C.softBlue, labelStyle: TextStyle(color: tab == t ? Colors.white : C.text, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          for (final l in list)
            AppCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonScreen(lesson: l))),
              child: Row(children: [
                IconBubble(l.icon),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${l.subtitle} · ${l.minutes} min', style: const TextStyle(color: C.text2, fontSize: 12.5)),
                ])),
                const Icon(Icons.chevron_right, color: C.text2),
              ]),
            ),
        ]),
      ),
    );
  }
}

class LessonScreen extends StatefulWidget {
  final Lesson lesson;
  const LessonScreen({super.key, required this.lesson});
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  int i = 0;
  static const _tips = ['Study the board first, then read the text.', 'Look at the highlighted squares and arrows.', 'Try to picture it before you move on.'];
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final st = widget.lesson.steps[i];
    final hl = <int>{};
    if (st.focus != null) {
      final g = ChessGame.fromFen(st.fen);
      hl.addAll(g.legalMovesFrom(sqFromName(st.focus!)).map((m) => m.to));
    }
    List<int>? arrow;
    if (st.arrow != null) arrow = [sqFromName(st.arrow!.substring(0, 2)), sqFromName(st.arrow!.substring(2, 4))];
    final n = widget.lesson.steps.length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.lesson.title)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: (i + 1) / n, minHeight: 6, backgroundColor: C.softBlue)),
          const SizedBox(height: 12),
          MiniBoard(st.fen, pieceSet: app.settings.pieceSet, theme: app.boardTheme, highlight: hl, arrow: arrow),
          const SizedBox(height: 16),
          Text('Step ${i + 1} of $n', style: const TextStyle(color: C.text2, fontSize: 12.5)),
          const SizedBox(height: 6),
          Text(st.text, style: const TextStyle(fontSize: 16, height: 1.45)),
          const SizedBox(height: 16),
          if (app.settings.guardianPuzzles) GuardianTalk(text: i == n - 1 ? 'Great work! Try the puzzles to practise this.' : _tips[i % _tips.length], seq: i),
          const SizedBox(height: 4),
          Row(children: [
            if (i > 0) Expanded(child: OutlinedButton(onPressed: () => setState(() => i--), child: const Text('Back'))),
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: ElevatedButton(onPressed: () => i < n - 1 ? setState(() => i++) : Navigator.pop(context), child: Text(i < n - 1 ? 'Next' : 'Finish'))),
          ]),
        ]),
      ),
    );
  }
}

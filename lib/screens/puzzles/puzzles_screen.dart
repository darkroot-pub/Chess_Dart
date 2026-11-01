import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/puzzles.dart';
import '../../providers/app_state.dart';
import '../../services/audio_service.dart';
import '../../services/chess_service/chess_game.dart';
import '../../services/stockfish_service/engine_service.dart';
import '../../widgets/cards/common.dart';
import '../../widgets/cards/ui_kit.dart';
import '../../widgets/chessboard/chess_board.dart';

class PuzzlesScreen extends StatefulWidget {
  final bool showBack;
  const PuzzlesScreen({super.key, this.showBack = true});
  @override
  State<PuzzlesScreen> createState() => _PuzzlesScreenState();
}

class _PuzzlesScreenState extends State<PuzzlesScreen> {
  String filter = 'All';
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = kPuzzles.where((p) => filter == 'All' || p.difficulty == filter).toList();
    final daily = dailyPuzzle();
    void open(Puzzle p) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PuzzleScreen(puzzle: p)));
    return Scaffold(
      appBar: AppBar(title: const Text('Puzzles'), automaticallyImplyLeading: widget.showBack, actions: [
        Center(child: Padding(padding: const EdgeInsets.only(right: 16), child: Row(children: [const Icon(Icons.star, color: C.warning, size: 18), const SizedBox(width: 4), Text('${app.stats.puzzlePoints}', style: const TextStyle(fontWeight: FontWeight.w800))]))),
      ]),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Reveal(
            child: BannerCard(
              image: 'assets/images/banner_puzzles.jpg',
              title: 'Daily Puzzle',
              subtitle: app.stats.solved.contains(daily.id) ? 'Completed today ✓ · ${daily.category}' : "${daily.category} · +${daily.points} points",
              height: 130,
              cta: app.stats.solved.contains(daily.id) ? 'Replay' : 'Solve',
              onTap: () => open(daily),
            ),
          ),
          Reveal(
            index: 1,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: cardDeco(radius: 18),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.insights, color: C.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('${app.stats.solved.length} of ${kPuzzles.length} solved', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${kPuzzles.isEmpty ? 0 : (app.stats.solved.length * 100 / kPuzzles.length).round()}%', style: const TextStyle(color: C.primary, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: kPuzzles.isEmpty ? 0 : app.stats.solved.length / kPuzzles.length),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 9, backgroundColor: C.softBlue, color: C.primary),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 8, children: [
            for (final f in ['All', 'Easy', 'Medium', 'Hard']) ChoicePill(f, filter == f, () => setState(() => filter = f)),
          ]),
          const SizedBox(height: 14),
          if (list.isEmpty) const EmptyState(icon: Icons.extension_off, title: 'No puzzles', message: 'No puzzles in this category.'),
          for (int i = 0; i < list.length; i++)
            Reveal(
              index: i + 2,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Pressable(
                  onTap: () => open(list[i]),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: cardDeco(radius: 20),
                    child: Row(children: [
                      ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 84, child: MiniBoard(list[i].fen, pieceSet: app.settings.pieceSet, theme: app.boardTheme))),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(list[i].category, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
                          const SizedBox(height: 3),
                          Text(list[i].title, style: const TextStyle(color: C.text2, fontSize: 12.5)),
                          const SizedBox(height: 8),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(color: _diffColor(list[i].difficulty).withAlpha(28), borderRadius: BorderRadius.circular(10)),
                              child: Text(list[i].difficulty, style: TextStyle(color: _diffColor(list[i].difficulty), fontWeight: FontWeight.w800, fontSize: 11.5)),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.star, color: C.warning, size: 15),
                            Text(' +${list[i].points}', style: const TextStyle(color: C.warning, fontWeight: FontWeight.w800, fontSize: 12.5)),
                          ]),
                        ]),
                      ),
                      app.stats.solved.contains(list[i].id)
                          ? const Icon(Icons.check_circle, color: C.success, size: 28)
                          : const Icon(Icons.play_circle_outline, color: C.primary, size: 28),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Color _diffColor(String d) => d == 'Easy' ? C.success : (d == 'Medium' ? C.warning : C.error);
}

class PuzzleScreen extends StatefulWidget {
  final Puzzle puzzle;
  const PuzzleScreen({super.key, required this.puzzle});
  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen> {
  late ChessGame g = ChessGame.fromFen(widget.puzzle.fen);
  late List<String> line = List.of(widget.puzzle.solution);
  late final int userColor = g.turn;
  int idx = 0, wrong = 0;
  int? selected;
  Set<int> targets = {};
  String msg = '';
  bool solved = false, busy = false, showSolution = false;
  List<int>? hint;

  Puzzle get p => widget.puzzle;

  void _tap(int sq) {
    if (solved || busy || showSolution) return;
    if (selected != null && targets.contains(sq)) {
      _move(selected!, sq);
      return;
    }
    final pc = g.board[sq];
    if (pc != 0 && pieceColor(pc) == g.turn) {
      selected = sq;
      targets = g.legalMovesFrom(sq).map((m) => m.to).toSet();
    } else {
      selected = null;
      targets = {};
    }
    setState(() {});
  }

  Future<void> _move(int from, int to) async {
    final m = g.findMove(from, to);
    if (m == null) {
      setState(() { selected = null; targets = {}; });
      return;
    }
    busy = true;
    hint = null;
    final remainingUserMoves = ((line.length - idx - 1) / 2).ceil();
    g.play(m);
    selected = null;
    targets = {};
    AudioService.instance.play(m.isCapture ? 'capture' : 'move');
    bool ok = idx < line.length && m.uci == line[idx];
    if (!ok && p.mate && g.isCheckmate) ok = true; // any mate is fine
    if (!ok && p.mate && EngineService.instance.available || (!ok && p.mate)) {
      // alternative forced mate? ask Stockfish
      final lines = await EngineService.instance.analyse(g.fen, movetimeMs: 500);
      if (!mounted) return;
      if (lines.isNotEmpty && lines.first.mate != null && lines.first.mate! < 0 && -lines.first.mate! <= remainingUserMoves) {
        ok = true;
        line = [...line.sublist(0, idx + 1), ...lines.first.pv];
      }
    }
    if (!ok) {
      g.undo();
      wrong++;
      busy = false;
      setState(() => msg = 'Not the best move. Try again!');
      AudioService.instance.play('notify');
      return;
    }
    idx++;
    final done = g.isCheckmate || idx >= line.length;
    if (done) {
      _solve();
      return;
    }
    setState(() => msg = 'Correct! Keep going…');
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final reply = g.findUci(line[idx]);
    if (reply == null) {
      _solve();
      return;
    }
    g.play(reply);
    idx++;
    AudioService.instance.play('move');
    busy = false;
    if (g.isCheckmate || idx >= line.length) {
      _solve();
    } else {
      setState(() => msg = 'Your move');
    }
  }

  void _solve() {
    solved = true;
    busy = false;
    final app = context.read<AppState>();
    final first = !app.stats.solved.contains(p.id);
    app.solvePuzzle(p.id, p.points);
    AudioService.instance.play('end');
    setState(() => msg = 'Solved!');
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.surface,
        title: Row(children: [const Icon(Icons.check_circle, color: C.success), const SizedBox(width: 8), Text(first ? '+${p.points} points' : 'Solved')]),
        content: Text(p.explanation),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
      ),
    );
  }

  void _hint() {
    if (solved || idx >= line.length) return;
    final m = g.findUci(line[idx]);
    if (m != null) setState(() => hint = [m.from, m.to]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final last = g.lastMove;
    return Scaffold(
      appBar: AppBar(title: Text(p.category)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(14), children: [
          Row(children: [
            Expanded(child: Text('${p.title} · ${p.difficulty}', style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(g.turn == kWhite ? 'White to move' : 'Black to move', style: const TextStyle(color: C.text2)),
          ]),
          const SizedBox(height: 10),
          ChessBoardView(
            pieces: g.board,
            pieceSet: s.pieceSet,
            theme: app.boardTheme,
            flipped: userColor == kBlack,
            coords: s.coords,
            selected: selected,
            targets: s.showLegal ? targets : const {},
            lastFrom: last?.from,
            lastTo: last?.to,
            checkSq: g.inCheck ? g.kingSquare(g.turn) : null,
            canDrag: (sq) => !solved && !busy && !showSolution && g.board[sq] != 0 && pieceColor(g.board[sq]) == g.turn,
            onTap: _tap,
            onDrop: (f, t) { if (f != t && !solved && !busy) _move(f, t); },
            arrow: hint,
          ),
          const SizedBox(height: 12),
          Text(showSolution ? p.explanation : (msg.isEmpty ? (p.mate ? 'Find the checkmate.' : 'Find the best move.') : msg), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: solved ? C.success : (msg.startsWith('Not') ? C.error : C.text)), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: solved ? null : _hint, icon: const Icon(Icons.lightbulb_outline), label: const Text('Hint'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: solved ? null : () => setState(() => showSolution = true), icon: const Icon(Icons.visibility_outlined), label: const Text('Solution'))),
          ]),
          if (solved || showSolution) ...[
            const SizedBox(height: 10),
            AppCard(child: Text('Solution: ${_solutionSan()}\n\n${p.explanation}', style: const TextStyle(height: 1.4))),
          ],
          if (solved)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ElevatedButton(
                onPressed: () {
                  final l = kPuzzles;
                  final i = l.indexWhere((x) => x.id == p.id);
                  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PuzzleScreen(puzzle: l[(i + 1) % l.length])));
                },
                child: const Text('Next puzzle'),
              ),
            ),
        ]),
      ),
    );
  }

  String _solutionSan() {
    final t = ChessGame.fromFen(p.fen);
    final out = <String>[];
    for (final u in p.solution) {
      final m = t.findUci(u);
      if (m == null) break;
      final no = t.fullmove, white = t.turn == kWhite;
      final san = t.play(m);
      out.add(white ? '$no. $san' : (out.isEmpty ? '$no... $san' : san));
    }
    return out.join(' ');
  }
}

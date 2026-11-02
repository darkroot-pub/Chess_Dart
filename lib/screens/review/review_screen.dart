import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../services/chess_service/chess_game.dart';
import '../../services/stockfish_service/analysis_service.dart';
import '../../services/stockfish_service/engine_service.dart';
import '../../widgets/cards/common.dart';
import '../../widgets/chessboard/chess_board.dart';

String fmtEval(int cp) {
  if (cp.abs() >= 9000) return '${cp > 0 ? '' : '-'}M${((10000 - cp.abs()) / 10).round()}';
  return '${cp > 0 ? '+' : ''}${(cp / 100).toStringAsFixed(1)}';
}

/// Chess.com-style game review: classifies every move (Brilliant ... Blunder) using Dark Chess AI.
class ReviewScreen extends StatefulWidget {
  final GameRecord record;
  const ReviewScreen({super.key, required this.record});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  GameAnalysis? an;
  double progress = 0;
  bool failed = false, running = false, cancelled = false, flipped = false;
  int ply = 0;

  @override
  void initState() {
    super.initState();
    flipped = widget.record.userColor == kBlack;
    _run(250);
  }

  @override
  void dispose() {
    cancelled = true;
    EngineService.instance.stop();
    super.dispose();
  }

  Future<void> _run(int ms) async {
    setState(() {
      running = true;
      failed = false;
      progress = 0;
    });
    final r = await AnalysisService.analyse(
      widget.record.startFen,
      widget.record.ucis,
      movetimeMs: ms,
      onProgress: (p) {
        if (mounted) setState(() => progress = p);
      },
      cancelled: () => cancelled,
    );
    if (!mounted) return;
    setState(() {
      running = false;
      an = r;
      failed = r == null;
      if (r != null) ply = r.plies.length;
    });
    if (r != null && r.plies.any((p) => p.cls == MoveClass.brilliant && p.mover == widget.record.userColor)) {
      context.read<AppState>().unlock('brilliant');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Review'),
        actions: [
          IconButton(icon: const Icon(Icons.copy_all_outlined), tooltip: 'Copy PGN', onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.record.pgn));
            snack(context, 'PGN copied');
          }),
        ],
      ),
      body: SafeArea(
        child: running
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.analytics_outlined, size: 54, color: C.primary),
                    const SizedBox(height: 14),
                    const Text('Dark Chess AI is reviewing your game…', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 14),
                    LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(8)),
                    const SizedBox(height: 8),
                    Text('${(progress * 100).round()}%', style: const TextStyle(color: C.text2)),
                  ]),
                ),
              )
            : (failed || an == null)
                ? EmptyState(
                    icon: Icons.memory,
                    title: 'Analysis unavailable',
                    message: widget.record.ucis.isEmpty ? 'This game has no moves to analyse.' : 'The Dark Chess AI engine could not start on this device.',
                    action: widget.record.ucis.isEmpty ? null : ElevatedButton(onPressed: () => _run(250), child: const Text('Try again')),
                  )
                : _body(an!, s, app),
      ),
    );
  }

  Widget _body(GameAnalysis a, AppSettings s, AppState app) {
    final g = ChessGame.fromFen(a.fens[ply]);
    PlyAnalysis? cur = ply > 0 ? a.plies[ply - 1] : null;
    int? lf, lt;
    if (cur != null) {
      lf = sqFromName(cur.uci.substring(0, 2));
      lt = sqFromName(cur.uci.substring(2, 4));
    }
    List<int>? arrow;
    if (cur != null && cur.bestUci != null && cur.bestUci != cur.uci && cur.winLoss >= 2) {
      arrow = [sqFromName(cur.bestUci!.substring(0, 2)), sqFromName(cur.bestUci!.substring(2, 4))];
    }
    final wPct = winPct(a.evals[ply]) / 100;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        Expanded(child: _acc('White', a.accWhite)),
        const SizedBox(width: 10),
        Expanded(child: _acc('Black', a.accBlack)),
      ]),
      const SizedBox(height: 10),
      ChessBoardView(
        pieces: g.board,
        pieceSet: s.pieceSet,
        theme: app.boardTheme,
        flipped: flipped,
        coords: s.coords,
        lastFrom: lf,
        lastTo: lt,
        checkSq: g.inCheck ? g.kingSquare(g.turn) : null,
        arrow: arrow,
        arrowColor: const Color(0xAA16A34A),
        badgeSq: lt,
        badgeText: cur?.cls.symbol == '👍' || cur?.cls.symbol == '📖' ? null : cur?.cls.symbol,
        badgeColor: cur?.cls.color ?? C.primary,
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 14,
          child: Row(children: [
            Expanded(flex: (wPct * 1000).round().clamp(1, 999), child: Container(color: Colors.white, alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 6), child: Text(fmtEval(a.evals[ply]), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)))),
            Expanded(flex: ((1 - wPct) * 1000).round().clamp(1, 999), child: Container(color: const Color(0xFF334155))),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      AppCard(
        child: cur == null
            ? const Text('Starting position', style: TextStyle(fontWeight: FontWeight.w700))
            : Row(children: [
                Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: cur.cls.color, shape: BoxShape.circle), child: Text(cur.cls.symbol, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${cur.san} is ${_phrase(cur.cls)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      (cur.bestSan != null && cur.bestUci != cur.uci && cur.winLoss >= 2)
                          ? 'Best was ${cur.bestSan}  ·  eval ${fmtEval(cur.evalAfter)}'
                          : 'Eval ${fmtEval(cur.evalAfter)}',
                      style: const TextStyle(color: C.text2, fontSize: 12.5),
                    ),
                  ]),
                ),
              ]),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        IconButton.filledTonal(onPressed: ply > 0 ? () => setState(() => ply = 0) : null, icon: const Icon(Icons.first_page)),
        IconButton.filledTonal(onPressed: ply > 0 ? () => setState(() => ply--) : null, icon: const Icon(Icons.chevron_left)),
        IconButton.filledTonal(onPressed: () => setState(() => flipped = !flipped), icon: const Icon(Icons.swap_vert)),
        IconButton.filledTonal(onPressed: ply < a.plies.length ? () => setState(() => ply++) : null, icon: const Icon(Icons.chevron_right)),
        IconButton.filledTonal(onPressed: ply < a.plies.length ? () => setState(() => ply = a.plies.length) : null, icon: const Icon(Icons.last_page)),
      ]),
      const SizedBox(height: 8),
      AppCard(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
        child: SizedBox(
          height: 90,
          child: LayoutBuilder(
            builder: (c, cs) => GestureDetector(
              onTapDown: (d) => setState(() => ply = (d.localPosition.dx / cs.maxWidth * a.plies.length).round().clamp(0, a.plies.length)),
              child: CustomPaint(size: Size(cs.maxWidth, 90), painter: _GraphPainter(a.evals, ply)),
            ),
          ),
        ),
      ),
      AppCard(
        child: Column(children: [
          const Row(children: [Expanded(child: Text('Move quality', style: TextStyle(fontWeight: FontWeight.w800))), SizedBox(width: 50, child: Text('White', textAlign: TextAlign.center, style: TextStyle(color: C.text2, fontSize: 12))), SizedBox(width: 50, child: Text('Black', textAlign: TextAlign.center, style: TextStyle(color: C.text2, fontSize: 12)))]),
          for (final c in MoveClass.values)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Container(width: 22, height: 22, alignment: Alignment.center, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle), child: Text(c.symbol, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))),
                const SizedBox(width: 10),
                Expanded(child: Text(c.label, style: TextStyle(color: c.color, fontWeight: FontWeight.w700))),
                SizedBox(width: 50, child: Text('${a.count(kWhite, c)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                SizedBox(width: 50, child: Text('${a.count(kBlack, c)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
            ),
        ]),
      ),
      AppCard(
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (int i = 0; i < a.plies.length; i++)
            InkWell(
              onTap: () => setState(() => ply = i + 1),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(color: ply == i + 1 ? C.primary : C.softBlue, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (i % 2 == 0) Text('${i ~/ 2 + 1}. ', style: TextStyle(color: ply == i + 1 ? Colors.white70 : C.text2, fontSize: 12)),
                  Text(a.plies[i].san, style: TextStyle(fontWeight: FontWeight.w700, color: ply == i + 1 ? Colors.white : C.text)),
                  const SizedBox(width: 4),
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: a.plies[i].cls.color, shape: BoxShape.circle)),
                ]),
              ),
            ),
        ]),
      ),
      OutlinedButton.icon(onPressed: () => _run(900), icon: const Icon(Icons.speed), label: const Text('Re-analyse deeper (slower)')),
    ]);
  }

  String _phrase(MoveClass c) => const {
        MoveClass.brilliant: 'a brilliant move', MoveClass.great: 'a great move', MoveClass.best: 'the best move',
        MoveClass.excellent: 'an excellent move', MoveClass.good: 'a good move', MoveClass.book: 'a book move',
        MoveClass.inaccuracy: 'an inaccuracy', MoveClass.mistake: 'a mistake', MoveClass.miss: 'a miss',
        MoveClass.blunder: 'a blunder',
      }[c]!;

  Widget _acc(String who, double v) => AppCard(
        child: Column(children: [
          Text(who, style: const TextStyle(color: C.text2, fontSize: 12)),
          Text('${v.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.primary)),
          const Text('Accuracy', style: TextStyle(color: C.text2, fontSize: 11)),
        ]),
      );
}

class _GraphPainter extends CustomPainter {
  final List<int> evals;
  final int cur;
  _GraphPainter(this.evals, this.cur);
  @override
  void paint(Canvas canvas, Size size) {
    final n = evals.length - 1;
    if (n < 1) return;
    final mid = size.height / 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF334155));
    Offset pt(int i) => Offset(i / n * size.width, size.height * (1 - winPct(evals[i]) / 100));
    final path = Path()..moveTo(0, size.height);
    for (int i = 0; i <= n; i++) {
      final p = pt(i);
      path.lineTo(p.dx, p.dy);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = const Color(0x66888888)..strokeWidth = 1);
    final x = cur / n * size.width;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()..color = C.primary..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _GraphPainter o) => o.cur != cur || o.evals != evals;
}

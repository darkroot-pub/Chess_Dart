import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../services/chess_service/chess_game.dart';
import '../../services/stockfish_service/analysis_jobs.dart';
import '../../services/stockfish_service/analysis_service.dart';
import '../../widgets/cards/analysis_waiting.dart';
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
  final jobs = AnalysisJobs.instance;
  GameAnalysis? an;
  AnalysisJob? job;
  bool flipped = false, _unlockChecked = false;
  int ply = 0;
  MoveClass? filter; // tapped quality row: Prev/Next jump between these moves
  bool showBest = false; // always draw the engine's best move

  @override
  void initState() {
    super.initState();
    flipped = widget.record.userColor == kBlack;
    jobs.attach(widget.record.id);
    jobs.addListener(_onJobs);
    job = jobs.startFor(widget.record); // reuses a stored result instantly, otherwise starts (or joins) a background job
    _sync();
  }

  @override
  void dispose() {
    // The analysis is NOT cancelled here: it keeps running in the background and notifies when it is done.
    jobs.removeListener(_onJobs);
    jobs.detach(widget.record.id);
    super.dispose();
  }

  void _onJobs() {
    if (!mounted) return;
    setState(_sync);
  }

  /// Pulls the newest state from the job. The previous result stays on screen while a deeper run is in progress.
  void _sync() {
    job = jobs.jobFor(widget.record.id) ?? job;
    final r = job?.result;
    if (r != null && !identical(r, an)) {
      final first = an == null;
      an = r;
      if (first || ply > r.plies.length) ply = r.plies.length;
    }
    if (an != null && !_unlockChecked) {
      _unlockChecked = true;
      if (an!.plies.any((p) => p.cls == MoveClass.brilliant && p.mover == widget.record.userColor)) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.read<AppState>().unlock('brilliant'); });
      }
    }
  }

  void _retry({bool deep = false}) {
    setState(() {
      job = jobs.startFor(widget.record, deep: deep, force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final j = job;
    Widget body;
    if (an != null) {
      body = _body(an!, s, app);
    } else if (j != null && j.active) {
      body = AnalysisWaiting(job: j, onBackground: () => Navigator.of(context).maybePop(), onStop: () { jobs.cancel(j.id); Navigator.of(context).maybePop(); });
    } else {
      body = EmptyState(
        icon: Icons.memory,
        title: j?.state == JobState.cancelled ? 'Analysis stopped' : 'Analysis unavailable',
        message: widget.record.ucis.isEmpty ? 'This game has no moves to analyse.' : (j?.error ?? 'The analysis was stopped before it finished.'),
        action: widget.record.ucis.isEmpty ? null : ElevatedButton(onPressed: _retry, child: const Text('Try again')),
      );
    }
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
      body: SafeArea(child: body),
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
    if (cur != null && cur.bestUci != null && cur.bestUci != cur.uci && (showBest || cur.winLoss >= 2)) {
      arrow = [sqFromName(cur.bestUci!.substring(0, 2)), sqFromName(cur.bestUci!.substring(2, 4))];
    }
    final wPct = winPct(a.evals[ply]) / 100;
    final running = job?.active ?? false;
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (running)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: job!.progress, minHeight: 6, borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 4),
            Text(job!.paused ? 'Deeper analysis paused while you play' : 'Deeper analysis ${(job!.progress * 100).round()}%. You can keep browsing; the better result replaces this one.', style: const TextStyle(color: C.text2, fontSize: 12)),
          ]),
        ),
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
      _keyMoments(a),
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
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: (a.count(kWhite, c) + a.count(kBlack, c)) == 0 ? null : () => _jumpClass(a, c),
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                decoration: BoxDecoration(color: filter == c ? c.color.withOpacity(0.14) : null, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Container(width: 22, height: 22, alignment: Alignment.center, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle), child: Text(c.symbol, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.label, style: TextStyle(color: c.color, fontWeight: FontWeight.w700))),
                  SizedBox(width: 50, child: Text('${a.count(kWhite, c)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                  SizedBox(width: 50, child: Text('${a.count(kBlack, c)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
              ),
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
                  _badge(a.plies[i].cls),
                ]),
              ),
            ),
        ]),
      ),
      OutlinedButton.icon(onPressed: (a.depth >= 18 || (job?.active ?? false)) ? null : () => _retry(deep: true), icon: const Icon(Icons.speed), label: Text(a.depth >= 18 ? 'Deep analysis (depth 18) done' : 'Re-analyse deeper (depth 18, slower)')),
    ]);
  }

  Widget _badge(MoveClass c) {
    final quiet = c == MoveClass.best || c == MoveClass.excellent || c == MoveClass.good || c == MoveClass.book;
    if (quiet) return Container(width: 8, height: 8, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle));
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(9)),
      child: Text(c.symbol, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }

  /// Moves of [c] in game order (both sides).
  List<int> _plysOf(GameAnalysis a, MoveClass c) => [for (int i = 0; i < a.plies.length; i++) if (a.plies[i].cls == c) i + 1];

  /// Tapping a quality row selects it and jumps to the next such move after the current one (wrapping around).
  void _jumpClass(GameAnalysis a, MoveClass c) {
    final xs = _plysOf(a, c);
    if (xs.isEmpty) return;
    setState(() {
      filter = c;
      ply = xs.firstWhere((p) => p > ply, orElse: () => xs.first);
    });
  }

  void _step(GameAnalysis a, int dir) {
    final c = filter;
    if (c == null) return;
    final xs = _plysOf(a, c);
    if (xs.isEmpty) return;
    setState(() {
      ply = dir > 0 ? xs.firstWhere((p) => p > ply, orElse: () => xs.first) : xs.lastWhere((p) => p < ply, orElse: () => xs.last);
    });
  }

  /// Chess.com-style shortcuts: one chip per important class (Brilliant, Great, Miss, Mistake, Blunder) with its count.
  Widget _keyMoments(GameAnalysis a) {
    const keys = [MoveClass.brilliant, MoveClass.great, MoveClass.blunder, MoveClass.mistake, MoveClass.miss, MoveClass.inaccuracy];
    final present = keys.where((c) => _plysOf(a, c).isNotEmpty).toList();
    if (present.isEmpty) return const SizedBox.shrink();
    final c = filter;
    final xs = c == null ? const <int>[] : _plysOf(a, c);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(children: [
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final k in present)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  selected: filter == k,
                  onSelected: (_) => _jumpClass(a, k),
                  avatar: CircleAvatar(backgroundColor: k.color, child: Text(k.symbol, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900))),
                  label: Text('${k.label} ${_plysOf(a, k).length}'),
                ),
              ),
          ]),
        ),
        if (c != null && xs.isNotEmpty)
          Row(children: [
            IconButton(onPressed: () => _step(a, -1), icon: const Icon(Icons.arrow_back_ios_new, size: 16)),
            Expanded(child: Text('${c.label}: ${xs.contains(ply) ? xs.indexOf(ply) + 1 : '–'} of ${xs.length}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: c.color))),
            IconButton(onPressed: () => _step(a, 1), icon: const Icon(Icons.arrow_forward_ios, size: 16)),
            IconButton(tooltip: 'Clear', onPressed: () => setState(() => filter = null), icon: const Icon(Icons.close, size: 16)),
          ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => showBest = !showBest),
            icon: Icon(showBest ? Icons.visibility : Icons.visibility_off_outlined, size: 18),
            label: Text(showBest ? 'Hide best-move arrow' : 'Show best-move arrow'),
          ),
        ),
      ]),
    );
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

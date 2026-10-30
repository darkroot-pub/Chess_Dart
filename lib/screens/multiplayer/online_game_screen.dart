import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/audio_service.dart';
import '../../services/chess_service/chess_game.dart';
import '../../services/multiplayer_service/supabase_service.dart';
import '../../widgets/cards/common.dart';
import '../../widgets/chessboard/chess_board.dart';

/// Live online game. Every move is sent to the `game-action` edge function, which validates it
/// with a real rules engine before updating the shared game row; clients only read via Realtime.
class OnlineGameScreen extends StatefulWidget {
  final String gameId;
  const OnlineGameScreen({super.key, required this.gameId});
  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  final sb = SupabaseService.instance;
  Map<String, dynamic>? game;
  final Map<String, String> names = {};
  RealtimeChannel? _ch;
  Timer? _tick, _poll;
  bool connected = false, busy = false, flipped = false;
  int? selected;
  Set<int> targets = {};
  String? error;
  int _lastMoves = -1;

  String get uid => sb.user!.id;
  int get myColor => game != null && game!['white_id'] == uid ? kWhite : kBlack;
  String get status => game?['status'] ?? 'waiting';
  List<String> get moves => List<String>.from(game?['moves'] ?? []);

  @override
  void initState() {
    super.initState();
    _load();
    _ch = sb.watchGame(widget.gameId, _apply, (c) { if (mounted) setState(() => connected = c); });
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) { if (mounted) { setState(() {}); _checkTimeout(); } });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    if (_ch != null) sb.client.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final g = await sb.fetchGame(widget.gameId);
      if (g != null && mounted) _apply(g);
    } catch (_) {
      if (mounted) setState(() => connected = false);
    }
  }

  Future<void> _apply(Map<String, dynamic> g) async {
    final first = game == null;
    setState(() => game = g);
    if (first) flipped = myColor == kBlack;
    final n = List.from(g['moves'] ?? []).length;
    if (_lastMoves >= 0 && n > _lastMoves) AudioService.instance.play('move');
    _lastMoves = n;
    for (final k in ['white_id', 'black_id']) {
      final id = g[k] as String?;
      if (id != null && !names.containsKey(id)) {
        try {
          final p = await sb.client.from('profiles').select('username,rating').eq('id', id).maybeSingle();
          if (p != null && mounted) setState(() => names[id] = '${p['username']}|${p['rating']}');
        } catch (_) {}
      }
    }
  }

  int _remaining(int color) {
    final g = game!;
    int ms = (color == kWhite ? g['white_ms'] : g['black_ms']) as int;
    if (status == 'active' && moves.isNotEmpty && (g['turn'] == (color == kWhite ? 'w' : 'b'))) {
      final since = DateTime.now().difference(DateTime.parse(g['last_move_at']).toLocal()).inMilliseconds;
      ms -= since;
    }
    return ms;
  }

  void _checkTimeout() {
    if (game == null || status != 'active' || moves.isEmpty || busy) return;
    if (_remaining(kWhite) < -500 || _remaining(kBlack) < -500) {
      busy = true;
      sb.action(widget.gameId, 'timeout').catchError((_) => <String, dynamic>{}).whenComplete(() { busy = false; _load(); });
    }
  }

  Future<void> _send(String action, {String? uci}) async {
    setState(() { busy = true; error = null; });
    try {
      final r = await sb.action(widget.gameId, action, uci: uci);
      if (r['game'] != null) _apply(Map<String, dynamic>.from(r['game']));
    } catch (e) {
      error = '$e';
      _load();
    }
    if (mounted) setState(() => busy = false);
  }

  ChessGame get cg => ChessGame.fromFen(game!['fen']);
  bool get myTurn => status == 'active' && game!['turn'] == (myColor == kWhite ? 'w' : 'b') && !busy;

  void _tap(int sq) {
    if (!myTurn) return;
    final g = cg;
    if (selected != null && targets.contains(sq)) {
      _move(g, selected!, sq);
      return;
    }
    final p = g.board[sq];
    if (p != 0 && pieceColor(p) == myColor) {
      selected = sq;
      targets = g.legalMovesFrom(sq).map((m) => m.to).toSet();
    } else {
      selected = null;
      targets = {};
    }
    setState(() {});
  }

  Future<void> _move(ChessGame g, int from, int to) async {
    int promo = kQ;
    if (g.needsPromotion(from, to) && !context.read<AppState>().settings.autoQueen) {
      final set = context.read<AppState>().settings.pieceSet;
      final c = await showDialog<int>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Promote to'),
          content: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (final t in [kQ, kR, kB, kN]) InkWell(onTap: () => Navigator.pop(d, t), child: PieceImage(makePiece(t, myColor), set, 48))]),
        ),
      );
      if (c == null) return;
      promo = c;
    }
    final m = g.findMove(from, to, promo: promo);
    selected = null;
    targets = {};
    if (m != null) _send('move', uci: m.uci);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    if (game == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final g = cg;
    final topColor = flipped ? kWhite : kBlack, botColor = 1 - topColor;
    String nameOf(int color) {
      final id = game![color == kWhite ? 'white_id' : 'black_id'] as String?;
      if (id == null) return 'Waiting…';
      return (names[id] ?? '…|').split('|').first;
    }
    String ratingOf(int color) {
      final id = game![color == kWhite ? 'white_id' : 'black_id'] as String?;
      final p = id == null ? null : names[id]?.split('|');
      return p != null && p.length > 1 ? '(${p[1]})' : '';
    }
    PlayerBar bar(int color) => PlayerBar(name: nameOf(color), sub: ratingOf(color), clockMs: _remaining(color), active: status == 'active' && game!['turn'] == (color == kWhite ? 'w' : 'b') && moves.isNotEmpty, captured: g.capturedBy(color), pieceSet: s.pieceSet);
    final last = moves.isEmpty ? null : g.findUci(moves.last);
    // the position is after the last move, so derive last-move squares from the uci string
    int? lf, lt;
    if (moves.isNotEmpty) {
      lf = sqFromName(moves.last.substring(0, 2));
      lt = sqFromName(moves.last.substring(2, 4));
    }
    final waiting = status == 'waiting';
    final drawOfferFromOpp = game!['draw_offer_by'] != null && game!['draw_offer_by'] != uid && status == 'active';
    return Scaffold(
      appBar: AppBar(
        title: Text(waiting ? 'Waiting for opponent' : 'Online Game'),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12), child: Icon(connected ? Icons.wifi : Icons.wifi_off, color: connected ? C.success : C.error, size: 20)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            bar(topColor),
            Stack(children: [
              ChessBoardView(
                pieces: g.board,
                pieceSet: s.pieceSet,
                theme: app.boardTheme,
                flipped: flipped,
                coords: s.coords,
                selected: selected,
                targets: s.showLegal ? targets : const {},
                lastFrom: lf,
                lastTo: lt,
                checkSq: g.inCheck ? g.kingSquare(g.turn) : null,
                canDrag: (sq) => myTurn && g.board[sq] != 0 && pieceColor(g.board[sq]) == myColor,
                onTap: _tap,
                onDrop: (f, t) { if (myTurn && f != t && g.legalMovesFrom(f).any((m) => m.to == t)) _move(g, f, t); },
              ),
              if (waiting)
                Positioned.fill(
                  child: Container(
                    color: const Color(0xCCFFFFFF),
                    alignment: Alignment.center,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text('Searching for an opponent…', style: TextStyle(fontWeight: FontWeight.w700)),
                      if (game!['code'] != null) ...[
                        const SizedBox(height: 10),
                        const Text('Room code', style: TextStyle(color: C.text2)),
                        InkWell(
                          onTap: () { Clipboard.setData(ClipboardData(text: game!['code'])); snack(context, 'Code copied'); },
                          child: Text(game!['code'], style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4, color: C.primary)),
                        ),
                      ],
                      TextButton(onPressed: () async { await sb.cancelGame(widget.gameId); if (mounted) Navigator.pop(context); }, child: const Text('Cancel')),
                    ]),
                  ),
                ),
            ]),
            bar(botColor),
            SizedBox(
              height: 34,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error ?? (status == 'finished' ? '${game!['result']} · ${game!['reason']}' : (!connected ? 'Reconnecting…' : (myTurn ? 'Your move' : (waiting ? '' : "Opponent's move")))),
                  style: TextStyle(color: error != null ? C.error : C.text2, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (drawOfferFromOpp)
              AppCard(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  const Expanded(child: Text('Opponent offers a draw', style: TextStyle(fontWeight: FontWeight.w700))),
                  TextButton(onPressed: () => _send('decline_draw'), child: const Text('Decline')),
                  FilledButton(onPressed: () => _send('accept_draw'), child: const Text('Accept')),
                ]),
              ),
            const Spacer(),
            Container(
              decoration: cardDeco(),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                TextButton.icon(onPressed: status == 'active' ? () => _send('resign') : null, icon: const Icon(Icons.flag_outlined), label: const Text('Resign')),
                TextButton.icon(onPressed: status == 'active' ? () => _send('offer_draw') : null, icon: const Icon(Icons.handshake_outlined), label: const Text('Draw')),
                TextButton.icon(onPressed: () => setState(() => flipped = !flipped), icon: const Icon(Icons.swap_vert), label: const Text('Flip')),
              ]),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}

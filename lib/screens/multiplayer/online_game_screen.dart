import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/audio_service.dart';
import '../../services/chess_service/chess_game.dart';
import '../../services/multiplayer_service/challenge_service.dart';
import '../../services/multiplayer_service/supabase_service.dart';
import '../../widgets/cards/common.dart';
import '../../widgets/chessboard/chess_board.dart';

/// Live online game. Every move is sent to the `game-action` edge function, which validates it
/// with a real rules engine before updating the shared game row; clients only read via Realtime.
/// Moves are shown instantly (optimistic) and rolled back if the server rejects them.
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
  final Map<String, String> avatars = {};
  RealtimeChannel? _ch;
  Timer? _tick, _poll;
  bool connected = false, busy = false, flipped = false;
  int? selected;
  Set<int> targets = {};
  String? error, notice;
  int _serverN = -1; // number of moves the server has confirmed
  String? pending; // my move shown optimistically, not yet confirmed
  bool _finishedSeen = false, _resultShown = false;
  String? _myRatingBefore, _ratingText;
  final _scroll = ScrollController();

  // replayed position (full history => SAN list + captured pieces)
  ChessGame? _g;
  String _gKey = '';
  int _pieces = 32;

  // local clock baseline: avoids errors when the phone's clock differs from the server's
  DateTime _stamp = DateTime.now();
  String _stampKey = '';

  String get uid => sb.user!.id;
  int get myColor => game != null && game!['white_id'] == uid ? kWhite : kBlack;
  String get status => game?['status'] ?? 'waiting';
  List<String> get moves => List<String>.from(game?['moves'] ?? []);
  List<String> get shown => pending == null ? moves : [...moves, pending!];
  String? get opponentId => game == null ? null : (myColor == kWhite ? game!['black_id'] : game!['white_id']) as String?;

  ChessGame get cg {
    final m = shown;
    final key = m.join(',');
    if (_g == null || key != _gKey) {
      final g = ChessGame.fromFen(ChessGame.startFen);
      for (final u in m) {
        final mv = g.findUci(u);
        if (mv == null) break;
        g.play(mv);
      }
      _g = g;
      _gKey = key;
    }
    return _g!;
  }

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
    _scroll.dispose();
    if (_ch != null) sb.client.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final g = await sb.fetchGame(widget.gameId);
      if (g != null && mounted) _apply(g);
      if (mounted && !connected) setState(() => connected = true);
    } catch (_) {
      if (mounted) setState(() => connected = false);
    }
  }

  Future<void> _apply(Map<String, dynamic> g) async {
    if (!mounted) return;
    final first = game == null;
    final n = List.from(g['moves'] ?? []).length;
    final key = '${g['last_move_at']}|$n|${g['status']}';
    // ignore stale rows (e.g. a slow poll arriving after a newer realtime update)
    if (!first && n < _serverN) return;
    if (key != _stampKey) {
      _stampKey = key;
      _stamp = DateTime.now();
    }
    final grew = _serverN >= 0 && n > _serverN;
    if (grew && pending != null) pending = null; // server confirmed (or opponent moved)
    setState(() => game = g);
    if (first) {
      flipped = myColor == kBlack;
      _pieces = cg.board.where((p) => p != 0).length;
    }
    _serverN = n;
    if (grew) _moveSound();
    if (selected != null && !myTurn) { selected = null; targets = {}; }
    _scrollMoves();

    final fin = g['status'] == 'finished';
    if (fin && !_finishedSeen) {
      final wasLive = !first;
      _finishedSeen = true;
      AudioService.instance.play('end');
      if (wasLive) _onFinished();
    }

    for (final k in ['white_id', 'black_id']) {
      final id = g[k] as String?;
      if (id != null && !names.containsKey(id)) {
        try {
          final p = await sb.client.from('profiles').select('username,rating,avatar_url').eq('id', id).maybeSingle();
          if (p != null && mounted) {
            setState(() {
              names[id] = '${p['username']}|${p['rating']}';
              if (p['avatar_url'] != null) avatars[id] = '${p['avatar_url']}';
            });
            if (id == uid) _myRatingBefore = '${p['rating']}';
          }
        } catch (_) {}
      }
    }
  }

  void _moveSound() {
    final g = cg;
    final count = g.board.where((p) => p != 0).length;
    final cap = count < _pieces;
    _pieces = count;
    AudioService.instance.play(g.inCheck ? 'check' : (cap ? 'capture' : 'move'));
  }

  void _scrollMoves() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _onFinished() async {
    // fetch the new rating to show the change
    try {
      await Future.delayed(const Duration(milliseconds: 800));
      final p = await sb.myProfile();
      final before = int.tryParse(_myRatingBefore ?? '');
      final now = p?['rating'] as int?;
      if (before != null && now != null && mounted) {
        final d = now - before;
        setState(() => _ratingText = 'Rating $before → $now (${d >= 0 ? '+' : ''}$d)');
        names[uid] = '${names[uid]?.split('|').first}|$now';
      }
    } catch (_) {}
    if (mounted && !_resultShown) {
      _resultShown = true;
      await showDialog(context: context, builder: (d) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(_resultTitle(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${game!['reason'] ?? ''}', style: const TextStyle(color: C.text2)),
          if (_ratingText != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_ratingText!, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close')),
          FilledButton(onPressed: () { Navigator.pop(d); _rematch(); }, child: const Text('Rematch')),
        ],
      ));
    }
  }

  String _resultTitle() {
    final r = game?['result'];
    if (r == '1/2-1/2') return 'Draw';
    final whiteWon = r == '1-0';
    return (whiteWon == (myColor == kWhite)) ? 'You won! 🎉' : 'You lost';
  }

  Future<void> _rematch() async {
    final o = opponentId;
    if (o == null || game == null) return;
    try {
      await ChallengeService.instance.send(o, game!['minutes'] as int, ((game!['inc_ms'] as int) ~/ 1000));
      if (mounted) snack(context, 'Rematch request sent');
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  int _remaining(int color) {
    final g = game!;
    int ms = (color == kWhite ? g['white_ms'] : g['black_ms']) as int;
    if (status == 'active' && moves.isNotEmpty && (g['turn'] == (color == kWhite ? 'w' : 'b'))) {
      ms -= DateTime.now().difference(_stamp).inMilliseconds;
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
      if (r['game'] != null) await _apply(Map<String, dynamic>.from(r['game']));
      if (action == 'offer_draw') notice = 'Draw offer sent';
      if (action != 'offer_draw') notice = null;
    } catch (e) {
      error = '$e';
      pending = null; // roll back the optimistic move
      await _load();
    }
    pending = null;
    if (mounted) setState(() => busy = false);
  }

  bool get myTurn => status == 'active' && cg.turn == myColor && pending == null && !busy;

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
      AudioService.instance.haptic();
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
    if (m == null) { setState(() {}); return; }
    // show the move immediately, confirm with the server in the background
    setState(() { pending = m.uci; error = null; notice = null; });
    _moveSound();
    _scrollMoves();
    _send('move', uci: m.uci);
  }

  Future<void> _confirm(String title, String msg, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Yes'))],
      ),
    );
    if (ok == true) _send(action);
  }

  Widget _movesCard(ChessGame g) {
    final san = g.sanList;
    if (san.isEmpty) {
      return Center(child: Text(status == 'active' ? 'Game started. White to move.' : '', style: const TextStyle(color: C.text2)));
    }
    return Container(
      width: double.infinity,
      decoration: cardDeco(),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        controller: _scroll,
        child: Wrap(spacing: 10, runSpacing: 6, children: [
          for (int i = 0; i < san.length; i++)
            RichText(text: TextSpan(style: const TextStyle(color: C.text, fontSize: 14), children: [
              if (i % 2 == 0) TextSpan(text: '${i ~/ 2 + 1}. ', style: const TextStyle(color: C.text2)),
              TextSpan(text: san[i], style: TextStyle(fontWeight: i == san.length - 1 ? FontWeight.w900 : FontWeight.w600, color: i == san.length - 1 ? C.primary : C.text)),
            ])),
        ]),
      ),
    );
  }

  Widget _resultCard() => Container(
        width: double.infinity,
        decoration: cardDeco(),
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_resultTitle(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('${game!['result']} · ${game!['reason']}', style: const TextStyle(color: C.text2)),
          if (_ratingText != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_ratingText!, style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back'))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(46)), onPressed: _rematch, child: const Text('Rematch'))),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    if (game == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final g = cg;
    final topColor = flipped ? kWhite : kBlack, botColor = 1 - topColor;
    String idOf(int color) => '${game![color == kWhite ? 'white_id' : 'black_id'] ?? ''}';
    String nameOf(int color) {
      final id = idOf(color);
      if (id.isEmpty) return 'Waiting…';
      return (names[id] ?? '…|').split('|').first;
    }
    String ratingOf(int color) {
      final p = names[idOf(color)]?.split('|');
      return p != null && p.length > 1 ? '(${p[1]})' : '';
    }
    final turnColor = g.turn;
    PlayerBar bar(int color) => PlayerBar(
          name: nameOf(color), sub: ratingOf(color), clockMs: _remaining(color), avatarUrl: avatars[idOf(color)],
          active: status == 'active' && turnColor == color && moves.isNotEmpty,
          captured: g.capturedBy(color), pieceSet: s.pieceSet,
        );
    int? lf, lt;
    final sh = shown;
    if (sh.isNotEmpty) {
      lf = sqFromName(sh.last.substring(0, 2));
      lt = sqFromName(sh.last.substring(2, 4));
    }
    final waiting = status == 'waiting';
    final finished = status == 'finished';
    final drawOfferFromOpp = game!['draw_offer_by'] != null && game!['draw_offer_by'] != uid && status == 'active';
    final drawSent = game!['draw_offer_by'] == uid && status == 'active';
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
              height: 30,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error ?? notice ?? (drawSent ? 'Draw offer sent' : (finished ? '${game!['result']} · ${game!['reason']}' : (!connected ? 'Reconnecting…' : (waiting ? '' : (cg.turn == myColor ? 'Your move' : "Opponent's move"))))),
                  style: TextStyle(color: error != null ? C.error : (myTurn ? C.primary : C.text2), fontWeight: FontWeight.w700),
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
            Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 8), child: finished ? _resultCard() : _movesCard(g))),
            Container(
              decoration: cardDeco(),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                TextButton.icon(onPressed: status == 'active' ? () => _confirm('Resign?', 'You will lose this game.', 'resign') : null, icon: const Icon(Icons.flag_outlined), label: const Text('Resign')),
                TextButton.icon(onPressed: status == 'active' && !drawSent ? () => _confirm('Offer a draw?', 'Your opponent can accept or decline.', 'offer_draw') : null, icon: const Icon(Icons.handshake_outlined), label: const Text('Draw')),
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

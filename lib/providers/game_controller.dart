import 'dart:async';
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import '../core/constants/constants.dart';
import '../models/models.dart';
import '../services/audio_service.dart';
import '../services/guardian_service.dart';
import '../services/lan_service.dart';
import '../services/chess_service/chess_game.dart';
import '../services/stockfish_service/analysis_jobs.dart';
import '../services/stockfish_service/engine_service.dart';
import 'app_state.dart';

typedef PromotionAsker = Future<int?> Function(int color);

class GameController extends ChangeNotifier {
  final AppState app;
  final String mode; // 'ai' | 'local' | 'lan' (a friend on the same hotspot / Wi-Fi)
  final LanLink? link; // only for 'lan'
  final String opponentName; // only for 'lan'
  final int humanColor;
  final int aiLevelIndex;
  final int tcIndex;
  late final AiLevel? level = mode == 'ai' ? kAiLevels[aiLevelIndex] : null;
  late final TimeControl tc = kTimeControls[tcIndex];
  final TimeControl? customTc;
  PromotionAsker? askPromotion;

  late ChessGame game;
  late int whiteMs, blackMs;
  bool paused = false, flipped = false, thinking = false, engineError = false, over = false;
  bool gameOverPending = false;
  int? selected;
  Set<int> targets = {};
  List<int>? hint;
  String? hintText;
  String? guardianText;
  int guardianSeq = 0;
  int _sinceTalk = 0;
  GameResult result = GameResult.ongoing;
  String endReason = '';
  GameRecord? record;
  final List<List<int>> _snaps = [];
  Timer? _timer;
  DateTime? _last;
  bool _disposed = false;
  bool _holding = false;

  void _releaseHold() {
    if (!_holding) return;
    _holding = false;
    AnalysisJobs.instance.release();
  }
  int _token = 0;

  TimeControl get timeControl => customTc ?? tc;

  GameController(this.app, {required this.mode, required this.humanColor, this.aiLevelIndex = 1, this.tcIndex = 5, this.customTc, SavedGame? resume, this.link, this.opponentName = 'Opponent'}) {
    game = ChessGame();
    whiteMs = blackMs = timeControl.baseMs;
    flipped = (mode == 'ai' || mode == 'lan') && humanColor == kBlack;
    if (resume != null) {
      game = ChessGame.fromFen(resume.startFen);
      for (final u in resume.ucis) {
        final m = game.findUci(u);
        if (m == null) break;
        _snaps.add([whiteMs, blackMs]);
        game.play(m);
      }
      whiteMs = resume.whiteMs;
      blackMs = resume.blackMs;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    AnalysisJobs.instance.hold(); // a background analysis pauses while a game is being played
    _holding = true;
    if (mode == 'ai') EngineService.instance.newGame();
    say(resume == null ? GEvent.greet : GEvent.tip);
    Future.microtask(_maybeAi);
    link?.attach(_onLan, onClose: _onLanClosed);
  }

  // ------------------------------------------------------------ hotspot / Wi-Fi game ('lan')
  bool get isLan => mode == 'lan';
  bool drawOfferIncoming = false; // the friend asked for a draw: the screen shows Accept / Decline
  bool drawOfferSent = false;
  String? lanNotice; // one-shot message for the screen (snack bar)

  void _lanSend(Map<String, dynamic> m) => link?.send(m);

  void _onLan(Map<String, dynamic> m) {
    if (_disposed) return;
    switch (m['t']) {
      case 'move':
        final u = m['u'], n = m['n'];
        if (over || u is! String || n is! int || game.turn == humanColor || n != game.plyCount + 1) return;
        final mv = game.findUci(u); // only a legal move of the side to move is accepted
        if (mv != null) _apply(mv);
        break;
      case 'end':
        final r = m['r'];
        if (over) return;
        _finish(r == '1-0' ? GameResult.whiteWins : (r == '0-1' ? GameResult.blackWins : GameResult.draw), m['why'] is String ? m['why'] as String : 'Game ended', remote: true);
        break;
      case 'drawOffer':
        if (!over) {
          drawOfferIncoming = true;
          notifyListeners();
        }
        break;
      case 'drawAccept':
        if (drawOfferSent && !over) _finish(GameResult.draw, 'Draw by agreement', remote: true);
        break;
      case 'drawDecline':
        if (drawOfferSent) {
          drawOfferSent = false;
          lanNotice = 'Your friend declined the draw';
          notifyListeners();
        }
        break;
    }
  }

  void _onLanClosed() {
    if (_disposed || over) return;
    _finish(GameResult.draw, 'Connection lost', remote: true);
  }

  void offerDrawLan() {
    if (over || drawOfferSent) return;
    drawOfferSent = true;
    _lanSend({'t': 'drawOffer'});
    lanNotice = 'Draw offer sent';
    notifyListeners();
  }

  void answerDrawLan(bool accept) {
    if (!drawOfferIncoming) return;
    drawOfferIncoming = false;
    if (accept) {
      _lanSend({'t': 'drawAccept'});
      _finish(GameResult.draw, 'Draw by agreement', remote: true);
    } else {
      _lanSend({'t': 'drawDecline'});
      notifyListeners();
    }
  }

  /// Guardian speaks (only vs AI, and only when enabled in settings).
  void say(GEvent e) {
    if (mode != 'ai' || !app.settings.guardianChat) return;
    guardianText = Guardian.say(e, trash: app.settings.guardianTaunts);
    guardianSeq++;
    _sinceTalk = 0;
  }

  /// Tap on the Guardian: a random tip or chat line.
  void chat() {
    say(_r.nextBool() ? GEvent.tip : GEvent.tap);
    notifyListeners();
  }

  static final _r = Random();

  // ------------------------------------------------------------ naming
  String get whiteName => mode == 'ai' ? (humanColor == kWhite ? app.stats.username : 'Dark Chess AI') : (isLan ? (humanColor == kWhite ? app.stats.username : opponentName) : 'Player 1');
  String get blackName => mode == 'ai' ? (humanColor == kBlack ? app.stats.username : 'Dark Chess AI') : (isLan ? (humanColor == kBlack ? app.stats.username : opponentName) : 'Player 2');
  String subFor(int color) {
    if (mode == 'ai') return color == humanColor ? '(${app.stats.rating})' : '(${level!.name} · ${level!.rating})';
    if (isLan) return color == humanColor ? 'You · ${color == kWhite ? 'White' : 'Black'}' : (color == kWhite ? 'White' : 'Black');
    return color == kWhite ? 'White' : 'Black';
  }

  bool get humanTurn => mode == 'local' || game.turn == humanColor;
  bool get canPlay => !over && !paused && !thinking && humanTurn;
  bool canDrag(int sq) =>
      (canPlay && game.board[sq] != 0 && pieceColor(game.board[sq]) == game.turn) ||
      (_canPremove && game.board[sq] != 0 && pieceColor(game.board[sq]) == humanColor);

  // ------------------------------------------------------------ pre-moves (vs AI): queue a move while the AI thinks
  List<int>? premove; // [from, to]
  bool get _canPremove => (mode == 'ai' || isLan) && app.settings.premoves && !over && !paused && game.turn != humanColor;

  void _premoveTap(int sq) {
    if (!_canPremove) return;
    if (selected != null && targets.contains(sq)) {
      _setPremove(selected!, sq);
      return;
    }
    final p = game.board[sq];
    if (p != 0 && pieceColor(p) == humanColor) {
      selected = sq;
      targets = game.withTurn(humanColor).legalMovesFrom(sq).map((m) => m.to).toSet();
      premove = null;
    } else {
      selected = null;
      targets = {};
      premove = null; // tapping elsewhere cancels the queued move
    }
    notifyListeners();
  }

  void _setPremove(int from, int to) {
    if (!game.withTurn(humanColor).legalMovesFrom(from).any((m) => m.to == to)) {
      selected = null;
      targets = {};
      notifyListeners();
      return;
    }
    premove = [from, to];
    selected = null;
    targets = {};
    AudioService.instance.haptic();
    notifyListeners();
  }

  void _runPremove() {
    if (_disposed || over || premove == null) return;
    final pm = premove!;
    premove = null;
    if (!canPlay) { notifyListeners(); return; }
    final m = game.findMove(pm[0], pm[1]); // promotion pre-moves always become a queen
    if (m == null) { notifyListeners(); return; }
    _apply(m);
  }

  // ------------------------------------------------------------ clock
  void _tick() {
    _maybeSlow();
    if (_disposed || over || paused || game.plyCount < 1 || timeControl.untimed) {
      _last = null;
      return;
    }
    final now = DateTime.now();
    final el = _last == null ? 100 : now.difference(_last!).inMilliseconds;
    _last = now;
    if (game.turn == kWhite) {
      whiteMs -= el;
    } else {
      blackMs -= el;
    }
    if (whiteMs <= 0 || blackMs <= 0) {
      final loser = whiteMs <= 0 ? kWhite : kBlack;
      if (loser == kWhite) whiteMs = 0; else blackMs = 0;
      _finish(loser == kWhite ? GameResult.blackWins : GameResult.whiteWins, 'Timeout');
      return;
    }
    // Only repaint when the visible clock text would change (1x/sec, or 10x/sec under 10s).
    final ms = game.turn == kWhite ? whiteMs : blackMs;
    final key = ms < 10000 ? ms ~/ 100 : -(ms ~/ 1000) - 1;
    if (key != _clockKey) {
      _clockKey = key;
      notifyListeners();
    }
  }

  int _clockKey = -1;

  // ------------------------------------------------------------ input
  void onTap(int sq) {
    if (!canPlay) { _premoveTap(sq); return; }
    if (selected != null && targets.contains(sq)) {
      _try(selected!, sq);
      return;
    }
    final p = game.board[sq];
    if (p != 0 && pieceColor(p) == game.turn) {
      selected = sq;
      targets = game.legalMovesFrom(sq).map((m) => m.to).toSet();
    } else {
      selected = null;
      targets = {};
    }
    notifyListeners();
  }

  void onDrop(int from, int to) {
    if (!canPlay) {
      if (from != to && _canPremove) _setPremove(from, to);
      return;
    }
    if (from == to) return;
    _try(from, to);
  }

  Future<void> _try(int from, int to) async {
    if (game.legalMovesFrom(from).where((m) => m.to == to).isEmpty) {
      selected = null;
      targets = {};
      notifyListeners();
      return;
    }
    int promo = kQ;
    if (game.needsPromotion(from, to) && !app.settings.autoQueen) {
      final c = await askPromotion?.call(game.turn);
      if (c == null) {
        selected = null;
        targets = {};
        notifyListeners();
        return;
      }
      promo = c;
    }
    final m = game.findMove(from, to, promo: promo);
    if (m != null) _apply(m);
  }

  void _apply(Move m) {
    final mover = game.turn;
    if (mover == humanColor) _balUserBefore = game.materialBalance() * (humanColor == kWhite ? 1 : -1); // for the "you hung it" taunt
    _snaps.add([whiteMs, blackMs]);
    game.play(m);
    if (isLan && mover == humanColor) _lanSend({'t': 'move', 'u': m.uci, 'n': game.plyCount}); // before any game-over handling
    if (!timeControl.untimed) {
      if (mover == kWhite) whiteMs += timeControl.incMs; else blackMs += timeControl.incMs;
    }
    selected = null;
    targets = {};
    hint = null;
    hintText = null;
    _last = DateTime.now();
    final r = game.result;
    if (r != GameResult.ongoing) {
      _finish(r, game.endReason);
      return;
    }
    AudioService.instance.play(game.inCheck ? 'check' : (m.isCapture ? 'capture' : 'move'));
    AudioService.instance.haptic();
    _react(mover, m);
    _autosave();
    notifyListeners();
    _maybeAi();
    if (mover != humanColor && premove != null) Future.delayed(const Duration(milliseconds: 180), _runPremove);
  }

  int _balUserBefore = 0; // material balance (human's point of view) just before the human's last move
  DateTime? _humanTurnSince; // when the human's turn began (drives the "are you asleep?" taunt)
  int _slowSaid = -1;

  void _maybeSlow() {
    final since = _humanTurnSince;
    if (mode != 'ai' || since == null || over || paused || !humanTurn || !app.settings.guardianChat || !app.settings.guardianTaunts) return;
    if (_slowSaid == game.plyCount || game.plyCount < 2) return;
    if (DateTime.now().difference(since).inSeconds >= 28) {
      _slowSaid = game.plyCount;
      say(GEvent.slow);
      notifyListeners();
    }
  }

  void _react(int mover, Move m) {
    if (mode != 'ai') return;
    _sinceTalk++;
    final mine = mover == humanColor;
    _humanTurnSince = mine ? null : DateTime.now();
    final balNow = game.materialBalance() * (humanColor == kWhite ? 1 : -1);
    if (m.captured != 0 && pieceType(m.captured) == kQ) {
      say(mine ? GEvent.aiQueenLost : GEvent.userQueenLost);
    } else if (!mine && m.isCapture && _balUserBefore - balNow >= 3) {
      say(GEvent.userBlunder); // the human's last move lost at least a minor piece
    } else if (game.inCheck) {
      say(mine ? GEvent.userCheck : GEvent.aiCheck);
    } else if (m.isCapture) {
      say(mine ? GEvent.userCapture : GEvent.aiCapture);
    } else if (mine && m.promo != 0) {
      say(GEvent.promote);
    } else if (mine && (m.castleK || m.castleQ)) {
      say(GEvent.castle);
    } else if (_sinceTalk >= (app.settings.guardianTaunts ? 4 : 6)) {
      final bal = game.materialBalance() * (humanColor == kWhite ? 1 : -1);
      say(bal >= 3 ? GEvent.winning : (bal <= -3 ? GEvent.losing : GEvent.userMove));
    }
  }

  void _autosave() {
    if (isLan) return; // a game against a friend cannot be resumed later
    app.setSaved(SavedGame(
      startFen: game.initialFen, mode: mode, ucis: game.moveStack.map((m) => m.uci).toList(),
      whiteMs: whiteMs, blackMs: blackMs, userColor: humanColor, aiLevel: aiLevelIndex, tcIndex: tcIndex,
    ));
  }

  // ------------------------------------------------------------ AI
  Future<void> _maybeAi() async {
    if (_disposed || mode != 'ai' || over || game.turn == humanColor || thinking) return;
    thinking = true;
    engineError = false;
    notifyListeners();
    final token = ++_token;
    final plies = game.plyCount;
    final t0 = DateTime.now();
    String? uci;
    try {
      uci = await EngineService.instance.bestMove(game.fen, level!);
    } catch (_) {}
    if (_disposed || token != _token) return;
    final dt = DateTime.now().difference(t0).inMilliseconds;
    if (dt < 450) await Future.delayed(Duration(milliseconds: 450 - dt));
    if (_disposed || token != _token) return;
    thinking = false;
    final m = uci == null ? null : game.findUci(uci);
    if (m == null || game.plyCount != plies) {
      engineError = m == null;
      notifyListeners();
      return;
    }
    _apply(m);
  }

  void retryEngine() {
    EngineService.instance.dispose().then((_) => _maybeAi());
  }

  // ------------------------------------------------------------ actions
  void _popOne() {
    game.undo();
    if (_snaps.isNotEmpty) {
      final s = _snaps.removeLast();
      whiteMs = s[0];
      blackMs = s[1];
    }
  }

  void undo() {
    premove = null;
    if (over || game.plyCount == 0 || isLan) return; // no take-backs against a friend
    _token++; // cancels any pending engine move
    if (thinking) EngineService.instance.stop();
    thinking = false;
    if (mode == 'ai') {
      int n = 0;
      while (game.plyCount > 0 && (n == 0 || game.turn != humanColor)) {
        _popOne();
        n++;
      }
    } else {
      _popOne();
    }
    selected = null;
    targets = {};
    hint = null;
    hintText = null;
    say(GEvent.undo);
    _last = null;
    _autosave();
    notifyListeners();
    _maybeAi();
  }

  Future<void> getHint() async {
    if (!canPlay || isLan) return; // no engine help in a game against a friend
    hintText = 'Thinking…';
    notifyListeners();
    final lines = await EngineService.instance.analyse(game.fen, movetimeMs: 500);
    if (_disposed) return;
    if (lines.isEmpty || lines.first.best == null) {
      hintText = 'Hint unavailable: engine not ready';
      hint = null;
    } else {
      final m = game.findUci(lines.first.best!);
      if (m != null) {
        hint = [m.from, m.to];
        hintText = 'Try ${game.san(m)}';
        say(GEvent.hint);
      }
    }
    notifyListeners();
  }

  void flip() {
    flipped = !flipped;
    notifyListeners();
  }

  void togglePause() {
    if (over || isLan) return; // the friend's clock keeps running
    paused = !paused;
    _last = null;
    notifyListeners();
  }

  void resign() {
    if (over) return;
    final loser = (mode == 'ai' || isLan) ? humanColor : game.turn;
    _finish(loser == kWhite ? GameResult.blackWins : GameResult.whiteWins, 'Resignation');
  }

  void agreeDraw() {
    if (!over) _finish(GameResult.draw, 'Draw by agreement');
  }

  /// Returns a message; draw is accepted only if the engine does not stand better.
  Future<String> offerDrawToAi() async {
    if (game.plyCount < 10) return 'The AI declines: it is too early for a draw.';
    final lines = await EngineService.instance.analyse(game.fen, movetimeMs: 400);
    if (_disposed) return '';
    if (lines.isEmpty) return 'Engine unavailable, draw declined.';
    final aiColor = 1 - humanColor;
    final aiEval = aiColor == kWhite ? lines.first.whiteCp : -lines.first.whiteCp;
    if (aiEval <= 30) {
      agreeDraw();
      return 'The AI accepts the draw.';
    }
    return 'The AI declines the draw.';
  }

  /// [remote] is true when the result came from the friend (or from a lost connection): it is then not sent back.
  void _finish(GameResult r, String reason, {bool remote = false}) {
    if (over) return;
    over = true;
    _releaseHold(); // the game is finished: background analyses may use the engine again
    premove = null;
    drawOfferIncoming = false;
    result = r;
    endReason = reason;
    thinking = false;
    _token++;
    final rs = r == GameResult.whiteWins ? '1-0' : (r == GameResult.blackWins ? '0-1' : '1/2-1/2');
    if (isLan && !remote) _lanSend({'t': 'end', 'r': rs, 'why': reason});
    record = app.recordGame(
      white: whiteName, black: blackName, result: rs, reason: reason, mode: mode,
      pgn: game.pgn(white: whiteName, black: blackName, resultStr: rs),
      startFen: game.initialFen, userColor: (mode == 'ai' || isLan) ? humanColor : kWhite,
      ucis: game.moveStack.map((m) => m.uci).toList(),
      opponentRating: mode == 'ai' ? level!.rating : null,
    );
    if (!isLan) app.setSaved(null); // a saved game against the AI is not touched by a hotspot game
    if (mode == 'ai') {
      final mine = (r == GameResult.whiteWins && humanColor == kWhite) || (r == GameResult.blackWins && humanColor == kBlack);
      say(r == GameResult.draw ? GEvent.draw : (mine ? GEvent.win : (reason == 'Resignation' ? GEvent.resign : GEvent.lose)));
    }
    AudioService.instance.play('end');
    AudioService.instance.haptic(heavy: true);
    gameOverPending = true;
    notifyListeners();
  }

  String get resultText {
    switch (result) {
      case GameResult.whiteWins:
        return (mode == 'ai' || isLan) ? (humanColor == kWhite ? 'You won!' : 'You lost') : 'White wins';
      case GameResult.blackWins:
        return (mode == 'ai' || isLan) ? (humanColor == kBlack ? 'You won!' : 'You lost') : 'Black wins';
      case GameResult.draw:
        return 'Draw';
      case GameResult.ongoing:
        return '';
    }
  }

  @override
  void dispose() {
    // leaving a running game against a friend counts as resigning, so the friend is not left waiting
    if (isLan && !over && !_disposed) {
      _lanSend({'t': 'end', 'r': humanColor == kWhite ? '0-1' : '1-0', 'why': 'Left the game'});
    }
    link?.close();
    _disposed = true;
    _releaseHold();
    _timer?.cancel();
    _token++;
    if (thinking) EngineService.instance.stop();
    super.dispose();
  }
}

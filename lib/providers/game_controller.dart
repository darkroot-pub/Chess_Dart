import 'dart:async';
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import '../core/constants/constants.dart';
import '../models/models.dart';
import '../services/audio_service.dart';
import '../services/guardian_service.dart';
import '../services/chess_service/chess_game.dart';
import '../services/stockfish_service/engine_service.dart';
import 'app_state.dart';

typedef PromotionAsker = Future<int?> Function(int color);

class GameController extends ChangeNotifier {
  final AppState app;
  final String mode; // 'ai' | 'local'
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
  int _token = 0;

  TimeControl get timeControl => customTc ?? tc;

  GameController(this.app, {required this.mode, required this.humanColor, this.aiLevelIndex = 1, this.tcIndex = 5, this.customTc, SavedGame? resume}) {
    game = ChessGame();
    whiteMs = blackMs = timeControl.baseMs;
    flipped = mode == 'ai' && humanColor == kBlack;
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
    if (mode == 'ai') EngineService.instance.newGame();
    say(resume == null ? GEvent.greet : GEvent.tip);
    Future.microtask(_maybeAi);
  }

  /// Guardian speaks (only vs AI, and only when enabled in settings).
  void say(GEvent e) {
    if (mode != 'ai' || !app.settings.guardianChat) return;
    guardianText = Guardian.say(e);
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
  String get whiteName => mode == 'ai' ? (humanColor == kWhite ? app.stats.username : 'Dark Chess AI') : 'Player 1';
  String get blackName => mode == 'ai' ? (humanColor == kBlack ? app.stats.username : 'Dark Chess AI') : 'Player 2';
  String subFor(int color) {
    if (mode == 'ai') return color == humanColor ? '(${app.stats.rating})' : '(${level!.name} · ${level!.rating})';
    return color == kWhite ? 'White' : 'Black';
  }

  bool get humanTurn => mode == 'local' || game.turn == humanColor;
  bool get canPlay => !over && !paused && !thinking && humanTurn;
  bool canDrag(int sq) => canPlay && game.board[sq] != 0 && pieceColor(game.board[sq]) == game.turn;

  // ------------------------------------------------------------ clock
  void _tick() {
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
    if (!canPlay) return;
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
    if (!canPlay || from == to) return;
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
    _snaps.add([whiteMs, blackMs]);
    game.play(m);
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
  }

  void _react(int mover, Move m) {
    if (mode != 'ai') return;
    _sinceTalk++;
    final mine = mover == humanColor;
    if (game.inCheck) {
      say(mine ? GEvent.userCheck : GEvent.aiCheck);
    } else if (m.isCapture) {
      say(mine ? GEvent.userCapture : GEvent.aiCapture);
    } else if (_sinceTalk >= 6) {
      final bal = game.materialBalance() * (humanColor == kWhite ? 1 : -1);
      say(bal >= 3 ? GEvent.winning : (bal <= -3 ? GEvent.losing : GEvent.userMove));
    }
  }

  void _autosave() {
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
    if (over || game.plyCount == 0) return;
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
    if (!canPlay) return;
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
    if (over) return;
    paused = !paused;
    _last = null;
    notifyListeners();
  }

  void resign() {
    if (over) return;
    final loser = mode == 'ai' ? humanColor : game.turn;
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

  void _finish(GameResult r, String reason) {
    if (over) return;
    over = true;
    result = r;
    endReason = reason;
    thinking = false;
    _token++;
    final rs = r == GameResult.whiteWins ? '1-0' : (r == GameResult.blackWins ? '0-1' : '1/2-1/2');
    record = app.recordGame(
      white: whiteName, black: blackName, result: rs, reason: reason, mode: mode,
      pgn: game.pgn(white: whiteName, black: blackName, resultStr: rs),
      startFen: game.initialFen, userColor: mode == 'ai' ? humanColor : kWhite,
      ucis: game.moveStack.map((m) => m.uci).toList(),
      opponentRating: mode == 'ai' ? level!.rating : null,
    );
    app.setSaved(null);
    if (mode == 'ai') {
      final mine = (r == GameResult.whiteWins && humanColor == kWhite) || (r == GameResult.blackWins && humanColor == kBlack);
      say(r == GameResult.draw ? GEvent.draw : (mine ? GEvent.win : GEvent.lose));
    }
    AudioService.instance.play('end');
    AudioService.instance.haptic(heavy: true);
    gameOverPending = true;
    notifyListeners();
  }

  String get resultText {
    switch (result) {
      case GameResult.whiteWins:
        return mode == 'ai' ? (humanColor == kWhite ? 'You won!' : 'You lost') : 'White wins';
      case GameResult.blackWins:
        return mode == 'ai' ? (humanColor == kBlack ? 'You won!' : 'You lost') : 'Black wins';
      case GameResult.draw:
        return 'Draw';
      case GameResult.ongoing:
        return '';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _token++;
    if (thinking) EngineService.instance.stop();
    super.dispose();
  }
}

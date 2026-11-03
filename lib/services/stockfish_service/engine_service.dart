import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:stockfish/stockfish.dart';
import '../../core/constants/constants.dart';

class EngineLine {
  final int multipv, depth;
  final int whiteCp; // centipawns from White's point of view (mate mapped to +-(10000 - 10*n))
  final int? mate; // from side-to-move's view
  final List<String> pv;
  EngineLine(this.multipv, this.depth, this.whiteCp, this.mate, this.pv);
  String? get best => pv.isEmpty ? null : pv.first;
}

/// Runs the bundled Stockfish through UCI. One shared instance, jobs are serialised.
class EngineService {
  static final EngineService instance = EngineService._();
  EngineService._();

  Stockfish? _sf;
  StreamSubscription<String>? _sub;
  Future<bool>? _initFuture;
  Future<void> _tail = Future.value();
  void Function(String line)? _onLine;
  bool available = false;
  VoidCallback? _stateListener;

  static final _fenRe = RegExp(r'^[1-8pnbrqkPNBRQK/]{15,80} [wb] (-|[KQkq]{1,4}) (-|[a-h][36]) \d{1,3} \d{1,4}$');
  /// Only well-formed FENs ever reach the engine (a stray newline in the string would inject UCI commands).
  static bool validFen(String fen) => _fenRe.hasMatch(fen);

  Future<bool> init() => _initFuture ??= _init();

  Future<bool> _init() async {
    try {
      final sf = Stockfish();
      _sf = sf;
      int waited = 0;
      while (sf.state.value == StockfishState.starting && waited < 15000) {
        await Future.delayed(const Duration(milliseconds: 100));
        waited += 100;
      }
      if (sf.state.value != StockfishState.ready) throw 'engine not ready';
      // if the native engine dies later, forget it so that the next request starts a fresh one
      _stateListener = () {
        if (sf.state.value != StockfishState.ready && identical(_sf, sf)) {
          available = false;
          _initFuture = null;
        }
      };
      sf.state.addListener(_stateListener!);
      final uciOk = Completer<void>();
      _sub = sf.stdout.listen((chunk) {
        for (final line in chunk.split('\n')) {
          final l = line.trim();
          if (l.isEmpty) continue;
          if (l == 'uciok' && !uciOk.isCompleted) uciOk.complete();
          _onLine?.call(l);
        }
      });
      sf.stdin = 'uci';
      await uciOk.future.timeout(const Duration(seconds: 10));
      sf.stdin = 'setoption name Threads value 2';
      sf.stdin = 'setoption name Hash value 32';
      available = true;
    } catch (e) {
      if (kDebugMode) debugPrint('Engine init failed: $e');
      available = false;
      _initFuture = null; // allow a retry instead of caching the failure forever
    }
    return available;
  }

  Future<T> _enqueue<T>(Future<T> Function() job) {
    final c = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        c.complete(await job());
      } catch (e) {
        c.completeError(e);
      }
    });
    return c.future;
  }

  void _send(String cmd) {
    final sf = _sf;
    if (sf != null) sf.stdin = cmd;
  }

  /// Waits until the engine has finished whatever it was doing (isready/readyok comes after any pending bestmove),
  /// so a late 'bestmove' from a timed-out search can never be mistaken for the answer to the next request.
  Future<void> _drain() async {
    final ok = Completer<void>();
    _onLine = (l) { if (l == 'readyok' && !ok.isCompleted) ok.complete(); };
    _send('stop');
    _send('isready');
    try {
      await ok.future.timeout(const Duration(seconds: 3));
    } catch (_) {}
    _onLine = null;
  }

  /// Restarts the native engine (after a crash or a hung search).
  Future<bool> restart() async {
    await dispose();
    return init();
  }

  Future<void> newGame() async {
    if (!await init()) return;
    await _enqueue(() async => _send('ucinewgame'));
  }

  void stop() {
    if (available) _send('stop');
  }

  /// Full-strength analysis; returns up to [multiPv] lines ordered best first.
  Future<List<EngineLine>> analyse(String fen, {int movetimeMs = 300, int multiPv = 1, int? depth}) async {
    if (!await init() || !validFen(fen)) return [];
    return _enqueue(() async {
      await _drain();
      _send('setoption name UCI_LimitStrength value false');
      _send('setoption name Skill Level value 20');
      _send('setoption name MultiPV value $multiPv');
      _send('position fen $fen');
      final whiteToMove = fen.split(' ')[1] == 'w';
      final lines = <int, EngineLine>{};
      final done = Completer<void>();
      _onLine = (l) {
        if (l.startsWith('info') && l.contains(' pv ') && l.contains(' score ') && !l.contains('lowerbound') && !l.contains('upperbound')) {
          final t = l.split(' ');
          int mpv = 1, depth = 0;
          int? cp, mate;
          for (int i = 0; i < t.length - 1; i++) {
            if (t[i] == 'multipv') mpv = int.tryParse(t[i + 1]) ?? 1;
            if (t[i] == 'depth') depth = int.tryParse(t[i + 1]) ?? 0;
            if (t[i] == 'score' && i + 2 < t.length) {
              if (t[i + 1] == 'cp') cp = int.tryParse(t[i + 2]);
              if (t[i + 1] == 'mate') mate = int.tryParse(t[i + 2]);
            }
          }
          final pvIdx = t.indexOf('pv');
          final pv = pvIdx >= 0 ? t.sublist(pvIdx + 1) : <String>[];
          int stm;
          if (mate != null) {
            stm = (mate > 0 ? 1 : -1) * (10000 - 10 * mate.abs());
          } else {
            stm = cp ?? 0;
          }
          lines[mpv] = EngineLine(mpv, depth, whiteToMove ? stm : -stm, mate, pv);
        } else if (l.startsWith('bestmove')) {
          if (!done.isCompleted) done.complete();
        }
      };
      // with a depth the search stops at whichever comes first: that depth or the time cap
      _send(depth != null ? 'go depth $depth movetime $movetimeMs' : 'go movetime $movetimeMs');
      var timedOut = false;
      await done.future.timeout(Duration(milliseconds: movetimeMs + 10000), onTimeout: () {
        timedOut = true;
      });
      _onLine = null;
      if (timedOut) {
        // an unfinished search is NOT a result: never classify a move from partial analysis
        await _drain();
        return <EngineLine>[];
      }
      final out = lines.values.toList()..sort((a, b) => a.multipv.compareTo(b.multipv));
      // every requested line must exist and agree on the position being analysed
      if (out.isEmpty || out.first.pv.isEmpty) return <EngineLine>[];
      return out;
    });
  }

  /// Engine move for the bot, using the configured difficulty. Returns a UCI move or null.
  Future<String?> bestMove(String fen, AiLevel level) async {
    if (!await init() || !validFen(fen)) return null;
    return _enqueue(() async {
      await _drain();
      _send('setoption name MultiPV value 1');
      if (level.uciElo != null) {
        _send('setoption name UCI_LimitStrength value true');
        _send('setoption name UCI_Elo value ${level.uciElo!.clamp(1320, 3190)}');
      } else {
        _send('setoption name UCI_LimitStrength value false');
      }
      _send('setoption name Skill Level value ${level.skill}');
      _send('position fen $fen');
      final done = Completer<String?>();
      _onLine = (l) {
        if (l.startsWith('bestmove')) {
          final p = l.split(' ');
          if (!done.isCompleted) done.complete(p.length > 1 && p[1] != '(none)' ? p[1] : null);
        }
      };
      _send(level.depth != null ? 'go depth ${level.depth} movetime ${level.movetime}' : 'go movetime ${level.movetime}');
      var timedOut = false;
      final r = await done.future.timeout(Duration(milliseconds: level.movetime + 10000), onTimeout: () {
        timedOut = true;
        return null;
      });
      _onLine = null;
      if (timedOut) await _drain();
      return r;
    });
  }

  Future<void> dispose() async {
    final l = _stateListener;
    if (l != null) _sf?.state.removeListener(l);
    _stateListener = null;
    await _sub?.cancel();
    _sub = null;
    _sf?.dispose();
    _sf = null;
    _initFuture = null;
    available = false;
  }
}

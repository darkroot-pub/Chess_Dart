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
      debugPrint('Stockfish init failed: $e');
      available = false;
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

  void _send(String cmd) => _sf!.stdin = cmd;

  Future<void> newGame() async {
    if (!await init()) return;
    await _enqueue(() async => _send('ucinewgame'));
  }

  void stop() {
    if (available) _send('stop');
  }

  /// Full-strength analysis; returns up to [multiPv] lines ordered best first.
  Future<List<EngineLine>> analyse(String fen, {int movetimeMs = 300, int multiPv = 1}) async {
    if (!await init()) return [];
    return _enqueue(() async {
      _send('setoption name UCI_LimitStrength value false');
      _send('setoption name Skill Level value 20');
      _send('setoption name MultiPV value $multiPv');
      _send('position fen $fen');
      final whiteToMove = fen.split(' ')[1] == 'w';
      final lines = <int, EngineLine>{};
      final done = Completer<void>();
      _onLine = (l) {
        if (l.startsWith('info') && l.contains(' pv ') && l.contains(' score ')) {
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
      _send('go movetime $movetimeMs');
      await done.future.timeout(Duration(milliseconds: movetimeMs + 10000), onTimeout: () {
        _send('stop');
      });
      _onLine = null;
      final out = lines.values.toList()..sort((a, b) => a.multipv.compareTo(b.multipv));
      return out;
    });
  }

  /// Engine move for the bot, using the configured difficulty. Returns a UCI move or null.
  Future<String?> bestMove(String fen, AiLevel level) async {
    if (!await init()) return null;
    return _enqueue(() async {
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
      final r = await done.future.timeout(Duration(milliseconds: level.movetime + 10000), onTimeout: () {
        _send('stop');
        return null;
      });
      _onLine = null;
      return r;
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sf?.dispose();
    _sf = null;
    _initFuture = null;
    available = false;
  }
}

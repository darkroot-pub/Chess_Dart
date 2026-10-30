// Self-contained chess rules: legal moves, check/mate/stalemate, castling, en passant,
// promotion, repetition, 50-move, insufficient material, FEN, SAN, PGN.
const int kEmpty = 0, kP = 1, kN = 2, kB = 3, kR = 4, kQ = 5, kK = 6;
const int kWhite = 0, kBlack = 1;
const String _letters = ' pnbrqk';

int pieceType(int p) => p & 7;
int pieceColor(int p) => p >> 3;
int makePiece(int type, int color) => type | (color << 3);
String sqName(int s) => '${String.fromCharCode(97 + (s & 7))}${(s >> 3) + 1}';
int sqFromName(String n) => (n.codeUnitAt(0) - 97) + (int.parse(n[1]) - 1) * 8;
String pieceKey(int p) => '${pieceColor(p) == 0 ? 'w' : 'b'}${' PNBRQK'[pieceType(p)]}';
const Map<int, int> kPieceValue = {kP: 1, kN: 3, kB: 3, kR: 5, kQ: 9, kK: 0};

class Move {
  final int from, to, piece, captured, promo;
  final bool ep, castleK, castleQ, dbl;
  const Move(this.from, this.to, this.piece,
      {this.captured = 0, this.promo = 0, this.ep = false, this.castleK = false, this.castleQ = false, this.dbl = false});
  String get uci => sqName(from) + sqName(to) + (promo != 0 ? _letters[promo] : '');
  bool get isCapture => captured != 0;
}

class _Undo {
  final Move move;
  final int castling, ep, half, full;
  _Undo(this.move, this.castling, this.ep, this.half, this.full);
}

enum GameResult { ongoing, whiteWins, blackWins, draw }

class ChessGame {
  static const String startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  List<int> board = List.filled(64, 0);
  int turn = kWhite;
  int castling = 15; // 1=WK 2=WQ 4=BK 8=BQ
  int ep = -1;
  int halfmove = 0, fullmove = 1;
  final List<_Undo> _undo = [];
  final List<String> sanList = [];
  final List<String> fenHistory = []; // fen after each move (index 0 = after move 1)
  final List<String> _keys = [];
  String initialFen = startFen;

  ChessGame() {
    loadFen(startFen);
  }
  ChessGame.fromFen(String fen) {
    if (!loadFen(fen)) loadFen(startFen);
  }

  List<Move> get moveStack => _undo.map((u) => u.move).toList();
  int get plyCount => _undo.length;
  Move? get lastMove => _undo.isEmpty ? null : _undo.last.move;

  // ---------------------------------------------------------------- FEN
  bool loadFen(String fen) {
    try {
      final parts = fen.trim().split(RegExp(r'\s+'));
      if (parts.length < 4) return false;
      final b = List<int>.filled(64, 0);
      final rows = parts[0].split('/');
      if (rows.length != 8) return false;
      for (int i = 0; i < 8; i++) {
        int f = 0;
        for (final ch in rows[i].split('')) {
          final d = int.tryParse(ch);
          if (d != null) {
            f += d;
          } else {
            final t = _letters.indexOf(ch.toLowerCase());
            if (t < 1 || f > 7) return false;
            b[(7 - i) * 8 + f] = makePiece(t, ch == ch.toUpperCase() ? kWhite : kBlack);
            f++;
          }
        }
        if (f != 8) return false;
      }
      int wk = 0, bk = 0;
      for (final p in b) {
        if (p == makePiece(kK, kWhite)) wk++;
        if (p == makePiece(kK, kBlack)) bk++;
      }
      if (wk != 1 || bk != 1) return false;
      board = b;
      turn = parts[1] == 'b' ? kBlack : kWhite;
      castling = 0;
      if (parts[2].contains('K')) castling |= 1;
      if (parts[2].contains('Q')) castling |= 2;
      if (parts[2].contains('k')) castling |= 4;
      if (parts[2].contains('q')) castling |= 8;
      ep = parts[3] == '-' ? -1 : sqFromName(parts[3]);
      halfmove = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;
      fullmove = parts.length > 5 ? int.tryParse(parts[5]) ?? 1 : 1;
      _undo.clear();
      sanList.clear();
      fenHistory.clear();
      _keys
        ..clear()
        ..add(_key());
      initialFen = this.fen;
      return true;
    } catch (_) {
      return false;
    }
  }

  String get fen {
    final sb = StringBuffer();
    for (int r = 7; r >= 0; r--) {
      int empty = 0;
      for (int f = 0; f < 8; f++) {
        final p = board[r * 8 + f];
        if (p == 0) {
          empty++;
        } else {
          if (empty > 0) sb.write(empty);
          empty = 0;
          final l = _letters[pieceType(p)];
          sb.write(pieceColor(p) == kWhite ? l.toUpperCase() : l);
        }
      }
      if (empty > 0) sb.write(empty);
      if (r > 0) sb.write('/');
    }
    String c = '';
    if (castling & 1 != 0) c += 'K';
    if (castling & 2 != 0) c += 'Q';
    if (castling & 4 != 0) c += 'k';
    if (castling & 8 != 0) c += 'q';
    if (c.isEmpty) c = '-';
    return '$sb ${turn == kWhite ? 'w' : 'b'} $c ${ep < 0 ? '-' : sqName(ep)} $halfmove $fullmove';
  }

  String _key() {
    final f = fen.split(' ');
    // only count the ep square when a pawn can really capture there
    String e = '-';
    if (ep >= 0 && _epCapturePossible()) e = sqName(ep);
    return '${f[0]} ${f[1]} ${f[2]} $e';
  }

  bool _epCapturePossible() {
    for (final m in legalMoves()) {
      if (m.ep) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- attacks
  bool isAttacked(int sq, int by) {
    final r = sq >> 3, f = sq & 7;
    final pr = by == kWhite ? r - 1 : r + 1;
    if (pr >= 0 && pr < 8) {
      for (final df in [-1, 1]) {
        final pf = f + df;
        if (pf >= 0 && pf < 8 && board[pr * 8 + pf] == makePiece(kP, by)) return true;
      }
    }
    for (final d in _knightD) {
      final nr = r + d[0], nf = f + d[1];
      if (_in(nr, nf) && board[nr * 8 + nf] == makePiece(kN, by)) return true;
    }
    for (final d in _kingD) {
      final nr = r + d[0], nf = f + d[1];
      if (_in(nr, nf) && board[nr * 8 + nf] == makePiece(kK, by)) return true;
    }
    for (final d in _diag) {
      int nr = r + d[0], nf = f + d[1];
      while (_in(nr, nf)) {
        final p = board[nr * 8 + nf];
        if (p != 0) {
          if (pieceColor(p) == by && (pieceType(p) == kB || pieceType(p) == kQ)) return true;
          break;
        }
        nr += d[0];
        nf += d[1];
      }
    }
    for (final d in _orth) {
      int nr = r + d[0], nf = f + d[1];
      while (_in(nr, nf)) {
        final p = board[nr * 8 + nf];
        if (p != 0) {
          if (pieceColor(p) == by && (pieceType(p) == kR || pieceType(p) == kQ)) return true;
          break;
        }
        nr += d[0];
        nf += d[1];
      }
    }
    return false;
  }

  /// Values of all pieces of colour [by] attacking [sq] (used by analysis).
  List<int> attackerValues(int sq, int by) {
    final res = <int>[];
    final saved = board[sq];
    for (int s = 0; s < 64; s++) {
      final p = board[s];
      if (p == 0 || pieceColor(p) != by) continue;
      final t = pieceType(p);
      final r = s >> 3, f = s & 7, tr = sq >> 3, tf = sq & 7;
      bool hit = false;
      if (t == kP) {
        hit = (tr - r) == (by == kWhite ? 1 : -1) && (tf - f).abs() == 1;
      } else if (t == kN) {
        hit = ((tr - r).abs() == 1 && (tf - f).abs() == 2) || ((tr - r).abs() == 2 && (tf - f).abs() == 1);
      } else if (t == kK) {
        hit = (tr - r).abs() <= 1 && (tf - f).abs() <= 1 && s != sq;
      } else {
        final dirs = t == kB ? _diag : (t == kR ? _orth : [..._diag, ..._orth]);
        for (final d in dirs) {
          int nr = r + d[0], nf = f + d[1];
          while (_in(nr, nf)) {
            if (nr * 8 + nf == sq) {
              hit = true;
              break;
            }
            if (board[nr * 8 + nf] != 0) break;
            nr += d[0];
            nf += d[1];
          }
          if (hit) break;
        }
      }
      if (hit) res.add(t == kK ? 100 : kPieceValue[t]!);
    }
    board[sq] = saved;
    return res;
  }

  static const _knightD = [[1, 2], [2, 1], [-1, 2], [-2, 1], [1, -2], [2, -1], [-1, -2], [-2, -1]];
  static const _kingD = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];
  static const _diag = [[1, 1], [1, -1], [-1, 1], [-1, -1]];
  static const _orth = [[1, 0], [-1, 0], [0, 1], [0, -1]];
  bool _in(int r, int f) => r >= 0 && r < 8 && f >= 0 && f < 8;

  int kingSquare(int color) => board.indexOf(makePiece(kK, color));
  bool get inCheck => isAttacked(kingSquare(turn), 1 - turn);

  // ---------------------------------------------------------------- generation
  List<Move> _pseudo() {
    final res = <Move>[];
    final us = turn;
    for (int s = 0; s < 64; s++) {
      final p = board[s];
      if (p == 0 || pieceColor(p) != us) continue;
      final t = pieceType(p), r = s >> 3, f = s & 7;
      if (t == kP) {
        final dir = us == kWhite ? 1 : -1;
        final startR = us == kWhite ? 1 : 6;
        final promoR = us == kWhite ? 7 : 0;
        final nr = r + dir;
        if (nr >= 0 && nr < 8 && board[nr * 8 + f] == 0) {
          _addPawn(res, s, nr * 8 + f, p, 0, promoR == nr);
          if (r == startR && board[(r + 2 * dir) * 8 + f] == 0) {
            res.add(Move(s, (r + 2 * dir) * 8 + f, p, dbl: true));
          }
        }
        for (final df in [-1, 1]) {
          final nf = f + df;
          if (nf < 0 || nf > 7 || nr < 0 || nr > 7) continue;
          final to = nr * 8 + nf;
          final tp = board[to];
          if (tp != 0 && pieceColor(tp) != us) {
            _addPawn(res, s, to, p, tp, promoR == nr);
          } else if (tp == 0 && to == ep) {
            res.add(Move(s, to, p, captured: makePiece(kP, 1 - us), ep: true));
          }
        }
      } else if (t == kN || t == kK) {
        for (final d in (t == kN ? _knightD : _kingD)) {
          final nr = r + d[0], nf = f + d[1];
          if (!_in(nr, nf)) continue;
          final tp = board[nr * 8 + nf];
          if (tp == 0 || pieceColor(tp) != us) res.add(Move(s, nr * 8 + nf, p, captured: tp));
        }
        if (t == kK) _castles(res, s, p);
      } else {
        final dirs = t == kB ? _diag : (t == kR ? _orth : [..._diag, ..._orth]);
        for (final d in dirs) {
          int nr = r + d[0], nf = f + d[1];
          while (_in(nr, nf)) {
            final tp = board[nr * 8 + nf];
            if (tp == 0) {
              res.add(Move(s, nr * 8 + nf, p));
            } else {
              if (pieceColor(tp) != us) res.add(Move(s, nr * 8 + nf, p, captured: tp));
              break;
            }
            nr += d[0];
            nf += d[1];
          }
        }
      }
    }
    return res;
  }

  void _addPawn(List<Move> res, int from, int to, int p, int cap, bool promo) {
    if (promo) {
      for (final t in [kQ, kR, kB, kN]) {
        res.add(Move(from, to, p, captured: cap, promo: t));
      }
    } else {
      res.add(Move(from, to, p, captured: cap));
    }
  }

  void _castles(List<Move> res, int s, int p) {
    final us = turn, them = 1 - us, base = us == kWhite ? 0 : 56;
    if (s != base + 4) return;
    if (isAttacked(s, them)) return;
    final kBit = us == kWhite ? 1 : 4, qBit = us == kWhite ? 2 : 8;
    if (castling & kBit != 0 &&
        board[base + 5] == 0 && board[base + 6] == 0 &&
        board[base + 7] == makePiece(kR, us) &&
        !isAttacked(base + 5, them) && !isAttacked(base + 6, them)) {
      res.add(Move(s, base + 6, p, castleK: true));
    }
    if (castling & qBit != 0 &&
        board[base + 1] == 0 && board[base + 2] == 0 && board[base + 3] == 0 &&
        board[base] == makePiece(kR, us) &&
        !isAttacked(base + 3, them) && !isAttacked(base + 2, them)) {
      res.add(Move(s, base + 2, p, castleQ: true));
    }
  }

  List<Move> legalMoves() {
    final us = turn;
    final res = <Move>[];
    for (final m in _pseudo()) {
      _make(m);
      final ok = !isAttacked(kingSquare(us), 1 - us);
      _unmake();
      if (ok) res.add(m);
    }
    return res;
  }

  List<Move> legalMovesFrom(int sq) => legalMoves().where((m) => m.from == sq).toList();

  // ---------------------------------------------------------------- make / unmake
  void _make(Move m) {
    _undo.add(_Undo(m, castling, ep, halfmove, fullmove));
    final us = turn;
    board[m.from] = 0;
    if (m.ep) board[(m.from >> 3) * 8 + (m.to & 7)] = 0;
    board[m.to] = m.promo != 0 ? makePiece(m.promo, us) : m.piece;
    if (m.castleK) {
      board[m.to - 1] = board[m.to + 1];
      board[m.to + 1] = 0;
    }
    if (m.castleQ) {
      board[m.to + 1] = board[m.to - 2];
      board[m.to - 2] = 0;
    }
    if (pieceType(m.piece) == kK) castling &= us == kWhite ? ~3 : ~12;
    for (final s in [m.from, m.to]) {
      if (s == 0) castling &= ~2;
      if (s == 7) castling &= ~1;
      if (s == 56) castling &= ~8;
      if (s == 63) castling &= ~4;
    }
    ep = m.dbl ? (m.from + m.to) ~/ 2 : -1;
    halfmove = (pieceType(m.piece) == kP || m.captured != 0) ? 0 : halfmove + 1;
    if (us == kBlack) fullmove++;
    turn = 1 - us;
  }

  void _unmake() {
    final u = _undo.removeLast();
    final m = u.move;
    turn = 1 - turn;
    final us = turn;
    castling = u.castling;
    ep = u.ep;
    halfmove = u.half;
    fullmove = u.full;
    board[m.from] = m.piece;
    board[m.to] = 0;
    if (m.ep) {
      board[(m.from >> 3) * 8 + (m.to & 7)] = makePiece(kP, 1 - us);
    } else if (m.captured != 0) {
      board[m.to] = m.captured;
    }
    if (m.castleK) {
      board[m.to + 1] = board[m.to - 1];
      board[m.to - 1] = 0;
    }
    if (m.castleQ) {
      board[m.to - 2] = board[m.to + 1];
      board[m.to + 1] = 0;
    }
  }

  // ---------------------------------------------------------------- public play API
  /// Finds the legal move matching from/to (+promo type, default queen).
  Move? findMove(int from, int to, {int promo = kQ}) {
    for (final m in legalMoves()) {
      if (m.from == from && m.to == to && (m.promo == 0 || m.promo == promo)) return m;
    }
    return null;
  }

  Move? findUci(String uci) {
    if (uci.length < 4) return null;
    final from = sqFromName(uci.substring(0, 2)), to = sqFromName(uci.substring(2, 4));
    int promo = kQ;
    if (uci.length > 4) promo = _letters.indexOf(uci[4]);
    return findMove(from, to, promo: promo);
  }

  bool needsPromotion(int from, int to) {
    final p = board[from];
    if (p == 0 || pieceType(p) != kP) return false;
    final r = to >> 3;
    return (r == 7 && pieceColor(p) == kWhite) || (r == 0 && pieceColor(p) == kBlack);
  }

  String play(Move m) {
    final s = san(m);
    _make(m);
    sanList.add(s);
    fenHistory.add(fen);
    _keys.add(_key());
    return s;
  }

  Move? undo() {
    if (_undo.isEmpty) return null;
    final m = _undo.last.move;
    _unmake();
    sanList.removeLast();
    fenHistory.removeLast();
    _keys.removeLast();
    return m;
  }

  // ---------------------------------------------------------------- SAN
  String san(Move m) {
    String s;
    final t = pieceType(m.piece);
    if (m.castleK) {
      s = 'O-O';
    } else if (m.castleQ) {
      s = 'O-O-O';
    } else {
      s = '';
      if (t == kP) {
        if (m.isCapture) s += String.fromCharCode(97 + (m.from & 7));
      } else {
        s += ' pNBRQK'[t];
        final others = legalMoves().where((o) => o.to == m.to && o.piece == m.piece && o.from != m.from).toList();
        if (others.isNotEmpty) {
          final sameFile = others.any((o) => (o.from & 7) == (m.from & 7));
          final sameRank = others.any((o) => (o.from >> 3) == (m.from >> 3));
          if (!sameFile) {
            s += String.fromCharCode(97 + (m.from & 7));
          } else if (!sameRank) {
            s += '${(m.from >> 3) + 1}';
          } else {
            s += sqName(m.from);
          }
        }
      }
      if (m.isCapture) s += 'x';
      s += sqName(m.to);
      if (m.promo != 0) s += '=${' pNBRQK'[m.promo]}';
    }
    _make(m);
    final chk = inCheck;
    final hasMove = legalMoves().isNotEmpty;
    _unmake();
    if (chk) s += hasMove ? '+' : '#';
    return s;
  }

  // ---------------------------------------------------------------- status
  bool get isCheckmate => inCheck && legalMoves().isEmpty;
  bool get isStalemate => !inCheck && legalMoves().isEmpty;

  bool get insufficientMaterial {
    final minors = <int>[]; // squares of minor pieces
    for (int s = 0; s < 64; s++) {
      final t = pieceType(board[s]);
      if (board[s] == 0 || t == kK) continue;
      if (t == kP || t == kR || t == kQ) return false;
      minors.add(s);
    }
    if (minors.length <= 1) return true;
    // only bishops, all on same colour squares
    if (minors.every((s) => pieceType(board[s]) == kB)) {
      final c = ((minors.first >> 3) + (minors.first & 7)) % 2;
      return minors.every((s) => ((s >> 3) + (s & 7)) % 2 == c);
    }
    return false;
  }

  bool get threefold {
    final k = _keys.last;
    return _keys.where((e) => e == k).length >= 3;
  }

  bool get fiftyMove => halfmove >= 100;

  GameResult get result {
    if (isCheckmate) return turn == kWhite ? GameResult.blackWins : GameResult.whiteWins;
    if (isStalemate || insufficientMaterial || threefold || fiftyMove) return GameResult.draw;
    return GameResult.ongoing;
  }

  String get endReason {
    if (isCheckmate) return 'Checkmate';
    if (isStalemate) return 'Stalemate';
    if (insufficientMaterial) return 'Insufficient material';
    if (threefold) return 'Threefold repetition';
    if (fiftyMove) return 'Fifty-move rule';
    return '';
  }

  // ---------------------------------------------------------------- material / captured
  /// Captured pieces by the given colour (i.e. pieces of the opposite colour that were taken).
  List<int> capturedBy(int color) {
    final out = <int>[];
    for (final u in _undo) {
      if (pieceColor(u.move.piece) == color && u.move.captured != 0) out.add(u.move.captured);
    }
    out.sort((a, b) => pieceType(b).compareTo(pieceType(a)));
    return out;
  }

  int materialBalance() {
    int w = 0, b = 0;
    for (final p in board) {
      if (p == 0) continue;
      final v = kPieceValue[pieceType(p)]!;
      if (pieceColor(p) == kWhite) {
        w += v;
      } else {
        b += v;
      }
    }
    return w - b;
  }

  // ---------------------------------------------------------------- PGN
  String pgn({String white = 'White', String black = 'Black', String resultStr = '*', String event = 'DarkChess game'}) {
    final sb = StringBuffer()
      ..writeln('[Event "$event"]')
      ..writeln('[Site "DarkChess"]')
      ..writeln('[White "$white"]')
      ..writeln('[Black "$black"]')
      ..writeln('[Result "$resultStr"]');
    if (initialFen != startFen) {
      sb
        ..writeln('[SetUp "1"]')
        ..writeln('[FEN "$initialFen"]');
    }
    sb.writeln();
    int startNo = int.tryParse(initialFen.split(' ').last) ?? 1;
    bool blackFirst = initialFen.split(' ')[1] == 'b';
    for (int i = 0; i < sanList.length; i++) {
      final whiteMove = blackFirst ? i % 2 == 1 : i % 2 == 0;
      final no = startNo + (blackFirst ? (i + 1) ~/ 2 : i ~/ 2);
      if (whiteMove) {
        sb.write('$no. ');
      } else if (i == 0) {
        sb.write('$no... ');
      }
      sb.write('${sanList[i]} ');
    }
    sb.write(resultStr);
    return sb.toString();
  }
}

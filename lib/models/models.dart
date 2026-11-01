import 'dart:convert';

class AppSettings {
  bool sound = true, vibration = true, showLegal = true, autoQueen = false, coords = true,
      animateMoves = true, highlightLast = true, guardianChat = true, guardianPuzzles = true, guardianSpin = true;
  int boardTheme = 6; // Ocean
  String pieceSet = 'lowpoly3d';
  Map<String, dynamic> toJson() => {
        'sound': sound, 'vibration': vibration, 'showLegal': showLegal, 'autoQueen': autoQueen,
        'coords': coords, 'animateMoves': animateMoves, 'highlightLast': highlightLast, 'guardianChat': guardianChat,
        'guardianPuzzles': guardianPuzzles, 'guardianSpin': guardianSpin, 'boardTheme': boardTheme, 'pieceSet': pieceSet,
      };
  static AppSettings fromJson(Map<String, dynamic> j) {
    final s = AppSettings();
    s.sound = j['sound'] ?? true;
    s.vibration = j['vibration'] ?? true;
    s.showLegal = j['showLegal'] ?? true;
    s.autoQueen = j['autoQueen'] ?? false;
    s.coords = j['coords'] ?? true;
    s.animateMoves = j['animateMoves'] ?? true;
    s.highlightLast = j['highlightLast'] ?? true;
    s.guardianChat = j['guardianChat'] ?? true;
    s.guardianPuzzles = j['guardianPuzzles'] ?? true;
    s.guardianSpin = j['guardianSpin'] ?? true;
    s.boardTheme = j['boardTheme'] ?? 6;
    s.pieceSet = j['pieceSet'] ?? 'lowpoly3d';
    return s;
  }
}

class PlayerStats {
  String username = 'Player';
  int rating = 1200, played = 0, wins = 0, losses = 0, draws = 0, puzzlePoints = 0;
  Set<String> solved = {};
  Set<String> achievements = {};
  int get winRate => played == 0 ? 0 : (wins * 100 / played).round();
  String get level => rating < 1200 ? 'Beginner' : (rating < 1700 ? 'Intermediate' : 'Advanced');
  Map<String, dynamic> toJson() => {
        'username': username, 'rating': rating, 'played': played, 'wins': wins, 'losses': losses,
        'draws': draws, 'puzzlePoints': puzzlePoints, 'solved': solved.toList(), 'ach': achievements.toList(),
      };
  static PlayerStats fromJson(Map<String, dynamic> j) {
    final s = PlayerStats();
    s.username = j['username'] ?? 'Player';
    s.rating = j['rating'] ?? 1200;
    s.played = j['played'] ?? 0;
    s.wins = j['wins'] ?? 0;
    s.losses = j['losses'] ?? 0;
    s.draws = j['draws'] ?? 0;
    s.puzzlePoints = j['puzzlePoints'] ?? 0;
    s.solved = Set<String>.from(j['solved'] ?? []);
    s.achievements = Set<String>.from(j['ach'] ?? []);
    return s;
  }
}

class GameRecord {
  final String id, date, white, black, result, reason, mode, pgn, startFen;
  final int userColor, ratingDelta;
  final List<String> ucis;
  GameRecord({
    required this.id, required this.date, required this.white, required this.black, required this.result,
    required this.reason, required this.mode, required this.pgn, required this.startFen,
    required this.userColor, required this.ratingDelta, required this.ucis,
  });
  String get opponent => userColor == 0 ? black : white;
  /// 1 win, 0 draw, -1 loss for the user
  int get outcome {
    if (result == '1/2-1/2') return 0;
    final whiteWon = result == '1-0';
    return (whiteWon == (userColor == 0)) ? 1 : -1;
  }
  Map<String, dynamic> toJson() => {
        'id': id, 'date': date, 'white': white, 'black': black, 'result': result, 'reason': reason,
        'mode': mode, 'pgn': pgn, 'startFen': startFen, 'userColor': userColor, 'ratingDelta': ratingDelta, 'ucis': ucis,
      };
  static GameRecord fromJson(Map<String, dynamic> j) => GameRecord(
        id: j['id'], date: j['date'], white: j['white'], black: j['black'], result: j['result'],
        reason: j['reason'] ?? '', mode: j['mode'] ?? '', pgn: j['pgn'] ?? '', startFen: j['startFen'],
        userColor: j['userColor'] ?? 0, ratingDelta: j['ratingDelta'] ?? 0,
        ucis: List<String>.from(j['ucis'] ?? []),
      );
}

/// A game in progress, saved so it can be resumed after the app is closed.
class SavedGame {
  final String startFen, mode;
  final List<String> ucis;
  final int whiteMs, blackMs, userColor, aiLevel, tcIndex;
  SavedGame({
    required this.startFen, required this.mode, required this.ucis, required this.whiteMs,
    required this.blackMs, required this.userColor, required this.aiLevel, required this.tcIndex,
  });
  String encode() => jsonEncode({
        'startFen': startFen, 'mode': mode, 'ucis': ucis, 'w': whiteMs, 'b': blackMs,
        'uc': userColor, 'ai': aiLevel, 'tc': tcIndex,
      });
  static SavedGame? decode(String? s) {
    if (s == null) return null;
    try {
      final j = jsonDecode(s);
      return SavedGame(
        startFen: j['startFen'], mode: j['mode'], ucis: List<String>.from(j['ucis']), whiteMs: j['w'],
        blackMs: j['b'], userColor: j['uc'], aiLevel: j['ai'], tcIndex: j['tc'],
      );
    } catch (_) {
      return null;
    }
  }
}

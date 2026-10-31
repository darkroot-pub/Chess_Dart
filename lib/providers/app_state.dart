import 'dart:math';
import 'package:flutter/material.dart';
import '../core/constants/constants.dart';
import '../models/models.dart';
import '../services/audio_service.dart';
import '../services/multiplayer_service/supabase_service.dart';
import '../services/storage_service/storage_service.dart';

class AchievementDef {
  final String id, title, desc;
  final IconData icon;
  const AchievementDef(this.id, this.title, this.desc, this.icon);
}

const List<AchievementDef> kAchievements = [
  AchievementDef('first_game', 'First Move', 'Finish your first game', Icons.flag),
  AchievementDef('first_win', 'Victory!', 'Win a game', Icons.emoji_events),
  AchievementDef('win_hard', 'Giant Slayer', 'Beat the Hard AI', Icons.military_tech),
  AchievementDef('win_expert', 'Grandmaster Mind', 'Beat the Expert AI', Icons.workspace_premium),
  AchievementDef('ten_games', 'Regular', 'Play 10 games', Icons.sports_esports),
  AchievementDef('puzzles_5', 'Puzzle Starter', 'Solve 5 puzzles', Icons.extension),
  AchievementDef('puzzles_all', 'Puzzle Master', 'Solve every puzzle', Icons.psychology),
  AchievementDef('brilliant', 'Brilliant!', 'Play a brilliant move (found in game review)', Icons.auto_awesome),
  AchievementDef('rating_1400', 'Rising Star', 'Reach a 1400 rating', Icons.trending_up),
];

class AppState extends ChangeNotifier {
  final StorageService storage = StorageService();
  AppSettings settings = AppSettings();
  PlayerStats stats = PlayerStats();
  List<GameRecord> history = [];
  SavedGame? saved;
  bool ready = false;
  int totalPuzzles = 13;

  Future<void> init() async {
    await storage.init();
    settings = storage.loadSettings();
    stats = storage.loadStats();
    history = storage.loadHistory();
    saved = storage.loadSavedGame();
    _applyAudio();
    ready = true;
    notifyListeners();
  }

  BoardTheme get boardTheme => kBoardThemes[settings.boardTheme.clamp(0, kBoardThemes.length - 1)];

  void _applyAudio() {
    AudioService.instance.sound = settings.sound;
    AudioService.instance.vibration = settings.vibration;
  }

  void updateSettings(void Function(AppSettings s) f) {
    f(settings);
    _applyAudio();
    storage.saveSettings(settings);
    notifyListeners();
  }

  bool _attached = false;

  /// Call once after Supabase init: keeps the displayed name in sync with the `profiles` table.
  void attachSupabase() {
    final sb = SupabaseService.instance;
    if (_attached || !sb.available) return;
    _attached = true;
    sb.client.auth.onAuthStateChange.listen((d) { if (d.session != null) syncProfile(); });
    syncProfile();
  }

  /// Loads the username from the database (the profile row is created by a trigger, so retry briefly).
  Future<void> syncProfile() async {
    final sb = SupabaseService.instance;
    if (!sb.available || !sb.signedIn) return;
    for (var i = 0; i < 4; i++) {
      try {
        final p = await sb.myProfile();
        final n = p?['username'] as String?;
        if (n != null && n.isNotEmpty) {
          if (stats.username != n) {
            stats.username = n;
            storage.saveStats(stats);
            notifyListeners();
          }
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }

  void setUsername(String n) {
    stats.username = n.trim().isEmpty ? 'Player' : n.trim();
    storage.saveStats(stats);
    notifyListeners();
    final sb = SupabaseService.instance;
    if (sb.available && sb.signedIn) {
      sb.updateUsername(stats.username).catchError((_) {}).whenComplete(syncProfile); // reverts if name is taken
    }
  }

  void setSaved(SavedGame? g) {
    saved = g;
    storage.saveSavedGame(g);
    notifyListeners();
  }

  /// Records a finished game, updates rating/statistics/achievements and returns the stored record.
  GameRecord recordGame({
    required String white, required String black, required String result, required String reason,
    required String mode, required String pgn, required String startFen, required int userColor,
    required List<String> ucis, int? opponentRating,
  }) {
    int delta = 0;
    final opp = opponentRating;
    final outcome = result == '1/2-1/2' ? 0 : (((result == '1-0') == (userColor == 0)) ? 1 : -1);
    if (opp != null) {
      final exp = 1 / (1 + pow(10, (opp - stats.rating) / 400));
      final score = outcome == 1 ? 1.0 : (outcome == 0 ? 0.5 : 0.0);
      delta = (24 * (score - exp)).round();
      stats.rating = max(100, stats.rating + delta);
      stats.played++;
      if (outcome == 1) stats.wins++;
      if (outcome == 0) stats.draws++;
      if (outcome == -1) stats.losses++;
      _achieve('first_game');
      if (stats.played >= 10) _achieve('ten_games');
      if (outcome == 1) {
        _achieve('first_win');
        if (opp >= 1900 && opp < 2600) _achieve('win_hard');
        if (opp >= 2600) _achieve('win_expert');
      }
      if (stats.rating >= 1400) _achieve('rating_1400');
      storage.saveStats(stats);
    }
    final rec = GameRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      date: DateTime.now().toIso8601String(),
      white: white, black: black, result: result, reason: reason, mode: mode, pgn: pgn,
      startFen: startFen, userColor: userColor, ratingDelta: delta, ucis: ucis,
    );
    history.insert(0, rec);
    storage.saveHistory(history);
    notifyListeners();
    return rec;
  }

  void _achieve(String id) => stats.achievements.add(id);

  void unlock(String id) {
    if (stats.achievements.add(id)) {
      storage.saveStats(stats);
      notifyListeners();
    }
  }

  void solvePuzzle(String id, int points) {
    if (stats.solved.add(id)) {
      stats.puzzlePoints += points;
      if (stats.solved.length >= 5) _achieve('puzzles_5');
      if (stats.solved.length >= totalPuzzles) _achieve('puzzles_all');
      storage.saveStats(stats);
      notifyListeners();
    }
  }
}

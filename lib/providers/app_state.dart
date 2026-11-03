import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/constants/constants.dart';
import '../models/models.dart';
import '../services/audio_service.dart';
import '../services/multiplayer_service/challenge_service.dart';
import '../services/multiplayer_service/supabase_service.dart';
import '../services/storage_service/storage_service.dart';
import '../services/stockfish_service/analysis_jobs.dart';

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
    AnalysisJobs.instance.bind(storage);
    settings = storage.loadSettings();
    if (!storage.uiV2) {
      // one-time: switch existing installs to the new 3D pieces + Ocean board
      settings.pieceSet = 'lowpoly3d';
      settings.boardTheme = 6;
      await storage.saveSettings(settings);
      await storage.setUiV2();
    }
    stats = storage.loadStats();
    history = storage.loadHistory();
    saved = storage.loadSavedGame();
    _pendingGames = storage.loadPending('pendingGames');
    _pendingPuzzles = storage.loadPending('pendingPuzzles');
    _settingsTs = storage.settingsTs;
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
    _settingsTs = DateTime.now().millisecondsSinceEpoch;
    storage.setSettingsTs(_settingsTs);
    storage.saveSettings(settings); _pushSoon();
    notifyListeners();
  }

  bool _attached = false;
  String? avatarUrl; // profile photo (Google photo or custom)
  String? get email => SupabaseService.instance.user?.email;

  /// Call once after Supabase init: keeps the displayed name in sync with the `profiles` table.
  void attachSupabase() {
    final sb = SupabaseService.instance;
    if (_attached || !sb.available) return;
    _attached = true;
    sb.client.auth.onAuthStateChange.listen((d) {
      if (d.session != null) {
        ChallengeService.instance.start();
        syncProfile();
      } else {
        ChallengeService.instance.stop();
        if (_synced) _resetLocal(); // another account may log in next: do not leak this user's progress
      }
    });
    if (sb.signedIn) ChallengeService.instance.start();
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
          stats.username = n;
          avatarUrl = p?['avatar_url'] as String?;
          if (avatarUrl == null || avatarUrl!.isEmpty) {
            // auto-fill the photo from the login provider (e.g. Google)
            final md = sb.user?.userMetadata;
            final pic = (md?['avatar_url'] ?? md?['picture']) as String?;
            if (pic != null && pic.isNotEmpty) {
              avatarUrl = pic;
              sb.updateAvatar(pic).catchError((_) {});
            }
          }
          await _pullAndMerge();
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }

  void setUsername(String n) {
    final clean = n.trim().replaceAll(RegExp(r'[\u0000-\u001F\u007F\u200B-\u200F\u202A-\u202E]'), '');
    stats.username = clean.isEmpty ? 'Player' : (clean.length > 20 ? clean.substring(0, 20) : clean);
    storage.saveStats(stats); _pushSoon();
    notifyListeners();
    final sb = SupabaseService.instance;
    if (sb.available && sb.signedIn) {
      sb.updateUsername(stats.username).catchError((_) {}).whenComplete(syncProfile); // reverts if name is taken
    }
  }

  // ---------------------------------------------------------------- cloud progress
  // Sync model (multi-device safe): the server keeps the authoritative counters. This device only sends
  //   * events  (finished rated games / solved puzzles, each with a unique id the server counts exactly once)
  //   * sets    (achievements: union)
  //   * latest settings (newest timestamp wins) and recent game records (merged by id)
  // and replaces its local stats with what the server returns. Unsent events survive restarts and offline periods.
  bool _synced = false, _syncing = false, _again = false;
  Timer? _pushTimer;
  String syncStatus = ''; // shown in the profile screen
  List<Map<String, dynamic>> _pendingGames = [], _pendingPuzzles = [];
  int _settingsTs = 0;

  static String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30).toRadixString(36)}';

  void _queue(List<Map<String, dynamic>> q, String key, Map<String, dynamic> e) {
    q.add(e);
    if (q.length > 500) q.removeRange(0, q.length - 500);
    storage.savePending(key, q);
  }

  void _pushSoon() {
    final sb = SupabaseService.instance;
    if (!_synced || !sb.available || !sb.signedIn) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 2), () { pushNow(); });
  }

  Future<void> pushNow() async {
    final sb = SupabaseService.instance;
    if (!sb.available || !sb.signedIn) return;
    if (_syncing) { _again = true; return; } // one request at a time; changes made meanwhile trigger another round
    _syncing = true;
    try {
      final first = !storage.syncV2;
      // First sync of this install: the old local stats go up as a one-time baseline, which already contains
      // every game/puzzle recorded so far, so those must not be sent again as events.
      if (first) { _pendingGames = []; _pendingPuzzles = []; }
      final games = List<Map<String, dynamic>>.of(_pendingGames);
      final puzzles = List<Map<String, dynamic>>.of(_pendingPuzzles);
      final r = await sb.syncProgress(
        baseline: first ? stats.toJson() : null,
        games: games,
        puzzles: puzzles,
        ach: stats.achievements.toList(),
        settings: settings.toJson(),
        settingsTs: _settingsTs,
        history: history.take(50).map((e) => e.toJson()).toList(),
      );
      // acknowledged: forget exactly the events that were sent
      final gi = games.map((e) => e['id']).toSet(), pi = puzzles.map((e) => e['id']).toSet();
      _pendingGames.removeWhere((e) => gi.contains(e['id']));
      _pendingPuzzles.removeWhere((e) => pi.contains(e['id']));
      await storage.savePending('pendingGames', _pendingGames);
      await storage.savePending('pendingPuzzles', _pendingPuzzles);
      await storage.setSyncV2();
      _applyServer(r);
      _synced = true;
      syncStatus = 'Saved to cloud';
    } catch (_) {
      syncStatus = 'Cloud sync pending. It will retry when you are online.';
    } finally {
      _syncing = false;
    }
    notifyListeners();
    if (_again) { _again = false; _pushSoon(); }
  }

  /// Adopts the server's authoritative copy, then re-applies events that are still waiting to be sent.
  void _applyServer(Map<String, dynamic> r) {
    final rs = PlayerStats.fromJson(Map<String, dynamic>.from(r['stats'] ?? {}));
    rs.username = stats.username; // the name comes from the profiles table
    rs.achievements = {...rs.achievements, ...stats.achievements};
    for (final e in _pendingGames) {
      final o = e['o'] as int;
      rs.played++;
      if (o == 1) rs.wins++; else if (o == 0) rs.draws++; else rs.losses++;
      rs.rating = max(100, rs.rating + (e['d'] as int));
    }
    for (final e in _pendingPuzzles) {
      if (rs.solved.add(e['id'] as String)) rs.puzzlePoints += e['p'] as int;
    }
    stats = rs;
    storage.saveStats(stats);

    final sts = (r['settings_ts'] as num?)?.toInt() ?? 0;
    final rset = r['settings'];
    if (sts > _settingsTs && rset is Map && rset.isNotEmpty) {
      settings = AppSettings.fromJson(Map<String, dynamic>.from(rset));
      _settingsTs = sts;
      storage.saveSettings(settings);
      storage.setSettingsTs(sts);
      _applyAudio();
    }

    final byId = <String, GameRecord>{for (final g in history) g.id: g};
    for (final e in (r['history'] as List? ?? [])) {
      try {
        final g = GameRecord.fromJson(Map<String, dynamic>.from(e));
        byId.putIfAbsent(g.id, () => g);
      } catch (_) {}
    }
    history = byId.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    if (history.length > 200) history = history.sublist(0, 200);
    storage.saveHistory(history);
  }

  /// First call after sign-in / app start: exchanges data with the server.
  Future<void> _pullAndMerge() async {
    _synced = true;
    await pushNow();
  }

  void _resetLocal() {
    _synced = false;
    _pushTimer?.cancel();
    _pendingGames = [];
    _pendingPuzzles = [];
    _settingsTs = 0;
    storage.savePending('pendingGames', _pendingGames);
    storage.savePending('pendingPuzzles', _pendingPuzzles);
    storage.setSettingsTs(0);
    stats = PlayerStats();
    history = [];
    settings = AppSettings();
    saved = null;
    storage.saveStats(stats);
    storage.saveHistory(history);
    storage.saveSettings(settings);
    storage.saveSavedGame(null);
    syncStatus = '';
    avatarUrl = null;
    notifyListeners();
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
    final gid = _newId();
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
      _queue(_pendingGames, 'pendingGames', {'id': gid, 'o': outcome, 'd': delta});
      storage.saveStats(stats); _pushSoon();
    }
    final rec = GameRecord(
      id: gid,
      date: DateTime.now().toIso8601String(),
      white: white, black: black, result: result, reason: reason, mode: mode, pgn: pgn,
      startFen: startFen, userColor: userColor, ratingDelta: delta, ucis: ucis,
    );
    history.insert(0, rec);
    storage.saveHistory(history); _pushSoon();
    notifyListeners();
    return rec;
  }

  /// Stores a finished ONLINE game in the history (and so in the cloud copy). The server already applied rating and
  /// result, so no statistics are touched here. Safe to call repeatedly: a game id is stored once.
  void recordOnlineGame(GameRecord rec) {
    if (history.any((g) => g.id == rec.id)) return;
    history.insert(0, rec);
    history.sort((a, b) => b.date.compareTo(a.date));
    if (history.length > 200) history = history.sublist(0, 200);
    storage.saveHistory(history); _pushSoon();
    notifyListeners();
  }

  /// Adds the rating change of an online game once it is known.
  void setOnlineRatingDelta(String id, int delta) {
    final i = history.indexWhere((g) => g.id == id);
    if (i < 0 || history[i].ratingDelta == delta) return;
    final o = history[i];
    history[i] = GameRecord(
      id: o.id, date: o.date, white: o.white, black: o.black, result: o.result, reason: o.reason, mode: o.mode,
      pgn: o.pgn, startFen: o.startFen, userColor: o.userColor, ratingDelta: delta, ucis: o.ucis,
    );
    storage.saveHistory(history); _pushSoon();
    notifyListeners();
  }

  void _achieve(String id) => stats.achievements.add(id);

  void unlock(String id) {
    if (stats.achievements.add(id)) {
      storage.saveStats(stats); _pushSoon();
      notifyListeners();
    }
  }

  void solvePuzzle(String id, int points) {
    if (stats.solved.add(id)) {
      stats.puzzlePoints += points;
      _queue(_pendingPuzzles, 'pendingPuzzles', {'id': id, 'p': points});
      if (stats.solved.length >= 5) _achieve('puzzles_5');
      if (stats.solved.length >= totalPuzzles) _achieve('puzzles_all');
      storage.saveStats(stats); _pushSoon();
      notifyListeners();
    }
  }
}

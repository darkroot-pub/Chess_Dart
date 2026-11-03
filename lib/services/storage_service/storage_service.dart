import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';

class StorageService {
  late SharedPreferences _p;
  Future<void> init() async => _p = await SharedPreferences.getInstance();

  AppSettings loadSettings() {
    try {
      final s = _p.getString('settings');
      return s == null ? AppSettings() : AppSettings.fromJson(jsonDecode(s));
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings s) => _p.setString('settings', jsonEncode(s.toJson()));

  PlayerStats loadStats() {
    try {
      final s = _p.getString('stats');
      return s == null ? PlayerStats() : PlayerStats.fromJson(jsonDecode(s));
    } catch (_) {
      return PlayerStats();
    }
  }

  Future<void> saveStats(PlayerStats s) => _p.setString('stats', jsonEncode(s.toJson()));

  List<GameRecord> loadHistory() {
    try {
      final s = _p.getString('history');
      if (s == null) return [];
      return (jsonDecode(s) as List).map((e) => GameRecord.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHistory(List<GameRecord> h) =>
      _p.setString('history', jsonEncode(h.take(200).map((e) => e.toJson()).toList()));

  // ---- cached game analyses (local only, newest 40 kept) ----
  List<String> analysisIndex() => _p.getStringList('an_index') ?? [];
  String? loadAnalysisJson(String id) => _p.getString('an_$id');
  Future<void> saveAnalysisJson(String id, String json) async {
    final idx = analysisIndex()..remove(id)..add(id);
    while (idx.length > 40) {
      await _p.remove('an_${idx.removeAt(0)}');
    }
    await _p.setString('an_$id', json);
    await _p.setStringList('an_index', idx);
  }

  SavedGame? loadSavedGame() => SavedGame.decode(_p.getString('savedGame'));
  Future<void> saveSavedGame(SavedGame? g) async {
    if (g == null) {
      await _p.remove('savedGame');
    } else {
      await _p.setString('savedGame', g.encode());
    }
  }

  /// Events (finished games / solved puzzles) not yet acknowledged by the server.
  List<Map<String, dynamic>> loadPending(String key) {
    try {
      final s = _p.getString(key);
      if (s == null) return [];
      return (jsonDecode(s) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePending(String key, List<Map<String, dynamic>> v) => _p.setString(key, jsonEncode(v));

  bool get syncV2 => _p.getBool('syncV2') ?? false;
  Future<void> setSyncV2() => _p.setBool('syncV2', true);
  int get settingsTs => _p.getInt('settingsTs') ?? 0;
  Future<void> setSettingsTs(int v) => _p.setInt('settingsTs', v);

  String get lastEmail => _p.getString('lastEmail') ?? '';
  Future<void> setLastEmail(String e) => _p.setString('lastEmail', e);

  bool get uiV2 => _p.getBool('uiV2') ?? false;
  Future<void> setUiV2() => _p.setBool('uiV2', true);

  bool get onboarded => _p.getBool('onboarded') ?? false;
  Future<void> setOnboarded() => _p.setBool('onboarded', true);
}

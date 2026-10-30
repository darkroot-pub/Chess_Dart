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

  SavedGame? loadSavedGame() => SavedGame.decode(_p.getString('savedGame'));
  Future<void> saveSavedGame(SavedGame? g) async {
    if (g == null) {
      await _p.remove('savedGame');
    } else {
      await _p.setString('savedGame', g.encode());
    }
  }

  bool get onboarded => _p.getBool('onboarded') ?? false;
  Future<void> setOnboarded() => _p.setBool('onboarded', true);
}

import 'package:flutter/material.dart';

class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  /// OAuth *Web application* client ID (used by native Google sign-in to mint the ID token).
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static bool get configured => url.isNotEmpty && anonKey.isNotEmpty;
}

const List<String> kPieceSets = [
  'lowpoly3d', 'cburnett', 'merida', 'alpha', 'staunty', 'cardinal', 'governor', 'california', 'caliente', 'anarcandy',
  'celtic', 'chess7', 'chessnut', 'companion', 'cooke', 'dubrovny', 'fantasy', 'firi', 'fresca', 'gioco',
  'horsey', 'icpieces', 'pixel', 'spatial',
];

class BoardTheme {
  final String name;
  final Color light, dark;
  const BoardTheme(this.name, this.light, this.dark);
}

const List<BoardTheme> kBoardThemes = [
  BoardTheme('Wood', Color(0xFFF0D9B5), Color(0xFFB58863)),
  BoardTheme('Green', Color(0xFFEEEED2), Color(0xFF769656)),
  BoardTheme('Blue', Color(0xFFDEE3E6), Color(0xFF8CA2AD)),
  BoardTheme('Royal', Color(0xFFE8F0FF), Color(0xFF6B93D6)),
  BoardTheme('Walnut', Color(0xFFE2C9A0), Color(0xFF8B5E3C)),
  BoardTheme('Slate', Color(0xFFE5E7EB), Color(0xFF9CA3AF)),
  BoardTheme('Ocean', Color(0xFFD9E5FB), Color(0xFF4A79D4)),
];

class TimeControl {
  final String category;
  final int minutes; // base
  final int inc; // seconds
  const TimeControl(this.category, this.minutes, this.inc);
  String get label => '$minutes min${inc > 0 ? ' + $inc' : ''}';
  int get baseMs => minutes * 60 * 1000;
  int get incMs => inc * 1000;
  bool get untimed => minutes == 0;
}

const List<TimeControl> kTimeControls = [
  TimeControl('Bullet', 1, 0),
  TimeControl('Bullet', 2, 1),
  TimeControl('Blitz', 3, 0),
  TimeControl('Blitz', 3, 2),
  TimeControl('Blitz', 5, 0),
  TimeControl('Rapid', 10, 0),
  TimeControl('Rapid', 15, 10),
  TimeControl('Classical', 30, 0),
  TimeControl('Classical', 60, 0),
  TimeControl('Unlimited', 0, 0),
];

class AiLevel {
  final String name;
  final int rating; // approx. opponent rating for Elo bookkeeping
  final int? uciElo; // null = full strength
  final int skill;
  final int movetime;
  final int? depth;
  const AiLevel(this.name, this.rating, this.uciElo, this.skill, this.movetime, this.depth);
}

const List<AiLevel> kAiLevels = [
  AiLevel('Easy', 800, null, 0, 60, 1),
  AiLevel('Medium', 1400, 1400, 6, 300, null),
  AiLevel('Hard', 1900, 1900, 14, 600, null),
  AiLevel('Expert', 2600, null, 20, 1200, null),
];

String fmtClock(int ms) {
  if (ms < 0) ms = 0;
  if (ms < 10000) return '0:${(ms / 1000).toStringAsFixed(1).padLeft(4, '0')}';
  final s = (ms / 1000).ceil();
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

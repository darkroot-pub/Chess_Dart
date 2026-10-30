import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../widgets/cards/common.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final st = app.stats;
    Widget stat(String label, String v) => Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 10, right: 5, left: 5),
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: C.text2, fontSize: 12)), const SizedBox(height: 4), Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))]),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), actions: [
        IconButton(icon: const Icon(Icons.leaderboard_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()))),
        IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
      ]),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Avatar(st.username, size: 76),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(st.username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                IconButton(icon: const Icon(Icons.edit, size: 18, color: C.text2), onPressed: () => _rename(context, app)),
              ]),
              Text('${st.rating}', style: const TextStyle(fontSize: 18, color: C.text2, fontWeight: FontWeight.w700)),
              Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: C.softBlue, borderRadius: BorderRadius.circular(10)), child: Text(st.level, style: const TextStyle(color: C.primary, fontWeight: FontWeight.w700, fontSize: 12))),
            ])),
          ]),
          const SizedBox(height: 16),
          Row(children: [stat('Games Played', '${st.played}'), stat('Win Rate', '${st.winRate}%')]),
          Row(children: [stat('Total Wins', '${st.wins}'), stat('Total Losses', '${st.losses}')]),
          Row(children: [stat('Draws', '${st.draws}'), stat('Puzzle points', '${st.puzzlePoints}')]),
          const SizedBox(height: 8),
          const Text('Achievements', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in kAchievements)
              Tooltip(
                message: a.desc,
                child: Container(
                  width: 104,
                  padding: const EdgeInsets.all(10),
                  decoration: cardDeco(color: st.achievements.contains(a.id) ? C.softBlue : C.surface),
                  child: Column(children: [
                    Icon(a.icon, color: st.achievements.contains(a.id) ? C.primary : C.border, size: 28),
                    const SizedBox(height: 4),
                    Text(a.title, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: st.achievements.contains(a.id) ? C.text : C.text2)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          const Text('Recent Activity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          if (app.history.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No games yet. Play your first game!', style: TextStyle(color: C.text2))),
          for (final r in app.history.take(30))
            AppCard(
              padding: const EdgeInsets.all(10),
              onTap: r.ucis.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(record: r))),
              child: Row(children: [
                Icon(r.outcome == 1 ? Icons.emoji_events : (r.outcome == 0 ? Icons.handshake : Icons.close), color: r.outcome == 1 ? C.success : (r.outcome == 0 ? C.warning : C.error)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r.outcome == 1 ? 'Won' : (r.outcome == 0 ? 'Draw' : 'Lost')} vs ${r.opponent}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${r.reason} · ${r.date.substring(0, 10)}', style: const TextStyle(color: C.text2, fontSize: 12)),
                ])),
                if (r.mode == 'ai') Text('${r.ratingDelta >= 0 ? '+' : ''}${r.ratingDelta} ELO', style: TextStyle(fontWeight: FontWeight.w800, color: r.ratingDelta >= 0 ? C.success : C.error, fontSize: 12.5)),
                const Icon(Icons.analytics_outlined, size: 18, color: C.text2),
              ]),
            ),
        ]),
      ),
    );
  }

  Future<void> _rename(BuildContext context, AppState app) async {
    final c = TextEditingController(text: app.stats.username);
    final n = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Username'),
        content: TextField(controller: c, maxLength: 20, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save'))],
      ),
    );
    if (n != null) app.setUsername(n);
  }
}

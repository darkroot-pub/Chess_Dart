import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/multiplayer_service/supabase_service.dart';
import '../../widgets/cards/common.dart';
import '../../widgets/cards/ui_kit.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final st = app.stats;
    final sb = SupabaseService.instance;
    // progress inside the current level band
    final bands = [(800, 1200, 'Beginner'), (1200, 1700, 'Intermediate'), (1700, 2400, 'Advanced')];
    final band = st.rating < 1200 ? bands[0] : (st.rating < 1700 ? bands[1] : bands[2]);
    final prog = ((st.rating - band.$1) / (band.$2 - band.$1)).clamp(0.0, 1.0);
    final nextLabel = st.rating < 1200 ? 'Intermediate at 1200' : (st.rating < 1700 ? 'Advanced at 1700' : 'Top level');
    int i = 0;
    Widget r(Widget w) => Reveal(index: i++, child: w);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, 0.3], colors: [Color(0xFFDCE6FF), C.bg])),
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
            r(Row(children: [
              const Expanded(child: Text('Profile', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5))),
              IconButton(icon: const Icon(Icons.leaderboard_outlined), style: IconButton.styleFrom(backgroundColor: Colors.white), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()))),
              const SizedBox(width: 6),
              IconButton(icon: const Icon(Icons.settings_outlined), style: IconButton.styleFrom(backgroundColor: Colors.white), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
            ])),
            const SizedBox(height: 12),
            r(Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B1B4A), Color(0xFF2563EB)]),
                boxShadow: const [BoxShadow(color: Color(0x442563EB), blurRadius: 22, offset: Offset(0, 10))],
              ),
              child: Column(children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
                    child: Avatar(st.username, size: 76, url: app.avatarUrl),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(st.username, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Colors.white), overflow: TextOverflow.ellipsis)),
                        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit, size: 18, color: Colors.white70), onPressed: () => _rename(context, app)),
                      ]),
                      if (app.email != null && app.email!.isNotEmpty) Text(app.email!, style: const TextStyle(fontSize: 12.5, color: Colors.white70), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(12)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.workspace_premium, color: Color(0xFFFCD34D), size: 16),
                          const SizedBox(width: 5),
                          Text('${st.rating} · ${band.$3}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        ]),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: prog),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 9, backgroundColor: Colors.white24, color: const Color(0xFFFCD34D)),
                  ),
                ),
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: Text(nextLabel, style: const TextStyle(color: Colors.white70, fontSize: 12))),
              ]),
            )),
            const SizedBox(height: 14),
            r(Row(children: [
              Expanded(child: StatTile(icon: Icons.sports_esports, color: C.primary, value: '${st.played}', label: 'Games')),
              const SizedBox(width: 10),
              Expanded(child: StatTile(icon: Icons.percent, color: const Color(0xFF8B5CF6), value: '${st.winRate}%', label: 'Win rate')),
            ])),
            const SizedBox(height: 10),
            r(Row(children: [
              Expanded(child: StatTile(icon: Icons.emoji_events, color: C.success, value: '${st.wins}', label: 'Wins')),
              const SizedBox(width: 10),
              Expanded(child: StatTile(icon: Icons.close_rounded, color: C.error, value: '${st.losses}', label: 'Losses')),
            ])),
            const SizedBox(height: 10),
            r(Row(children: [
              Expanded(child: StatTile(icon: Icons.handshake, color: C.warning, value: '${st.draws}', label: 'Draws')),
              const SizedBox(width: 10),
              Expanded(child: StatTile(icon: Icons.star, color: const Color(0xFFEC4899), value: '${st.puzzlePoints}', label: 'Puzzle points')),
            ])),
            if (sb.available && sb.signedIn) ...[
              const SizedBox(height: 12),
              r(Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                decoration: cardDeco(radius: 18),
                child: Row(children: [
                  Icon(app.syncStatus.startsWith('Cloud') ? Icons.cloud_off : Icons.cloud_done_outlined, color: app.syncStatus.startsWith('Cloud') ? C.error : C.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(app.syncStatus.isEmpty ? 'Progress is saved to your account' : app.syncStatus, style: const TextStyle(fontSize: 12.5, color: C.text2))),
                  TextButton(onPressed: () => app.syncProfile(), child: const Text('Sync now')),
                ]),
              )),
            ],
            r(SectionTitle('Achievements', trailing: Text('${st.achievements.length}/${kAchievements.length}', style: const TextStyle(color: C.text2, fontWeight: FontWeight.w700)))),
            r(GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.0,
              children: [
                for (final a in kAchievements)
                  GestureDetector(
                    onTap: () => snack(context, '${a.title}: ${a.desc}'),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: st.achievements.contains(a.id)
                          ? BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFDCE6FF), Colors.white]), border: Border.all(color: C.primary.withAlpha(90)), boxShadow: const [BoxShadow(color: Color(0x222563EB), blurRadius: 10, offset: Offset(0, 4))])
                          : cardDeco(radius: 18, color: const Color(0xFFF1F4FA)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(st.achievements.contains(a.id) ? a.icon : Icons.lock_outline, color: st.achievements.contains(a.id) ? C.primary : C.border, size: 30),
                        const SizedBox(height: 6),
                        Text(a.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: st.achievements.contains(a.id) ? C.text : C.text2)),
                      ]),
                    ),
                  ),
              ],
            )),
            r(const SectionTitle('Recent activity')),
            if (app.history.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No games yet. Play your first game!', style: TextStyle(color: C.text2))),
            for (final g in app.history.take(30))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Pressable(
                  onTap: g.ucis.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(record: g))),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: cardDeco(radius: 18),
                    child: Row(children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(color: (g.outcome == 1 ? C.success : (g.outcome == 0 ? C.warning : C.error)).withAlpha(28), borderRadius: BorderRadius.circular(14)),
                        child: Icon(g.outcome == 1 ? Icons.emoji_events : (g.outcome == 0 ? Icons.handshake : Icons.close), color: g.outcome == 1 ? C.success : (g.outcome == 0 ? C.warning : C.error)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${g.outcome == 1 ? 'Won' : (g.outcome == 0 ? 'Draw' : 'Lost')} vs ${g.opponent}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('${g.reason} · ${g.date.substring(0, 10)}', style: const TextStyle(color: C.text2, fontSize: 12)),
                        ]),
                      ),
                      if (g.mode == 'ai') Text('${g.ratingDelta >= 0 ? '+' : ''}${g.ratingDelta}', style: TextStyle(fontWeight: FontWeight.w900, color: g.ratingDelta >= 0 ? C.success : C.error)),
                      const SizedBox(width: 6),
                      const Icon(Icons.analytics_outlined, size: 18, color: C.text2),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
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

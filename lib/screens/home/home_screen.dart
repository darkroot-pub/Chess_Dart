import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/puzzles.dart';
import '../../providers/app_state.dart';
import '../../services/multiplayer_service/supabase_service.dart';
import '../../widgets/cards/common.dart';
import '../../widgets/cards/ui_kit.dart';
import '../../widgets/chessboard/chess_board.dart';
import '../character/character_screen.dart';
import '../game/game_screen.dart';
import '../../widgets/cards/character_viewer.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../learn/learn_screen.dart';
import '../multiplayer/online_hub_screen.dart';
import '../puzzles/puzzles_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int tab) goTab;
  const HomeScreen({super.key, required this.goTab});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstRun());
  }

  Future<void> _firstRun() async {
    final app = context.read<AppState>();
    if (app.storage.onboarded) return;
    await app.storage.setOnboarded();
    if (!mounted) return;
    final md = SupabaseService.instance.user?.userMetadata;
    final c = TextEditingController(text: '${md?['full_name'] ?? md?['name'] ?? ''}');
    final n = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Welcome to DarkChess'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Choose a username. Your rating starts at 1200.'),
          const SizedBox(height: 10),
          TextField(controller: c, maxLength: 20, decoration: const InputDecoration(hintText: 'Username', border: OutlineInputBorder())),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Start'))],
      ),
    );
    if (n != null) app.setUsername(n);
  }

  void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final st = app.stats;
    final sv = app.saved;
    final daily = dailyPuzzle();
    final dailyDone = st.solved.contains(daily.id);
    final sb = SupabaseService.instance;
    final online = sb.available && sb.signedIn;
    int i = 0;
    Widget r(Widget w) => Reveal(index: i++, child: w);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, 0.35], colors: [Color(0xFFDCE6FF), C.bg])),
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 16), children: [
            r(Row(children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [C.primary, C.secondary])),
                child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white), child: Avatar(st.username, size: 46, url: app.avatarUrl)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_greeting, style: const TextStyle(color: C.text2, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(st.username, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 21, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
                ]),
              ),
              IconButton(onPressed: () => push(const SettingsScreen()), icon: const Icon(Icons.settings_outlined), style: IconButton.styleFrom(backgroundColor: Colors.white)),
            ])),
            const SizedBox(height: 16),
            r(BannerCard(
              image: 'assets/images/banner_play.jpg',
              title: 'Play Now',
              subtitle: 'Start a new game vs AI\nor a friend',
              height: 168,
              cta: 'Start',
              onTap: () => widget.goTab(1),
            )),
            r(Row(children: [
              Expanded(child: StatTile(icon: Icons.workspace_premium, color: C.warning, value: '${st.rating}', label: 'Rating')),
              const SizedBox(width: 10),
              Expanded(child: StatTile(icon: Icons.emoji_events, color: C.success, value: '${st.wins}', label: 'Wins')),
            ])),
            const SizedBox(height: 10),
            r(Row(children: [
              Expanded(child: StatTile(icon: Icons.percent, color: C.primary, value: '${st.winRate}%', label: 'Win rate')),
              const SizedBox(width: 10),
              Expanded(child: StatTile(icon: Icons.star, color: const Color(0xFF8B5CF6), value: '${st.puzzlePoints}', label: 'Puzzle points')),
            ])),
            if (sv != null) ...[
              const SizedBox(height: 12),
              r(Pressable(
                onTap: () => push(GameScreen(mode: sv.mode, humanColor: sv.userColor, aiLevel: sv.aiLevel, tcIndex: sv.tcIndex, resume: sv)),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: cardDeco(radius: 20),
                  child: Row(children: [
                    const IconBubble(Icons.play_circle_fill, color: C.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Continue your game', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('${sv.ucis.length} moves played · ${sv.mode == 'ai' ? 'vs AI' : 'Pass & Play'}', style: const TextStyle(color: C.text2, fontSize: 12.5)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right, color: C.text2),
                  ]),
                ),
              )),
            ],
            r(const SectionTitle('Play')),
            r(BannerCard(
              image: 'assets/images/banner_online.jpg',
              title: 'Online Multiplayer',
              subtitle: 'Friends, challenges & ranked',
              badge: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withAlpha(235), borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: online ? C.success : C.text2), const SizedBox(width: 5), Text(online ? 'Online' : 'Sign in', style: TextStyle(color: online ? C.success : C.text2, fontSize: 11.5, fontWeight: FontWeight.w800))]),
              ),
              onTap: () => push(const OnlineHubScreen()),
            )),
            r(BannerCard(image: 'assets/images/banner_ai.jpg', title: 'vs Stockfish AI', subtitle: 'Four levels, works offline', onTap: () => widget.goTab(1))),
            r(const SectionTitle('Daily puzzle')),
            r(Pressable(
              onTap: () => push(PuzzleScreen(puzzle: daily)),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: cardDeco(radius: 22),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 96, child: MiniBoard(daily.fen, pieceSet: app.settings.pieceSet, theme: app.boardTheme))),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(daily.category, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text('${daily.title} · ${daily.difficulty}', style: const TextStyle(color: C.text2, fontSize: 12.5)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: dailyDone ? C.success.withAlpha(28) : C.primary, borderRadius: BorderRadius.circular(16)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(dailyDone ? Icons.check_circle : Icons.bolt, size: 16, color: dailyDone ? C.success : Colors.white),
                          const SizedBox(width: 5),
                          Text(dailyDone ? 'Completed' : 'Solve +${daily.points}', style: TextStyle(color: dailyDone ? C.success : Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        ]),
                      ),
                    ]),
                  ),
                ]),
              ),
            )),
            const SizedBox(height: 12),
            r(Pressable(
              onTap: () => push(const CharacterScreen()),
              child: Container(
                height: 150,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFF3B2A7A), Color(0xFF6D4AD8)]), boxShadow: const [BoxShadow(color: Color(0x336D4AD8), blurRadius: 18, offset: Offset(0, 8))]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(children: [
                    Positioned(right: -6, top: 4, bottom: 0, child: Image.asset(CharacterViewer.frame(0), fit: BoxFit.contain)),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 14, 150, 14),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Meet your Guardian', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                        SizedBox(height: 3),
                        Text('Rotate and explore in 3D', style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 13)),
                      ]),
                    ),
                  ]),
                ),
              ),
            )),
            r(Row(children: [
              Expanded(child: BannerCard(image: 'assets/images/banner_puzzles.jpg', title: 'Puzzles', subtitle: 'Sharpen tactics', height: 120, onTap: () => widget.goTab(2))),
              const SizedBox(width: 10),
              Expanded(child: BannerCard(image: 'assets/images/banner_learn.jpg', title: 'Learn', subtitle: 'Lessons & tips', height: 120, onTap: () => push(const LearnScreen()))),
            ])),
            r(Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => widget.goTab(3), icon: const Icon(Icons.bar_chart), label: const Text('Statistics'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () => push(const LeaderboardScreen()), icon: const Icon(Icons.leaderboard), label: const Text('Ranks'))),
            ])),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/chess_service/chess_game.dart';
import '../../widgets/cards/common.dart';
import '../../widgets/chessboard/chess_board.dart';
import '../game/game_screen.dart';
import '../game/play_setup_screen.dart';
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
    final c = TextEditingController();
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final st = app.stats;
    final sv = app.saved;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            const Spacer(),
            RichText(text: const TextSpan(children: [TextSpan(text: 'Dark', style: TextStyle(color: C.text, fontSize: 24, fontWeight: FontWeight.w800)), TextSpan(text: 'Chess', style: TextStyle(color: C.primary, fontSize: 24, fontWeight: FontWeight.w800))])),
            const Spacer(),
          ]),
          const SizedBox(height: 14),
          AppCard(
            child: Row(children: [
              Avatar(st.username, size: 46),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hello, ${st.username}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const Text('Ready for your next move?', style: TextStyle(color: C.text2, fontSize: 13)),
              ])),
              Column(children: [const Icon(Icons.workspace_premium, color: C.warning), Text('${st.rating}', style: const TextStyle(fontWeight: FontWeight.w800))]),
            ]),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => widget.goTab(1),
            child: Container(
              height: 110,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [C.primary, C.secondary]), boxShadow: const [BoxShadow(color: Color(0x332563EB), blurRadius: 16, offset: Offset(0, 6))]),
              child: Row(children: [
                const Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Play Now', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                  Text('Start a new game', style: TextStyle(color: Colors.white70)),
                ])),
                PieceImage(makePiece(kQ, kWhite), app.settings.pieceSet, 70),
                PieceImage(makePiece(kN, kWhite), app.settings.pieceSet, 56),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (sv != null)
            NavTile(
              icon: Icons.play_circle_fill,
              color: C.success,
              title: 'Resume game',
              subtitle: '${sv.ucis.length} moves played · ${sv.mode == 'ai' ? 'vs AI' : 'Pass & Play'}',
              onTap: () => push(GameScreen(mode: sv.mode, humanColor: sv.userColor, aiLevel: sv.aiLevel, tcIndex: sv.tcIndex, resume: sv)),
            ),
          NavTile(icon: Icons.public, title: 'Online Multiplayer', subtitle: 'Play with real players', onTap: () => push(const OnlineHubScreen())),
          NavTile(icon: Icons.smart_toy, title: 'vs AI', subtitle: 'Challenge Stockfish offline', onTap: () => push(const PlaySetupScreen(initialMode: 'ai', showBack: true))),
          NavTile(icon: Icons.extension, color: C.success, title: 'Puzzles', subtitle: 'Improve your tactics', onTap: () => push(const PuzzlesScreen())),
          NavTile(icon: Icons.menu_book, title: 'Learn', subtitle: 'Lessons & tips', onTap: () => push(const LearnScreen())),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => widget.goTab(3), icon: const Icon(Icons.bar_chart), label: const Text('Statistics'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => push(const LeaderboardScreen()), icon: const Icon(Icons.leaderboard), label: const Text('Ranks'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => push(const SettingsScreen()), icon: const Icon(Icons.settings), label: const Text('Settings'))),
          ]),
        ]),
      ),
    );
  }
}

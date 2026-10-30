import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/chess_service/chess_game.dart';
import '../../widgets/cards/common.dart';
import '../multiplayer/online_hub_screen.dart';
import 'game_screen.dart';

/// Game settings + start screen. Used for the "Play" tab and for "vs AI".
class PlaySetupScreen extends StatefulWidget {
  final String initialMode; // 'ai' | 'local'
  final bool showBack;
  const PlaySetupScreen({super.key, this.initialMode = 'ai', this.showBack = false});
  @override
  State<PlaySetupScreen> createState() => _PlaySetupScreenState();
}

class _PlaySetupScreenState extends State<PlaySetupScreen> {
  late String mode = widget.initialMode;
  int level = 1, color = 2, tc = 5; // color: 0 white, 1 black, 2 random

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final saved = app.saved;
    Widget chip(String t, bool sel, VoidCallback f) => ChoiceChip(
          label: Text(t),
          selected: sel,
          onSelected: (_) => f(),
          selectedColor: C.primary,
          labelStyle: TextStyle(color: sel ? Colors.white : C.text, fontWeight: FontWeight.w600),
          backgroundColor: C.softBlue,
          side: BorderSide.none,
          showCheckmark: false,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Game Settings'), automaticallyImplyLeading: widget.showBack),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (saved != null)
            AppCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GameScreen(mode: saved.mode, humanColor: saved.userColor, aiLevel: saved.aiLevel, tcIndex: saved.tcIndex, resume: saved))),
              child: Row(children: [
                const IconBubble(Icons.play_circle_fill, color: C.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Resume saved game', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('${saved.ucis.length} moves played · ${saved.mode == 'ai' ? 'vs AI' : 'Pass & Play'}', style: const TextStyle(color: C.text2, fontSize: 12.5)),
                  ]),
                ),
                IconButton(icon: const Icon(Icons.delete_outline, color: C.text2), onPressed: () => app.setSaved(null)),
              ]),
            ),
          const Text('Game mode', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            chip('vs AI (offline)', mode == 'ai', () => setState(() => mode = 'ai')),
            chip('Pass & Play', mode == 'local', () => setState(() => mode = 'local')),
          ]),
          const SizedBox(height: 10),
          NavTile(
            icon: Icons.public,
            title: 'Online Multiplayer',
            subtitle: 'Play with real players (needs Supabase)',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnlineHubScreen())),
          ),
          if (mode == 'ai') ...[
            const Text('Difficulty', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [for (int i = 0; i < kAiLevels.length; i++) chip('${kAiLevels[i].name} · ${kAiLevels[i].rating}', level == i, () => setState(() => level = i))]),
            const SizedBox(height: 14),
            const Text('Play as', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              chip('White', color == 0, () => setState(() => color = 0)),
              chip('Black', color == 1, () => setState(() => color = 1)),
              chip('Random', color == 2, () => setState(() => color = 2)),
            ]),
          ],
          const SizedBox(height: 14),
          const Text('Time control', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (int i = 0; i < kTimeControls.length; i++) chip(kTimeControls[i].untimed ? 'Unlimited' : kTimeControls[i].label, tc == i, () => setState(() => tc = i)),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(kTimeControls[tc].untimed ? 'No clock' : '${kTimeControls[tc].category} · ${kTimeControls[tc].label}', style: const TextStyle(color: C.text2, fontSize: 12.5)),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(children: [
              SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, title: const Text('Sound'), value: s.sound, onChanged: (v) => app.updateSettings((x) => x.sound = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, title: const Text('Show legal moves'), value: s.showLegal, onChanged: (v) => app.updateSettings((x) => x.showLegal = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, title: const Text('Auto queen'), value: s.autoQueen, onChanged: (v) => app.updateSettings((x) => x.autoQueen = v)),
            ]),
          ),
          const SizedBox(height: 6),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Game'),
            onPressed: () {
              final human = color == 2 ? Random().nextInt(2) : color;
              app.setSaved(null);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(mode: mode, humanColor: mode == 'ai' ? human : kWhite, aiLevel: level, tcIndex: tc)));
            },
          ),
        ]),
      ),
    );
  }
}

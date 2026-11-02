import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/chess_service/chess_game.dart';
import '../../widgets/chessboard/chess_board.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const SafeArea(child: SingleChildScrollView(padding: EdgeInsets.all(16), child: SettingsPanel())),
      );
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    Widget sw(String t, bool v, void Function(bool) f, IconData i) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(i, color: C.primary),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
          value: v,
          onChanged: (x) => app.updateSettings((_) => f(x)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      sw('Sound', s.sound, (v) => s.sound = v, Icons.volume_up),
      sw('Vibration', s.vibration, (v) => s.vibration = v, Icons.vibration),
      sw('Show legal moves', s.showLegal, (v) => s.showLegal = v, Icons.circle_outlined),
      sw('Auto queen', s.autoQueen, (v) => s.autoQueen = v, Icons.workspace_premium),
      sw('Board coordinates', s.coords, (v) => s.coords = v, Icons.grid_on),
      sw('Piece move animation', s.animateMoves, (v) => s.animateMoves = v, Icons.animation),
      sw('Highlight last move', s.highlightLast, (v) => s.highlightLast = v, Icons.highlight_alt),
      const Padding(padding: EdgeInsets.only(top: 10, bottom: 2), child: Text('Guardian (Kindred)', style: TextStyle(fontWeight: FontWeight.w800, color: C.primary))),
      sw('Comments in games vs AI', s.guardianChat, (v) => s.guardianChat = v, Icons.chat_bubble_outline),
      sw('Coaching in puzzles', s.guardianPuzzles, (v) => s.guardianPuzzles = v, Icons.psychology_alt_outlined),
      sw('Guardian auto-rotates', s.guardianSpin, (v) => s.guardianSpin = v, Icons.threed_rotation),
      const SizedBox(height: 8),
      const Text('Board theme', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      SizedBox(
        height: 62,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (int i = 0; i < kBoardThemes.length; i++)
            GestureDetector(
              onTap: () => app.updateSettings((x) => x.boardTheme = i),
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                width: 62,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: s.boardTheme == i ? C.primary : C.border, width: s.boardTheme == i ? 3 : 1)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Column(children: [
                    for (int r = 0; r < 2; r++)
                      Expanded(
                        child: Row(children: [
                          for (int c = 0; c < 2; c++) Expanded(child: ColoredBox(color: (r + c) % 2 == 0 ? kBoardThemes[i].light : kBoardThemes[i].dark, child: const SizedBox.expand())),
                        ]),
                      ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      const Text('Piece style', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      SizedBox(
        height: 84,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final name in kPieceSets)
            GestureDetector(
              onTap: () => app.updateSettings((x) => x.pieceSet = name),
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                width: 82,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: app.boardTheme.light, borderRadius: BorderRadius.circular(12), border: Border.all(color: s.pieceSet == name ? C.primary : C.border, width: s.pieceSet == name ? 3 : 1)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [PieceImage(makePiece(kN, kWhite), name, 32), PieceImage(makePiece(kN, kBlack), name, 32)]),
                  Text(name == 'lowpoly3d' ? '3D Low-poly' : (name[0].toUpperCase() + name.substring(1)), style: const TextStyle(fontSize: 10, color: C.text, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 18),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.info_outline, color: C.primary),
        title: const Text('Credits & licenses', style: TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => showDialog(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Credits'),
            content: const SingleChildScrollView(
              child: Text(
                '3D chess pieces and board art are based on "Low Poly Chess Set" by hanoldaa '
                '(https://sketchfab.com/3d-models/low-poly-chess-set-0f440e2b01ca42f8b3fdee8178c51f20), '
                'licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). '
                'Images were rendered from the model.\n\n'
                'Guardian character: "Spirit Blossom Kindred" (https://sketchfab.com/3d-models/spirit-blossom-kindred-85187f9f246f4702b7c137dcc6c0fc12) '
                'by Retronous (https://sketchfab.com/Retronous) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/). Rendered to turntable frames.\n\n'
                'Other piece sets: lichess.org (see their licenses). Dark Chess AI is powered by the open-source Stockfish engine (GPLv3, https://stockfishchess.org).',
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
          ),
        ),
      ),
    ]);
  }
}

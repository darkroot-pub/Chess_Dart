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
        height: 74,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final name in kPieceSets)
            GestureDetector(
              onTap: () => app.updateSettings((x) => x.pieceSet = name),
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                width: 74,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: app.boardTheme.light, borderRadius: BorderRadius.circular(12), border: Border.all(color: s.pieceSet == name ? C.primary : C.border, width: s.pieceSet == name ? 3 : 1)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [PieceImage(makePiece(kN, kWhite), name, 28), PieceImage(makePiece(kN, kBlack), name, 28)]),
                  Text(name, style: const TextStyle(fontSize: 9, color: C.text), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }
}

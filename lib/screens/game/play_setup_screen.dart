import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/chess_service/chess_game.dart';
import '../../services/multiplayer_service/supabase_service.dart';
import '../../widgets/cards/common.dart';
import '../../widgets/chessboard/chess_board.dart';
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

const _levelDesc = ['A great start for beginners', 'A balanced challenge', 'For experienced players', 'Full-strength Stockfish'];

class _PlaySetupScreenState extends State<PlaySetupScreen> {
  late String mode = widget.initialMode;
  int level = 0, color = 2, tc = 5; // color: 0 white, 1 black, 2 random

  Widget _title(IconData icon, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(children: [Icon(icon, size: 22, color: C.text), const SizedBox(width: 12), Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))]),
      );

  Widget _pill(String label, bool sel, VoidCallback onTap, {IconData? icon, Widget? leading}) {
    final lead = leading ?? (icon == null ? null : Icon(icon, size: 20, color: sel ? Colors.white : C.primary));
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(horizontal: sel || lead != null ? 18 : 20, vertical: 12),
        decoration: BoxDecoration(
          color: sel ? C.primary : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: sel ? const Color(0x552563EB) : const Color(0x142563EB), blurRadius: sel ? 12 : 8, offset: const Offset(0, 3))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (lead != null) ...[lead, const SizedBox(width: 8)],
          Text(label, style: TextStyle(color: sel ? Colors.white : C.text, fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
      ),
    );
  }

  Widget _header(String set) => SizedBox(
        height: 250,
        child: Stack(clipBehavior: Clip.none, children: [
          // chess pieces from the selected piece set, as the hero artwork
          Positioned(right: -34, top: 6, child: Opacity(opacity: 0.18, child: PieceImage(makePiece(kP, kBlack), set, 120))),
          Positioned(right: 108, top: 40, child: Opacity(opacity: 0.32, child: PieceImage(makePiece(kB, kBlack), set, 110))),
          Positioned(right: 36, top: 30, child: Opacity(opacity: 0.55, child: PieceImage(makePiece(kQ, kBlack), set, 130))),
          Positioned(right: -6, top: -4, child: PieceImage(makePiece(kK, kBlack), set, 190)),
          Positioned(
            left: 4, top: 8,
            child: widget.showBack
                ? IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back), style: IconButton.styleFrom(backgroundColor: Colors.white70))
                : Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)]), boxShadow: const [BoxShadow(color: Color(0x552563EB), blurRadius: 14, offset: Offset(0, 6))]),
                    child: Center(child: PieceImage(makePiece(kN, kWhite), set, 42)),
                  ),
          ),
          const Positioned(
            left: 4, bottom: 22,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Game Settings', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              SizedBox(height: 4),
              Text('Customize your chess experience', style: TextStyle(fontSize: 16, color: C.text2)),
            ]),
          ),
        ]),
      );

  Widget _onlineCard() {
    final sb = SupabaseService.instance;
    final (label, col) = !sb.available ? ('Offline', C.text2) : (sb.signedIn ? ('Online', C.success) : ('Sign in', C.primary));
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnlineHubScreen())),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x1A2563EB), blurRadius: 16, offset: Offset(0, 6))]),
        child: Stack(children: [
          Row(children: [
            Image.asset('assets/images/earth.png', width: 74, height: 74, fit: BoxFit.contain),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(height: 6),
                Text('Online Multiplayer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                SizedBox(height: 6),
                Text('Play with real players,\nfriends & challenges', style: TextStyle(color: C.text2, fontSize: 14.5)),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 30, color: C.text),
          ]),
          Positioned(
            right: 30, top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: col.withAlpha(28), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 9, color: col), const SizedBox(width: 5), Text(label, style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 13))]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _difficulty() {
    Widget arrow(IconData i, VoidCallback f) => Material(
          color: Colors.white, shape: const CircleBorder(), elevation: 3, shadowColor: const Color(0x332563EB),
          child: InkWell(customBorder: const CircleBorder(), onTap: f, child: SizedBox(width: 52, height: 52, child: Icon(i, color: C.primary, size: 28))),
        );
    final n = kAiLevels.length;
    return Column(children: [
      Row(children: [
        arrow(Icons.chevron_left, () => setState(() => level = (level - 1 + n) % n)),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            height: 66,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(33), gradient: const LinearGradient(colors: [Color(0xFFDDE8FF), Colors.white, Color(0xFFDDE8FF)]), boxShadow: const [BoxShadow(color: Color(0x222563EB), blurRadius: 12, offset: Offset(0, 4))]),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.workspace_premium, color: C.text, size: 30),
              const SizedBox(width: 10),
              Text(kAiLevels[level].name, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
        const SizedBox(width: 14),
        arrow(Icons.chevron_right, () => setState(() => level = (level + 1) % n)),
      ]),
      const SizedBox(height: 8),
      Text(_levelDesc[level.clamp(0, _levelDesc.length - 1)], style: const TextStyle(color: C.text2, fontSize: 15)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final set = s.pieceSet;
    final saved = app.saved;
    final tcSel = kTimeControls[tc];
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, 0.3, 0.6], colors: [Color(0xFFDCE6FF), Color(0xFFEBF1FF), C.bg])),
        child: SafeArea(
          bottom: false,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            _header(set),
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
            _title(Icons.settings, 'Game mode'),
            Wrap(spacing: 12, runSpacing: 10, children: [
              _pill('vs AI (offline)', mode == 'ai', () => setState(() => mode = 'ai'), icon: Icons.psychology),
              _pill('Pass & Play', mode == 'local', () => setState(() => mode = 'local'), icon: Icons.people),
            ]),
            const SizedBox(height: 14),
            _onlineCard(),
            if (mode == 'ai') ...[
              _title(Icons.bar_chart, 'Difficulty'),
              _difficulty(),
              _title(Icons.person, 'Play as'),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _pill('White', color == 0, () => setState(() => color = 0), leading: PieceImage(makePiece(kK, kWhite), set, 24)),
                _pill('Black', color == 1, () => setState(() => color = 1), leading: PieceImage(makePiece(kK, kBlack), set, 24)),
                _pill('Random', color == 2, () => setState(() => color = 2), icon: Icons.casino),
              ]),
            ],
            _title(Icons.schedule, 'Time control'),
            Wrap(spacing: 10, runSpacing: 12, children: [
              for (int i = 0; i < kTimeControls.length; i++)
                _pill(kTimeControls[i].untimed ? 'Unlimited' : kTimeControls[i].label, tc == i, () => setState(() => tc = i),
                    icon: tc != i ? null : (kTimeControls[i].untimed ? Icons.all_inclusive : Icons.schedule)),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Row(children: [
                const Icon(Icons.bolt, color: C.primary, size: 20),
                const SizedBox(width: 6),
                Text(tcSel.untimed ? 'No clock' : tcSel.category, style: const TextStyle(color: C.primary, fontWeight: FontWeight.w600, fontSize: 15)),
                if (!tcSel.untimed) Text('  •  ${tcSel.label}', style: const TextStyle(color: C.text2, fontSize: 15)),
              ]),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x142563EB), blurRadius: 14, offset: Offset(0, 4))]),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(children: [
                SwitchListTile(secondary: const Icon(Icons.volume_up, color: C.text), title: const Text('Sound', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)), value: s.sound, onChanged: (v) => app.updateSettings((x) => x.sound = v)),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(secondary: const Icon(Icons.balance, color: C.text), title: const Text('Show legal moves', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)), value: s.showLegal, onChanged: (v) => app.updateSettings((x) => x.showLegal = v)),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(secondary: PieceImage(makePiece(kQ, kBlack), set, 26), title: const Text('Auto queen', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)), value: s.autoQueen, onChanged: (v) => app.updateSettings((x) => x.autoQueen = v)),
              ]),
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x662563EB), blurRadius: 18, offset: Offset(0, 8))]),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                icon: const Icon(Icons.play_arrow_rounded, size: 34),
                label: const Text('Start Game', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                onPressed: () {
                  final human = color == 2 ? Random().nextInt(2) : color;
                  app.setSaved(null);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(mode: mode, humanColor: mode == 'ai' ? human : kWhite, aiLevel: level, tcIndex: tc)));
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

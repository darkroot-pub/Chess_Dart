import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../providers/game_controller.dart';
import '../../services/chess_service/chess_game.dart';
import '../../widgets/cards/common.dart';
import '../../widgets/cards/guardian_widgets.dart';
import '../../widgets/chessboard/chess_board.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';

class GameScreen extends StatelessWidget {
  final String mode;
  final int humanColor, aiLevel, tcIndex;
  final SavedGame? resume;
  const GameScreen({super.key, required this.mode, required this.humanColor, this.aiLevel = 1, required this.tcIndex, this.resume});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return ChangeNotifierProvider(
      create: (_) => GameController(app, mode: mode, humanColor: humanColor, aiLevelIndex: aiLevel, tcIndex: tcIndex, resume: resume),
      child: const _GameView(),
    );
  }
}

class _GameView extends StatefulWidget {
  const _GameView();
  @override
  State<_GameView> createState() => _GameViewState();
}

class _GameViewState extends State<_GameView> {
  bool _dialogOpen = false;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    context.read<GameController>().askPromotion = _askPromotion;
  }

  Future<int?> _askPromotion(int color) {
    final set = context.read<AppState>().settings.pieceSet;
    return showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Promote pawn to'),
        content: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (final t in [kQ, kR, kB, kN])
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(context, t),
              child: Container(padding: const EdgeInsets.all(4), decoration: cardDeco(radius: 12), child: PieceImage(makePiece(t, color), set, 50)),
            ),
        ]),
      ),
    );
  }

  void _maybeShowOver(GameController c) {
    if (c.gameOverPending && !_dialogOpen) {
      c.gameOverPending = false;
      _dialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final rec = c.record;
        final delta = rec?.ratingDelta ?? 0;
        await showDialog<void>(
          context: context,
          builder: (dctx) => AlertDialog(
            backgroundColor: C.surface,
            title: Text(c.resultText, textAlign: TextAlign.center),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              if (c.mode == 'ai' && context.read<AppState>().settings.guardianChat) Padding(padding: const EdgeInsets.only(bottom: 10), child: GuardianTalk(text: c.guardianText, seq: c.guardianSeq)),
              Text(c.endReason, style: const TextStyle(color: C.text2)),
              if (c.mode == 'ai')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${delta >= 0 ? '+' : ''}$delta rating  →  ${context.read<AppState>().stats.rating}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: delta >= 0 ? C.success : C.error)),
                ),
            ]),
            actionsAlignment: MainAxisAlignment.center,
            actionsOverflowButtonSpacing: 6,
            actions: [
              if (rec != null && rec.ucis.isNotEmpty)
                FilledButton.icon(
                  icon: const Icon(Icons.analytics),
                  label: const Text('Game review'),
                  onPressed: () {
                    Navigator.pop(dctx);
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(record: rec)));
                  },
                ),
              TextButton(onPressed: () { Navigator.pop(dctx); Navigator.pop(context); }, child: const Text('New game')),
              TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Close')),
            ],
          ),
        );
        _dialogOpen = false;
      });
    }
  }

  Future<bool> _confirm(String title, String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: C.surface,
          title: Text(title),
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Yes')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final app = context.watch<AppState>();
    final s = app.settings;
    _maybeShowOver(c);
    final g = c.game;
    final topColor = c.flipped ? kWhite : kBlack, botColor = 1 - topColor;
    final last = g.lastMove;
    final bal = g.materialBalance();
    int adv(int color) => color == kWhite ? (bal > 0 ? bal : 0) : (bal < 0 ? -bal : 0);
    PlayerBar bar(int color) => PlayerBar(
          name: color == kWhite ? c.whiteName : c.blackName,
          sub: c.subFor(color),
          bot: c.mode == 'ai' && color != c.humanColor,
          guardian: c.mode == 'ai' && color != c.humanColor && s.guardianChat,
          clockMs: c.timeControl.untimed ? null : (color == kWhite ? c.whiteMs : c.blackMs),
          active: !c.over && g.turn == color && g.plyCount > 0,
          captured: g.capturedBy(color),
          pieceSet: s.pieceSet,
          advantage: adv(color),
        );
    final targets = (s.showLegal && c.selected != null) ? c.targets : <int>{};
    final status = c.over
        ? '${c.resultText} · ${c.endReason}'
        : c.paused
            ? 'Paused'
            : c.thinking
                ? 'Dark Chess AI is thinking…'
                : (c.hintText ?? (g.inCheck ? 'Check!' : (c.humanTurn ? 'Your move' : '')));

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.mode == 'ai' ? 'vs Dark Chess AI · ${c.level!.name}' : 'Pass & Play', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(c.timeControl.untimed ? 'Unlimited' : '${c.timeControl.label} · ${c.timeControl.category}', style: const TextStyle(fontSize: 12, color: C.text2)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy PGN',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: g.pgn(white: c.whiteName, black: c.blackName)));
              snack(context, 'PGN copied');
            },
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => showSheet(context, const SettingsPanel())),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            bar(topColor),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: app.boardTheme.dark, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x332563EB), blurRadius: 18, offset: Offset(0, 8))]),
              child: ClipRRect(borderRadius: BorderRadius.circular(13), child: RepaintBoundary(child:
            ChessBoardView(
              pieces: g.board,
              pieceSet: s.pieceSet,
              theme: app.boardTheme,
              flipped: c.flipped,
              coords: s.coords,
              animate: s.animateMoves,
              highlightLast: s.highlightLast,
              selected: c.selected,
              targets: targets,
              lastFrom: last?.from,
              lastTo: last?.to,
              checkSq: g.inCheck ? g.kingSquare(g.turn) : null,
              canDrag: c.canDrag,
              onTap: c.onTap,
              onDrop: c.onDrop,
              arrow: c.hint,
            ))),
            ),
            bar(botColor),
            SizedBox(
              height: 34,
              child: Row(children: [
                if (c.thinking) const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
                Expanded(
                  child: c.engineError
                      ? Row(children: [
                          const Icon(Icons.error_outline, size: 16, color: C.error),
                          const SizedBox(width: 6),
                          const Expanded(child: Text('Dark Chess AI could not start', style: TextStyle(color: C.error, fontSize: 13))),
                          TextButton(onPressed: c.retryEngine, child: const Text('Retry')),
                        ])
                      : Text(status, style: TextStyle(color: g.inCheck && !c.over ? C.error : C.text2, fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ]),
            ),
            if (c.mode == 'ai' && s.guardianChat) GuardianTalk(text: c.guardianText, seq: c.guardianSeq, onTap: c.chat),
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: cardDeco(radius: 18),
                child: g.sanList.isEmpty
                    ? const Center(child: Text('Moves will appear here', style: TextStyle(color: C.text2)))
                    : Builder(builder: (_) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
                        });
                        return SingleChildScrollView(
                          controller: _scroll,
                          child: Wrap(spacing: 10, runSpacing: 6, children: [
                            for (int i = 0; i < g.sanList.length; i++)
                              RichText(text: TextSpan(style: const TextStyle(color: C.text, fontSize: 14.5), children: [
                                if (i % 2 == 0) TextSpan(text: '${i ~/ 2 + 1}. ', style: const TextStyle(color: C.text2)),
                                TextSpan(text: g.sanList[i], style: TextStyle(fontWeight: i == g.sanList.length - 1 ? FontWeight.w900 : FontWeight.w600, color: i == g.sanList.length - 1 ? C.primary : C.text)),
                              ])),
                          ]),
                        );
                      }),
              ),
            ),
            Container(
              decoration: cardDeco(),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _Act(Icons.flag_outlined, 'Resign', c.over ? null : () async {
                  if (await _confirm('Resign?', 'You will lose this game.')) c.resign();
                }),
                _Act(Icons.lightbulb_outline, 'Hint', c.canPlay ? c.getHint : null),
                _Act(Icons.undo, 'Undo', (!c.over && g.plyCount > 0) ? c.undo : null),
                _Act(Icons.swap_vert, 'Flip', c.flip),
                _Act(Icons.handshake_outlined, 'Draw', c.over ? null : () async {
                  if (c.mode == 'ai') {
                    final msg = await c.offerDrawToAi();
                    if (mounted && msg.isNotEmpty) snack(context, msg);
                  } else if (await _confirm('Draw offer', 'Does the opponent accept the draw?')) {
                    c.agreeDraw();
                  }
                }),
                _Act(c.paused ? Icons.play_arrow : Icons.pause, c.paused ? 'Resume' : 'Pause', c.over ? null : c.togglePause),
              ]),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}

class _Act extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _Act(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap == null ? null : () { HapticFeedback.selectionClick(); onTap!(); },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44, height: 40,
            decoration: BoxDecoration(color: on ? C.softBlue : C.bg, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: on ? C.primary : C.border, size: 22),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 11, color: on ? C.text : C.border, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

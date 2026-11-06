import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/constants.dart';
import '../../services/chess_service/chess_game.dart';

/// Decode width for the 3D piece PNGs, rounded up to a multiple of 32 so the same few sizes are reused everywhere
/// (and can be loaded ahead of time with [precachePieces]).
int pieceDecodeWidth(double physicalPx) => ((physicalPx / 32).ceil() * 32).clamp(64, 512);

/// Loads the 12 piece images at board size before a game starts, so the first moves do not stutter.
/// Only the 3D set uses raster images; the SVG sets are tiny and load instantly.
void precachePieces(BuildContext context, String set, double boardSide) {
  if (set != 'lowpoly3d') return;
  final w = pieceDecodeWidth(boardSide / 8 * 0.94 * MediaQuery.devicePixelRatioOf(context));
  for (final k in const ['wK', 'wQ', 'wR', 'wB', 'wN', 'wP', 'bK', 'bQ', 'bR', 'bB', 'bN', 'bP']) {
    precacheImage(ResizeImage(AssetImage('assets/pieces/lowpoly3d/$k.png'), width: w), context).catchError((_) {});
  }
}

class PieceImage extends StatelessWidget {
  final int piece;
  final String set;
  final double size;
  const PieceImage(this.piece, this.set, this.size, {super.key});
  @override
  Widget build(BuildContext context) => set == 'lowpoly3d'
      // rendered from the 3D low-poly model (PNG, tall & narrow): sit on the square's baseline.
      // cacheWidth decodes the 512px source at on-screen size: far less memory and no decode jank.
      ? Image.asset('assets/pieces/lowpoly3d/${pieceKey(piece)}.png', width: size, height: size, cacheWidth: pieceDecodeWidth(size * MediaQuery.devicePixelRatioOf(context)), fit: BoxFit.contain, alignment: Alignment.bottomCenter, filterQuality: FilterQuality.medium, gaplessPlayback: true)
      : SvgPicture.asset('assets/pieces/$set/${pieceKey(piece)}.svg', width: size, height: size);
}

/// Interactive 8x8 board: tap-to-move, drag-and-drop, highlights, arrows and move-quality badges.
///
/// The screen around the board rebuilds every second for the clocks (and more often for sounds, hints, chat...).
/// Rebuilding 64 squares each time is wasted work, so the built board is reused while everything that affects how
/// it looks is unchanged. Callbacks are always read from the newest widget, so a reused board never calls stale code.
class ChessBoardView extends StatefulWidget {
  final List<int> pieces;
  final bool flipped, coords, animate, highlightLast;
  final String pieceSet;
  final BoardTheme theme;
  final int? selected, lastFrom, lastTo, checkSq;
  final Set<int> targets;
  final bool Function(int sq)? canDrag;
  final void Function(int sq)? onTap;
  final void Function(int from, int to)? onDrop;
  final List<int>? arrow;
  final List<int>? premove;
  final Color arrowColor;
  final int? badgeSq;
  final String? badgeText;
  final Color badgeColor;

  const ChessBoardView({
    super.key,
    required this.pieces,
    required this.pieceSet,
    required this.theme,
    this.flipped = false,
    this.coords = true,
    this.animate = false,
    this.highlightLast = true,
    this.selected,
    this.lastFrom,
    this.lastTo,
    this.checkSq,
    this.targets = const {},
    this.canDrag,
    this.onTap,
    this.onDrop,
    this.arrow,
    this.premove,
    this.arrowColor = const Color(0xCC16A34A),
    this.badgeSq,
    this.badgeText,
    this.badgeColor = Colors.green,
  });

  @override
  State<ChessBoardView> createState() => _ChessBoardViewState();
}

class _ChessBoardViewState extends State<ChessBoardView> {
  String? _sig;
  Widget? _built;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = widget;
      final side = c.biggest.shortestSide;
      final sig = [
        side, w.flipped, w.coords, w.animate, w.highlightLast, w.pieceSet, w.theme.light.toARGB32(), w.theme.dark.toARGB32(),
        w.selected, w.lastFrom, w.lastTo, w.checkSq, (w.targets.toList()..sort()).join(','), w.pieces.join(','),
        w.arrow?.join(','), w.premove?.join(','), w.arrowColor.toARGB32(), w.badgeSq, w.badgeText, w.badgeColor.toARGB32(),
        if (w.canDrag != null) [for (int i = 0; i < 64; i++) w.canDrag!(i) ? 1 : 0].join(),
      ].join('|');
      if (sig == _sig && _built != null) return _built!;
      _sig = sig;
      return _built = _BoardBody(
        pieces: List<int>.of(w.pieces),
        pieceSet: w.pieceSet,
        theme: w.theme,
        flipped: w.flipped,
        coords: w.coords,
        animate: w.animate,
        highlightLast: w.highlightLast,
        selected: w.selected,
        lastFrom: w.lastFrom,
        lastTo: w.lastTo,
        checkSq: w.checkSq,
        targets: Set<int>.of(w.targets),
        canDrag: w.canDrag == null ? null : (sq) => widget.canDrag?.call(sq) ?? false,
        onTap: (sq) => widget.onTap?.call(sq),
        onDrop: (a, b) => widget.onDrop?.call(a, b),
        arrow: w.arrow == null ? null : List<int>.of(w.arrow!),
        premove: w.premove == null ? null : List<int>.of(w.premove!),
        arrowColor: w.arrowColor,
        badgeSq: w.badgeSq,
        badgeText: w.badgeText,
        badgeColor: w.badgeColor,
      );
    });
  }
}

class _BoardBody extends StatelessWidget {
  final List<int> pieces;
  final bool flipped, coords, animate, highlightLast;
  final String pieceSet;
  final BoardTheme theme;
  final int? selected, lastFrom, lastTo, checkSq;
  final Set<int> targets;
  final bool Function(int sq)? canDrag;
  final void Function(int sq)? onTap;
  final void Function(int from, int to)? onDrop;
  final List<int>? arrow; // [from, to]
  final List<int>? premove; // queued pre-move [from, to], drawn in orange
  final Color arrowColor;
  final int? badgeSq;
  final String? badgeText;
  final Color badgeColor;

  const _BoardBody({
    required this.pieces,
    required this.pieceSet,
    required this.theme,
    required this.flipped,
    required this.coords,
    required this.animate,
    required this.highlightLast,
    this.selected,
    this.lastFrom,
    this.lastTo,
    this.checkSq,
    required this.targets,
    this.canDrag,
    this.onTap,
    this.onDrop,
    this.arrow,
    this.premove,
    required this.arrowColor,
    this.badgeSq,
    this.badgeText,
    required this.badgeColor,
  });

  Offset _pos(int sq, double s) {
    final f = sq & 7, r = sq >> 3;
    final col = flipped ? 7 - f : f, row = flipped ? r : 7 - r;
    return Offset(col * s, row * s);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final side = c.biggest.shortestSide;
      final s = side / 8;
      return SizedBox(
        width: side,
        height: side,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(children: [
            for (int sq = 0; sq < 64; sq++)
              if (sq != lastTo) _square(sq, s),
            // drawn last so a sliding piece passes over its neighbours
            if (lastTo != null) _square(lastTo!, s),
            if (arrow != null) IgnorePointer(child: CustomPaint(size: Size(side, side), painter: _ArrowPainter(_pos(arrow![0], s) + Offset(s / 2, s / 2), _pos(arrow![1], s) + Offset(s / 2, s / 2), s, arrowColor))),
            if (premove != null) IgnorePointer(child: CustomPaint(size: Size(side, side), painter: _ArrowPainter(_pos(premove![0], s) + Offset(s / 2, s / 2), _pos(premove![1], s) + Offset(s / 2, s / 2), s, const Color(0xCCF97316)))),
            if (badgeSq != null && badgeText != null)
              Positioned(
                left: _pos(badgeSq!, s).dx + s * 0.58,
                top: _pos(badgeSq!, s).dy - s * 0.04,
                child: IgnorePointer(
                  child: Container(
                    width: s * 0.46,
                    height: s * 0.46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                    child: Text(badgeText!, style: TextStyle(color: Colors.white, fontSize: s * 0.22, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }

  Widget _square(int sq, double s) {
    final f = sq & 7, r = sq >> 3;
    final isLight = (f + r) % 2 == 1;
    final p = pieces[sq];
    final pos = _pos(sq, s);
    Color bg = isLight ? theme.light : theme.dark;
    final overlays = <Widget>[];
    if (highlightLast && (sq == lastFrom || sq == lastTo)) overlays.add(Container(color: const Color(0x66F6E05E)));
    if (premove != null && (sq == premove![0] || sq == premove![1])) overlays.add(Container(color: const Color(0x66F97316)));
    if (sq == selected) overlays.add(Container(color: const Color(0x8860A5FA)));
    if (sq == checkSq) {
      overlays.add(Container(decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xCCEF4444), Color(0x00EF4444)], radius: 0.8))));
    }
    if (targets.contains(sq)) {
      overlays.add(Center(
        child: p == 0
            ? Container(width: s * 0.3, height: s * 0.3, decoration: const BoxDecoration(color: Color(0x55102A4A), shape: BoxShape.circle))
            : Container(width: s * 0.92, height: s * 0.92, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x55102A4A), width: s * 0.08))),
      ));
    }
    if (coords) {
      final showRank = (flipped ? f == 7 : f == 0);
      final showFile = (flipped ? r == 7 : r == 0);
      final tc = isLight ? theme.dark : theme.light;
      if (showRank) overlays.add(Positioned(left: 2, top: 1, child: Text('${r + 1}', style: TextStyle(fontSize: s * 0.2, color: tc, fontWeight: FontWeight.w700))));
      if (showFile) overlays.add(Positioned(right: 2, bottom: 0, child: Text(String.fromCharCode(97 + f), style: TextStyle(fontSize: s * 0.2, color: tc, fontWeight: FontWeight.w700))));
    }
    Widget? piece;
    if (p != 0) {
      final img = PieceImage(p, pieceSet, s * 0.94);
      if (canDrag != null && canDrag!(sq)) {
        piece = Draggable<int>(
          data: sq,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () => onTap?.call(sq),
          feedback: Transform.translate(offset: Offset(-s * 0.7, -s * 0.7), child: PieceImage(p, pieceSet, s * 1.4)),
          childWhenDragging: Opacity(opacity: 0.25, child: img),
          child: img,
        );
      } else {
        piece = img;
      }
      if (animate && sq == lastTo && lastFrom != null && lastFrom != lastTo) {
        final d = _pos(lastFrom!, s) - pos;
        final inner = piece;
        piece = TweenAnimationBuilder<double>(
          key: ValueKey('mv$lastFrom>$lastTo'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: inner,
          builder: (_, t, child) {
            // slide from the origin square with a small hop in the middle
            final hop = -math.sin(t * math.pi) * s * 0.18;
            return Transform.translate(offset: Offset(d.dx * (1 - t), d.dy * (1 - t) + hop), child: child);
          },
        );
        overlays.add(IgnorePointer(
          child: TweenAnimationBuilder<double>(
            key: ValueKey('ring$lastFrom>$lastTo'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOut,
            builder: (_, t, __) => Center(child: Opacity(opacity: (1 - t) * 0.7, child: Container(width: s * (0.4 + 0.8 * t), height: s * (0.4 + 0.8 * t), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5 * (1 - t) + 0.5))))),
          ),
        ));
      }
    }
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: s,
      height: s,
      child: DragTarget<int>(
        onAcceptWithDetails: (d) => onDrop?.call(d.data, sq),
        builder: (context, cand, rej) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap == null ? null : () => onTap!(sq),
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Positioned.fill(child: ColoredBox(color: bg)),
            ...overlays,
            if (cand.isNotEmpty) Positioned.fill(child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 3)))),
            if (piece != null) piece,
          ]),
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Offset a, b;
  final double s;
  final Color color;
  _ArrowPainter(this.a, this.b, this.s, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final d = (b - a);
    final len = d.distance;
    if (len < 1) return;
    final u = d / len;
    final n = Offset(-u.dy, u.dx);
    final w = s * 0.14, head = s * 0.38;
    final tip = b - u * (s * 0.12);
    final baseEnd = tip - u * head;
    final path = Path()
      ..moveTo(a.dx + n.dx * w / 2, a.dy + n.dy * w / 2)
      ..lineTo(baseEnd.dx + n.dx * w / 2, baseEnd.dy + n.dy * w / 2)
      ..lineTo(baseEnd.dx + n.dx * s * 0.2, baseEnd.dy + n.dy * s * 0.2)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(baseEnd.dx - n.dx * s * 0.2, baseEnd.dy - n.dy * s * 0.2)
      ..lineTo(baseEnd.dx - n.dx * w / 2, baseEnd.dy - n.dy * w / 2)
      ..lineTo(a.dx - n.dx * w / 2, a.dy - n.dy * w / 2)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter o) => o.a != a || o.b != b || o.color != color;
}

/// Read-only diagram used in lessons and puzzle previews.
class MiniBoard extends StatelessWidget {
  final String fen;
  final String pieceSet;
  final BoardTheme theme;
  final Set<int> highlight;
  final List<int>? arrow;
  const MiniBoard(this.fen, {super.key, this.pieceSet = 'cburnett', this.theme = const BoardTheme('Wood', Color(0xFFF0D9B5), Color(0xFFB58863)), this.highlight = const {}, this.arrow});
  @override
  Widget build(BuildContext context) {
    final g = ChessGame.fromFen(fen);
    return AspectRatio(
      aspectRatio: 1,
      child: ChessBoardView(pieces: g.board, pieceSet: pieceSet, theme: theme, coords: false, targets: highlight, arrow: arrow, arrowColor: const Color(0xAA2563EB)),
    );
  }
}

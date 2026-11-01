import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/constants.dart';
import '../../services/chess_service/chess_game.dart';
import '../chessboard/chess_board.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Ink(decoration: cardDeco(), child: Padding(padding: padding, child: child)),
          ),
        ),
      );
}

class IconBubble extends StatelessWidget {
  final IconData icon;
  final Color color;
  const IconBubble(this.icon, {super.key, this.color = C.primary});
  @override
  Widget build(BuildContext context) => Container(
        width: 46, height: 46,
        decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 24),
      );
}

class NavTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final Color color;
  const NavTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap, this.color = C.primary});
  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        child: Row(children: [
          IconBubble(icon, color: color),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: C.text2, fontSize: 12.5)),
          ])),
          const Icon(Icons.chevron_right, color: C.text2),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: C.secondary),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(color: C.text2), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool bot;
  final String? url; // profile photo (e.g. from Google); falls back to the initial
  const Avatar(this.name, {super.key, this.size = 40, this.bot = false, this.url});
  @override
  Widget build(BuildContext context) {
    final colors = [C.primary, const Color(0xFF7C3AED), const Color(0xFF0891B2), const Color(0xFFDB2777), const Color(0xFFEA580C)];
    final c = colors[name.codeUnits.fold(0, (a, b) => a + b) % colors.length];
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: c,
      foregroundImage: (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
      onForegroundImageError: (url != null && url!.isNotEmpty) ? (_, __) {} : null,
      child: bot ? Icon(Icons.smart_toy, color: Colors.white, size: size * 0.55) : Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.42)),
    );
  }
}

class PlayerBar extends StatelessWidget {
  final String name;
  final String sub;
  final int? clockMs;
  final bool active, bot;
  final List<int> captured;
  final String pieceSet;
  final int advantage;
  final String? avatarUrl;
  const PlayerBar({super.key, this.avatarUrl, required this.name, required this.sub, this.clockMs, this.active = false, this.bot = false, this.captured = const [], this.pieceSet = 'cburnett', this.advantage = 0});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: active ? C.softBlue : C.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: active ? C.primary.withAlpha(130) : C.border, width: active ? 1.5 : 1),
          boxShadow: const [BoxShadow(color: Color(0x0F2563EB), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Row(children: [
          Avatar(name, size: 40, bot: bot, url: avatarUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$name  ', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              SizedBox(
                height: 18,
                child: Row(children: [
                  Text(sub, style: const TextStyle(color: C.text2, fontSize: 12)),
                  const SizedBox(width: 6),
                  for (final p in captured) Align(widthFactor: 0.55, child: PieceImage(p, pieceSet, 17)),
                  if (advantage > 0) Padding(padding: const EdgeInsets.only(left: 8), child: Text('+$advantage', style: const TextStyle(color: C.text2, fontSize: 12, fontWeight: FontWeight.w700))),
                ]),
              ),
            ]),
          ),
          if (clockMs != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? C.primary : C.softBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(fmtClock(clockMs!), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: active ? Colors.white : (clockMs! < 10000 ? C.error : C.text), fontFeatures: const [FontFeature.tabularFigures()])),
            ),
        ]),
      );
}

Future<T?> showSheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 18), child: child)),
    );

void snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

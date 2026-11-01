import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Fades + slides its child in once, optionally after a delay (use [index] for staggered lists).
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  const Reveal({super.key, required this.child, this.index = 0});
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    final d = Duration(milliseconds: 55 * widget.index.clamp(0, 12));
    Future.delayed(d, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _a,
        child: AnimatedBuilder(
          animation: _a,
          builder: (_, child) => Transform.translate(offset: Offset(0, 22 * (1 - _a.value)), child: child),
          child: widget.child,
        ),
      );
}

/// Scales down slightly while pressed and gives a light haptic tick on tap.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const Pressable({super.key, required this.child, this.onTap});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap == null ? null : () { HapticFeedback.selectionClick(); widget.onTap!(); },
        child: AnimatedScale(scale: _down ? 0.965 : 1, duration: const Duration(milliseconds: 110), curve: Curves.easeOut, child: widget.child),
      );
}

/// Big tappable card with a rendered 3D banner image, title and subtitle.
class BannerCard extends StatelessWidget {
  final String image, title, subtitle;
  final double height;
  final VoidCallback onTap;
  final Widget? badge;
  final String? cta;
  const BannerCard({super.key, required this.image, required this.title, required this.subtitle, required this.onTap, this.height = 112, this.badge, this.cta});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Pressable(
          onTap: onTap,
          child: Container(
            height: height,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x332563EB), blurRadius: 18, offset: Offset(0, 8))]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(fit: StackFit.expand, children: [
                Image.asset(image, fit: BoxFit.cover, alignment: Alignment.centerRight),
                // darken the left side so the text stays readable
                const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0x66000000), Color(0x00000000)], stops: [0.0, 0.65]))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, shadows: [Shadow(color: Color(0x55000000), blurRadius: 6)])),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 13, fontWeight: FontWeight.w500)),
                    if (cta != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(cta!, style: const TextStyle(color: C.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_rounded, color: C.primary, size: 16),
                        ]),
                      ),
                    ],
                  ]),
                ),
                if (badge != null) Positioned(top: 12, right: 12, child: badge!),
              ]),
            ),
          ),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.2))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Small rounded stat tile (icon, big value, label).
class StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value, label;
  const StatTile({super.key, required this.icon, required this.color, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: cardDeco(radius: 18),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 21)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
              Text(label, style: const TextStyle(fontSize: 11.5, color: C.text2, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );
}

/// Pill button used for choices (selected = filled blue).
class ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const ChoicePill(this.label, this.selected, this.onTap, {super.key, this.icon});
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? C.primary : Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: selected ? const Color(0x552563EB) : const Color(0x142563EB), blurRadius: selected ? 12 : 8, offset: const Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 17, color: selected ? Colors.white : C.primary), const SizedBox(width: 6)],
            Text(label, style: TextStyle(color: selected ? Colors.white : C.text, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ),
      );
}

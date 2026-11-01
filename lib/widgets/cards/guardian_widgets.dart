import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/guardian_service.dart';

/// Round portrait of the Guardian (cropped head).
class GuardianAvatar extends StatelessWidget {
  final double size;
  const GuardianAvatar({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFA78BFA), width: 2), boxShadow: const [BoxShadow(color: Color(0x44A78BFA), blurRadius: 8)]),
        child: ClipOval(child: Image.asset('assets/images/guardian_head.png', fit: BoxFit.cover)),
      );
}

/// Portrait + speech bubble. The bubble pops each time [seq] changes.
class GuardianTalk extends StatelessWidget {
  final String? text;
  final int seq;
  final VoidCallback? onTap;
  const GuardianTalk({super.key, required this.text, required this.seq, this.onTap});
  @override
  Widget build(BuildContext context) {
    if (text == null || text!.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const GuardianAvatar(size: 42),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (w, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), alignment: Alignment.centerLeft, child: w)),
              child: Container(
                key: ValueKey(seq),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3EEFF),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                  border: Border.all(color: const Color(0x55A78BFA)),
                ),
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: '${Guardian.name}  ', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF6D4AD8), fontSize: 12)),
                  TextSpan(text: text, style: const TextStyle(color: C.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ])),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../services/guardian_service.dart';
import '../../widgets/cards/character_viewer.dart';

/// Showcase + chat for the Spirit Blossom Kindred model (CC-BY, Retronous).
class CharacterScreen extends StatefulWidget {
  const CharacterScreen({super.key});
  @override
  State<CharacterScreen> createState() => _CharacterScreenState();
}

class _CharacterScreenState extends State<CharacterScreen> {
  String _line = Guardian.say(GEvent.greet);
  int _seq = 0;

  void _talk(GEvent e) {
    HapticFeedback.selectionClick();
    setState(() {
      _line = Guardian.say(e);
      _seq++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final spin = context.watch<AppState>().settings.guardianSpin;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.white, title: const Text('Guardian', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1E1B4B), Color(0xFF3B2A7A), Color(0xFF0F172A)])),
        child: Stack(fit: StackFit.expand, children: [
          Positioned.fill(child: Opacity(opacity: 0.25, child: Image.asset('assets/images/earth.png', fit: BoxFit.cover, alignment: Alignment.bottomCenter))),
          SafeArea(
            child: Column(children: [
              const SizedBox(height: 8),
              Expanded(child: CharacterViewer(autoRotate: spin)),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0x33FFFFFF))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: const [
                    Text('Spirit Blossom Kindred', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    SizedBox(width: 8),
                    Text('Guardian', style: TextStyle(color: Color(0xFFA78BFA), fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: SizedBox(
                      key: ValueKey(_seq),
                      width: double.infinity,
                      child: _Typewriter(_line),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: FilledButton.icon(onPressed: () => _talk(GEvent.tap), icon: const Icon(Icons.chat_bubble_outline, size: 18), label: const Text('Talk'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)), onPressed: () => _talk(GEvent.tip), icon: const Icon(Icons.lightbulb_outline, size: 18), label: const Text('Chess tip'))),
                  ]),
                  const SizedBox(height: 8),
                  const Text('Drag to rotate · pinch to zoom · double-tap to spin\n3D model by Retronous (CC-BY-4.0)', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Reveals text letter by letter, like a game dialogue box.
class _Typewriter extends StatelessWidget {
  final String text;
  const _Typewriter(this.text);
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<int>(
        tween: IntTween(begin: 0, end: text.length),
        duration: Duration(milliseconds: 25 * text.length),
        builder: (_, n, __) => Text(text.substring(0, n), style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35, fontWeight: FontWeight.w600), minLines: 2, maxLines: 4),
      );
}

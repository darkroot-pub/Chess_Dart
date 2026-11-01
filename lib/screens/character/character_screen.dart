import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/cards/character_viewer.dart';

/// Showcase for the Spirit Blossom Kindred model (CC-BY, Retronous).
class CharacterScreen extends StatelessWidget {
  const CharacterScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
              const Expanded(child: CharacterViewer()),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0x33FFFFFF))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  const Text('Spirit Blossom Kindred', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  const Text('Your DarkChess guardian. Drag to rotate, pinch to zoom, double-tap to spin.', style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 13.5)),
                  const SizedBox(height: 10),
                  Row(children: const [
                    Icon(Icons.threed_rotation, color: Colors.white70, size: 18),
                    SizedBox(width: 6),
                    Expanded(child: Text('3D model by Retronous (CC-BY-4.0)', style: TextStyle(color: Colors.white60, fontSize: 11.5))),
                  ]),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

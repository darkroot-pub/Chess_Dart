import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/app.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/chess_service/chess_game.dart';
import '../../services/multiplayer_service/supabase_service.dart';
import '../../services/stockfish_service/engine_service.dart';
import '../../widgets/chessboard/chess_board.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final app = context.read<AppState>();
    final t0 = DateTime.now();
    try {
      await app.init();
      await SupabaseService.instance.init();
    } catch (_) {}
    EngineService.instance.init(); // warm up Stockfish in the background
    final left = 1800 - DateTime.now().difference(t0).inMilliseconds;
    if (left > 0) await Future.delayed(Duration(milliseconds: left));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => const MainShell(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE8F0FF), C.bg])),
          child: SafeArea(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              FadeTransition(
                opacity: CurvedAnimation(parent: ac, curve: Curves.easeOut),
                child: Column(children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: const LinearGradient(colors: [C.primary, C.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: const [BoxShadow(color: Color(0x442563EB), blurRadius: 24, offset: Offset(0, 10))],
                    ),
                    child: Center(child: PieceImage(makePiece(kN, kWhite), 'cburnett', 92)),
                  ),
                  const SizedBox(height: 22),
                  RichText(text: const TextSpan(children: [TextSpan(text: 'Dark', style: TextStyle(color: C.text, fontSize: 40, fontWeight: FontWeight.w800)), TextSpan(text: 'Chess', style: TextStyle(color: C.primary, fontSize: 40, fontWeight: FontWeight.w800))])),
                  const SizedBox(height: 6),
                  const Text('Think  •  Plan  •  Win', style: TextStyle(color: C.text2, fontSize: 16, letterSpacing: 1)),
                ]),
              ),
              const SizedBox(height: 70),
              SizedBox(
                width: 180,
                child: AnimatedBuilder(
                  animation: ac,
                  builder: (_, __) => LinearProgressIndicator(value: ac.value, minHeight: 5, borderRadius: BorderRadius.circular(5), backgroundColor: C.border, color: C.primary),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Loading...', style: TextStyle(color: C.text2, fontSize: 12)),
            ]),
          ),
        ),
      );
}

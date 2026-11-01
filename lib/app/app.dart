import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/cards/challenge_banner.dart';
import 'nav.dart';
import '../core/theme/app_theme.dart';
import '../screens/game/play_setup_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/puzzles/puzzles_screen.dart';
import '../screens/splash/splash_screen.dart';

class DarkChessApp extends StatelessWidget {
  const DarkChessApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DarkChess',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        themeMode: ThemeMode.light,
        navigatorKey: navKey,
        builder: (context, child) => ChallengeOverlay(child: child ?? const SizedBox.shrink()),
        home: const SplashScreen(),
      );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0;
  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.sports_esports_outlined, Icons.sports_esports_rounded, 'Play'),
    (Icons.extension_outlined, Icons.extension_rounded, 'Puzzles'),
    (Icons.person_outline, Icons.person_rounded, 'Profile'),
  ];

  void _go(int i) {
    if (i == tab) return;
    HapticFeedback.selectionClick();
    setState(() => tab = i);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: tab, children: [
          HomeScreen(goTab: _go),
          const PlaySetupScreen(),
          const PuzzlesScreen(showBack: false),
          const ProfileScreen(),
        ]),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [BoxShadow(color: Color(0x262563EB), blurRadius: 22, offset: Offset(0, 8))],
              border: Border.all(color: C.border),
            ),
            child: Row(children: [
              for (int i = 0; i < _items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _go(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: tab == i ? C.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: tab == i ? const [BoxShadow(color: Color(0x552563EB), blurRadius: 12, offset: Offset(0, 4))] : null,
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        AnimatedScale(scale: tab == i ? 1.12 : 1, duration: const Duration(milliseconds: 260), child: Icon(tab == i ? _items[i].$2 : _items[i].$1, color: tab == i ? Colors.white : C.text2, size: 24)),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          child: tab == i
                              ? Padding(padding: const EdgeInsets.only(left: 6), child: Text(_items[i].$3, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)))
                              : const SizedBox(width: 0, height: 0),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}

import 'package:flutter/material.dart';
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
  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: tab, children: [
          HomeScreen(goTab: (t) => setState(() => tab = t)),
          const PlaySetupScreen(),
          const PuzzlesScreen(showBack: false),
          const ProfileScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          backgroundColor: C.surface,
          indicatorColor: C.softBlue,
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: C.primary), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.sports_esports_outlined), selectedIcon: Icon(Icons.sports_esports, color: C.primary), label: 'Play'),
            NavigationDestination(icon: Icon(Icons.extension_outlined), selectedIcon: Icon(Icons.extension, color: C.primary), label: 'Puzzles'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: C.primary), label: 'Profile'),
          ],
        ),
      );
}

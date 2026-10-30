import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import '../../core/constants/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/multiplayer_service/supabase_service.dart';
import '../../widgets/cards/common.dart';
import 'online_game_screen.dart';

class OnlineHubScreen extends StatefulWidget {
  const OnlineHubScreen({super.key});
  @override
  State<OnlineHubScreen> createState() => _OnlineHubScreenState();
}

class _OnlineHubScreenState extends State<OnlineHubScreen> {
  final sb = SupabaseService.instance;
  final email = TextEditingController(), pass = TextEditingController(), name = TextEditingController(), code = TextEditingController();
  bool busy = false, signUp = false;
  int tc = 4; // index into kTimeControls
  String? error;
  List<Map<String, dynamic>> players = [];
  Timer? _t;

  StreamSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    if (sb.available) {
      _authSub = sb.client.auth.onAuthStateChange.listen((d) {
        if (d.session != null && mounted) { setState(() => error = null); _refresh(); }
      });
    }
    if (sb.available && sb.signedIn) _refresh();
    _t = Timer.periodic(const Duration(seconds: 20), (_) { if (mounted && sb.signedIn) _refresh(); });
  }

  @override
  void dispose() {
    _t?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!sb.signedIn) return;
    try {
      await sb.heartbeat();
      final p = await sb.onlinePlayers();
      if (mounted) setState(() => players = p);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not load players: $e');
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() { busy = true; error = null; });
    String? err;
    try {
      await f();
    } catch (e) {
      err = e is AuthException ? e.message : '$e';
    }
    if (mounted) setState(() { busy = false; if (err != null) error = err; });
  }

  void _openGame(Map<String, dynamic> g) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlineGameScreen(gameId: g['id'])));

  @override
  Widget build(BuildContext context) {
    if (!sb.available) {
      return Scaffold(
        appBar: AppBar(title: const Text('Online Multiplayer')),
        body: EmptyState(
          icon: Icons.cloud_off,
          title: 'Online play is not configured',
          message: sb.initError != null ? 'Could not connect to Supabase:\n${sb.initError}' : 'This build has no Supabase credentials. Offline games, puzzles and analysis still work.\n\nSee SETUP_SUPABASE.md to enable online play.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Online Multiplayer'), actions: [
        if (sb.signedIn) IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: () async { await sb.signOut(); if (mounted) setState(() {}); }),
      ]),
      body: SafeArea(child: sb.signedIn ? _lobby() : _auth()),
    );
  }

  Widget _auth() => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Sign in to play online', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (signUp) TextField(controller: name, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
        if (signUp) const SizedBox(height: 10),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password (6+ chars)', border: OutlineInputBorder())),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: C.error))),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: busy ? null : () => _run(() async {
            if (signUp) {
              final ok = await sb.signUp(email.text.trim(), pass.text, name.text.trim().isEmpty ? 'Player${DateTime.now().millisecond}' : name.text.trim());
              if (!ok) {
                if (mounted) setState(() { signUp = false; error = 'Account created. Please confirm your e-mail, then sign in.'; });
                return;
              }
            } else {
              await sb.signIn(email.text.trim(), pass.text);
            }
            await _refresh();
          }),
          child: Text(signUp ? 'Create account' : 'Sign in'),
        ),
        TextButton(onPressed: () => setState(() => signUp = !signUp), child: Text(signUp ? 'I already have an account' : 'Create a new account')),
        const Divider(),
        OutlinedButton.icon(icon: const Icon(Icons.g_mobiledata, size: 28), label: const Text('Continue with Google'), onPressed: busy ? null : () => _run(() async { await sb.signInGoogle(); })),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: busy ? null : () => _run(() async { await sb.signInGuest(); await _refresh(); }), child: const Text('Continue as guest')),
      ]);

  Widget _lobby() => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: const TextStyle(color: C.error))),
          const Text('Time control', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (int i = 0; i < kTimeControls.length - 1; i++)
              ChoiceChip(label: Text(kTimeControls[i].label), selected: tc == i, onSelected: (_) => setState(() => tc = i), selectedColor: C.primary, showCheckmark: false, side: BorderSide.none, backgroundColor: C.softBlue, labelStyle: TextStyle(color: tc == i ? Colors.white : C.text)),
          ]),
          const SizedBox(height: 12),
          AppCard(
            child: Column(children: [
              Row(children: [const IconBubble(Icons.public), const SizedBox(width: 12), const Expanded(child: Text('Quick Match\nFind an opponent instantly', style: TextStyle(fontWeight: FontWeight.w700)))]),
              const SizedBox(height: 10),
              ElevatedButton(onPressed: busy ? null : () => _run(() async => _openGame(await sb.quickMatch(kTimeControls[tc].minutes, kTimeControls[tc].inc))), child: const Text('Play')),
            ]),
          ),
          AppCard(
            child: Column(children: [
              Row(children: [const IconBubble(Icons.group, color: C.secondary), const SizedBox(width: 12), const Expanded(child: Text('Play with Friends\nPrivate room with a code', style: TextStyle(fontWeight: FontWeight.w700)))]),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: busy ? null : () => _run(() async => _openGame(await sb.createRoom(kTimeControls[tc].minutes, kTimeControls[tc].inc))), child: const Text('Create private room')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Room code', isDense: true, border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                FilledButton(onPressed: busy ? null : () => _run(() async => _openGame(await sb.joinRoom(code.text))), child: const Text('Join')),
              ]),
            ]),
          ),
          Row(children: [
            const Expanded(child: Text('Online players', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            IconButton(icon: const Icon(Icons.person_add_alt), tooltip: 'Add friend', onPressed: _addFriend),
          ]),
          if (players.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Nobody else is online right now.', style: TextStyle(color: C.text2))),
          for (final p in players)
            AppCard(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Avatar(p['username'] ?? '?'),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p['username'] ?? '?', style: const TextStyle(fontWeight: FontWeight.w700)), Text('(${p['rating']}) · ${p['games_played']} games', style: const TextStyle(color: C.text2, fontSize: 12))])),
                const Icon(Icons.circle, color: C.success, size: 10),
                const SizedBox(width: 4),
                const Text('Online', style: TextStyle(color: C.success, fontSize: 12)),
              ]),
            ),
        ]),
      );

  Future<void> _addFriend() async {
    final c = TextEditingController();
    final n = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Add friend'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Username')),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Add'))],
      ),
    );
    if (n == null || n.isEmpty) return;
    try {
      await sb.addFriend(n);
      if (mounted) snack(context, 'Friend added');
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }
}

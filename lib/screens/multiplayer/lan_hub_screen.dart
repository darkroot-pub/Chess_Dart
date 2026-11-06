import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/lan_service.dart';
import '../../widgets/cards/common.dart';
import '../game/game_screen.dart';

/// Play against a friend who is next to you, over one phone's hotspot or the same Wi-Fi. No internet, no account.
class LanHubScreen extends StatefulWidget {
  const LanHubScreen({super.key});
  @override
  State<LanHubScreen> createState() => _LanHubScreenState();
}

class _LanHubScreenState extends State<LanHubScreen> {
  bool hosting = true; // tab: host or join
  int tc = 4; // index into kTimeControls
  int color = 2; // 0 white, 1 black, 2 random (what the HOST plays)

  // host state
  LanHost? _host;
  List<(String, String)> _addresses = [];
  String _pin = '';
  bool _waiting = false;

  // join state
  final _ip = TextEditingController();
  final _pinCtl = TextEditingController();
  bool _connecting = false;

  String? _error;
  bool _leaving = false;

  @override
  void dispose() {
    _host?.stop();
    _ip.dispose();
    _pinCtl.dispose();
    super.dispose();
  }

  String get _myName => context.read<AppState>().stats.username;

  Future<void> _create() async {
    setState(() => _error = null);
    final addrs = await lanAddresses();
    if (!mounted) return;
    if (addrs.isEmpty) {
      setState(() => _error = 'No network found. Turn on your phone\'s hotspot (or connect to Wi-Fi) first, then try again.');
      return;
    }
    final hostColor = color == 2 ? Random().nextInt(2) : color;
    final pin = LanHost.newPin();
    final host = LanHost(
      pin: pin,
      hostName: _myName,
      hostColor: hostColor,
      tcIndex: tc,
      onProblem: (m) {
        if (mounted) setState(() { _waiting = false; _error = m; });
      },
      onGuest: (link, guestName) {
        if (!mounted || _leaving) {
          link.close();
          return;
        }
        _leaving = true;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => GameScreen(mode: 'lan', humanColor: hostColor, tcIndex: tc, link: link, opponentName: guestName),
        ));
      },
    );
    try {
      await host.start();
    } on LanException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    if (!mounted) {
      host.stop();
      return;
    }
    setState(() {
      _host = host;
      _addresses = addrs;
      _pin = pin;
      _waiting = true;
    });
  }

  Future<void> _cancelHost() async {
    await _host?.stop();
    if (mounted) setState(() { _host = null; _waiting = false; });
  }

  Future<void> _join() async {
    setState(() { _error = null; _connecting = true; });
    final name = _myName;
    try {
      final (link, welcome) = await LanClient.connect(host: _ip.text, pin: _pinCtl.text.trim(), name: name);
      if (!mounted) {
        link.close();
        return;
      }
      final hostColor = welcome['hostColor'] as int;
      final tcIndex = (welcome['tc'] as int).clamp(0, kTimeControls.length - 1);
      final hostName = (welcome['name'] is String && (welcome['name'] as String).trim().isNotEmpty) ? (welcome['name'] as String).trim() : 'Friend';
      _leaving = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => GameScreen(mode: 'lan', humanColor: 1 - hostColor, tcIndex: tcIndex, link: link, opponentName: hostName.length > 20 ? hostName.substring(0, 20) : hostName),
      ));
    } on LanException catch (e) {
      if (mounted) setState(() { _error = e.message; _connecting = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not connect. Try again.'; _connecting = false; });
    }
  }

  Widget _step(String n, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 11, backgroundColor: C.primary, child: Text(n, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 14))),
        ]),
      );

  Widget _chip(String label, bool sel, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => onTap(),
        selectedColor: C.primary,
        showCheckmark: false,
        side: BorderSide.none,
        backgroundColor: C.softBlue,
        labelStyle: TextStyle(color: sel ? Colors.white : C.text, fontWeight: FontWeight.w600),
      );

  Widget _hostPanel() {
    if (_waiting) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: cardDeco(radius: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Tell your friend:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          const Text('1. Connect to this phone\'s hotspot (or the same Wi-Fi)\n2. Open DarkChess → Play → Hotspot / Wi-Fi → Join', style: TextStyle(color: C.text2)),
          const SizedBox(height: 14),
          for (final (name, ip) in _addresses)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Clipboard.setData(ClipboardData(text: ip));
                snack(context, 'Address copied');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  const Icon(Icons.wifi_tethering, color: C.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(ip, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1))),
                  Text(name, style: const TextStyle(color: C.text2, fontSize: 12)),
                ]),
              ),
            ),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.pin_outlined, color: C.primary),
            const SizedBox(width: 10),
            Text(_pin, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 6)),
            const SizedBox(width: 10),
            const Text('PIN', style: TextStyle(color: C.text2)),
          ]),
          const SizedBox(height: 16),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Waiting for your friend…', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          TextButton(onPressed: _cancelHost, child: const Text('Cancel')),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Time control', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (int i = 0; i < kTimeControls.length; i++) _chip(kTimeControls[i].untimed ? 'Unlimited' : kTimeControls[i].label, tc == i, () => setState(() => tc = i)),
      ]),
      const SizedBox(height: 16),
      const Text('You play', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        _chip('White', color == 0, () => setState(() => color = 0)),
        _chip('Black', color == 1, () => setState(() => color = 1)),
        _chip('Random', color == 2, () => setState(() => color = 2)),
      ]),
      const SizedBox(height: 18),
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        onPressed: _create,
        icon: const Icon(Icons.wifi_tethering),
        label: const Text('Create game', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
    ]);
  }

  Widget _joinPanel() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Type what you see on your friend\'s screen.', style: TextStyle(color: C.text2)),
        const SizedBox(height: 12),
        TextField(
          controller: _ip,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), LengthLimitingTextInputFormatter(15)],
          decoration: InputDecoration(labelText: 'Address (e.g. 192.168.43.1)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinCtl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          decoration: InputDecoration(labelText: 'PIN (4 digits)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: _connecting ? null : _join,
          icon: _connecting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
          label: Text(_connecting ? 'Connecting…' : 'Join game', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hotspot / Wi-Fi game')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(radius: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Play a friend nearby, no internet needed', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              _step('1', 'One phone turns on its hotspot. The other phone connects to it. (Or both join the same Wi-Fi.)'),
              _step('2', 'The hotspot phone taps Host and creates the game.'),
              _step('3', 'The other phone taps Join and types the address and PIN.'),
            ]),
          ),
          const SizedBox(height: 16),
          if (!_waiting)
            Row(children: [
              Expanded(child: _chip('Host a game', hosting, () => setState(() { hosting = true; _error = null; }))),
              const SizedBox(width: 10),
              Expanded(child: _chip('Join a game', !hosting, () => setState(() { hosting = false; _error = null; }))),
            ]),
          if (!_waiting) const SizedBox(height: 16),
          hosting ? _hostPanel() : _joinPanel(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0x1AEF4444), borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline, color: C.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: C.error))),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

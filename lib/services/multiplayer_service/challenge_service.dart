import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/nav.dart';
import '../../screens/multiplayer/online_game_screen.dart';
import 'supabase_service.dart';

/// Polls for friend challenges while signed in. Incoming ones appear as a banner on any screen;
/// when someone accepts a challenge we sent, the game opens automatically.
class ChallengeService {
  static final ChallengeService instance = ChallengeService._();
  ChallengeService._();

  final ValueNotifier<List<Map<String, dynamic>>> incoming = ValueNotifier([]);
  Timer? _t;
  final Set<String> _handled = {};
  bool _busy = false;
  SupabaseService get sb => SupabaseService.instance;

  void start() {
    if (_t != null || !sb.available) return;
    _poll();
    _t = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  void stop() {
    _t?.cancel();
    _t = null;
    _handled.clear();
    incoming.value = [];
  }

  void _toast(String msg) {
    final ctx = navKey.currentContext;
    if (ctx != null) ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void _open(String gameId) => navKey.currentState?.push(MaterialPageRoute(builder: (_) => OnlineGameScreen(gameId: gameId)));

  Future<void> _poll() async {
    if (_busy || !sb.signedIn) return;
    _busy = true;
    try {
      final uid = sb.user!.id;
      final t5 = DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String();
      final t2 = DateTime.now().toUtc().subtract(const Duration(minutes: 2)).toIso8601String();
      final inc = List<Map<String, dynamic>>.from(
          await sb.client.from('challenges').select().eq('to_id', uid).eq('status', 'pending').gt('created_at', t5).order('created_at'));
      final out = List<Map<String, dynamic>>.from(
          await sb.client.from('challenges').select().eq('from_id', uid).inFilter('status', ['accepted', 'declined']).gt('created_at', t2));
      final ids = <String>{for (final c in inc) c['from_id'] as String, for (final c in out) c['to_id'] as String}.toList();
      final prof = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final r = await sb.client.from('profiles').select('id,username,avatar_url').inFilter('id', ids);
        for (final p in r) {
          prof[p['id'] as String] = Map<String, dynamic>.from(p);
        }
      }
      for (final c in inc) {
        c['from'] = prof[c['from_id']];
      }
      incoming.value = inc.where((c) => !_handled.contains(c['id'])).toList();
      for (final c in out) {
        final id = c['id'] as String;
        if (_handled.contains(id)) continue;
        _handled.add(id);
        final name = prof[c['to_id']]?['username'] ?? 'Player';
        if (c['status'] == 'accepted' && c['game_id'] != null) {
          final g = await sb.fetchGame(c['game_id']);
          if (g != null && g['status'] == 'active') {
            _toast('$name accepted your challenge!');
            _open(c['game_id']);
          }
        } else if (c['status'] == 'declined') {
          _toast('$name declined your challenge');
        }
      }
    } catch (_) {
      // transient network errors: try again on the next tick
    } finally {
      _busy = false;
    }
  }

  Future<void> send(String toId, int minutes, int inc) async {
    await sb.client.rpc('send_challenge', params: {'p_to': toId, 'p_minutes': minutes, 'p_inc': inc});
  }

  Future<void> respond(Map<String, dynamic> c, bool accept) async {
    final id = c['id'] as String;
    _handled.add(id);
    incoming.value = incoming.value.where((e) => e['id'] != id).toList();
    try {
      final r = await sb.client.rpc('respond_challenge', params: {'p_id': id, 'p_accept': accept});
      if (accept && r is Map && r['game_id'] != null) _open(r['game_id'] as String);
    } catch (e) {
      _toast('$e');
    }
  }
}

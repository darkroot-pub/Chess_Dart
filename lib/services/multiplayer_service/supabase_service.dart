import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/constants.dart';

/// All online features go through Supabase. When credentials are missing, [available] is false and
/// the UI shows an "online unavailable" state; offline play is unaffected.
class SupabaseService {
  static final SupabaseService instance = SupabaseService._();
  SupabaseService._();
  bool available = false;
  String? initError;

  Future<void> init() async {
    if (!SupabaseConfig.configured) return;
    try {
      await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
      available = true;
    } catch (e) {
      initError = '$e';
      debugPrint('Supabase init failed: $e');
    }
  }

  SupabaseClient get client => Supabase.instance.client;
  User? get user => available ? client.auth.currentUser : null;
  bool get signedIn => user != null;

  Future<void> signUp(String email, String password, String username) async {
    await client.auth.signUp(email: email, password: password, data: {'username': username});
  }

  Future<void> signIn(String email, String password) => client.auth.signInWithPassword(email: email, password: password);
  Future<void> signInGuest() => client.auth.signInAnonymously();
  Future<void> signOut() => client.auth.signOut();

  Future<Map<String, dynamic>?> myProfile() async {
    if (user == null) return null;
    return await client.from('profiles').select().eq('id', user!.id).maybeSingle();
  }

  Future<void> heartbeat() async {
    try {
      await client.rpc('touch_presence');
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> onlinePlayers() async {
    final since = DateTime.now().toUtc().subtract(const Duration(minutes: 3)).toIso8601String();
    final r = await client.from('profiles').select('id,username,rating,games_played').gt('last_seen', since).neq('id', user!.id).order('rating', ascending: false).limit(50);
    return List<Map<String, dynamic>>.from(r);
  }

  Future<List<Map<String, dynamic>>> leaderboard({bool friends = false}) async {
    if (!friends) {
      final r = await client.from('leaderboard').select().limit(100);
      return List<Map<String, dynamic>>.from(r);
    }
    final f = await client.from('friendships').select('friend_id').eq('user_id', user!.id);
    final ids = [user!.id, ...List<Map<String, dynamic>>.from(f).map((e) => e['friend_id'] as String)];
    final r = await client.from('leaderboard').select().inFilter('id', ids);
    return List<Map<String, dynamic>>.from(r);
  }

  Future<void> addFriend(String username) async {
    final p = await client.from('profiles').select('id').eq('username', username).maybeSingle();
    if (p == null) throw 'No player called "$username"';
    if (p['id'] == user!.id) throw 'You cannot add yourself';
    await client.from('friendships').upsert({'user_id': user!.id, 'friend_id': p['id']});
  }

  Future<Map<String, dynamic>> quickMatch(int minutes, int inc) async =>
      Map<String, dynamic>.from(await client.rpc('quick_match', params: {'p_minutes': minutes, 'p_inc': inc}));
  Future<Map<String, dynamic>> createRoom(int minutes, int inc) async =>
      Map<String, dynamic>.from(await client.rpc('create_room', params: {'p_minutes': minutes, 'p_inc': inc}));
  Future<Map<String, dynamic>> joinRoom(String code) async =>
      Map<String, dynamic>.from(await client.rpc('join_room', params: {'p_code': code.trim().toUpperCase()}));
  Future<void> cancelGame(String id) async => await client.rpc('cancel_game', params: {'p_game': id});

  Future<Map<String, dynamic>?> fetchGame(String id) async => await client.from('games').select().eq('id', id).maybeSingle();

  /// Server-validated actions: move (uci), resign, offer_draw, accept_draw, decline_draw, timeout.
  Future<Map<String, dynamic>> action(String gameId, String action, {String? uci}) async {
    final res = await client.functions.invoke('game-action', body: {'game_id': gameId, 'action': action, if (uci != null) 'uci': uci});
    final d = res.data;
    if (d is Map && d['error'] != null) throw d['error'];
    return Map<String, dynamic>.from(d as Map);
  }

  RealtimeChannel watchGame(String id, void Function(Map<String, dynamic> row) onRow, void Function(bool connected) onStatus) {
    final ch = client.channel('game:$id');
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'games',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
          callback: (payload) => onRow(Map<String, dynamic>.from(payload.newRecord)),
        )
        .subscribe((status, error) => onStatus(status == RealtimeSubscribeStatus.subscribed));
    return ch;
  }
}

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  /// Creates the account and guarantees a session afterwards. Returns true when signed in,
  /// false when the project requires e-mail confirmation first (no session can exist yet).
  Future<bool> signUp(String email, String password, String username) async {
    final res = await client.auth.signUp(email: email, password: password, data: {'username': username});
    if (res.session != null || client.auth.currentSession != null) return true;
    // No session came back: sign in with the same credentials (works when confirmation is off).
    try {
      await client.auth.signInWithPassword(email: email, password: password);
      return true;
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('confirm')) return false;
      rethrow;
    }
  }

  Future<void> signIn(String email, String password) => client.auth.signInWithPassword(email: email, password: password);
  /// Native Google account picker (no browser). Exchanges the Google ID token for a Supabase session.
  Future<void> signInGoogle() async {
    if (SupabaseConfig.googleWebClientId.isEmpty) throw 'Google sign-in is not configured (missing GOOGLE_WEB_CLIENT_ID).';
    final g = GoogleSignIn(serverClientId: SupabaseConfig.googleWebClientId);
    await g.signOut(); // always show the account chooser
    final acct = await g.signIn();
    if (acct == null) return; // user cancelled
    final auth = await acct.authentication;
    final idToken = auth.idToken;
    if (idToken == null) throw 'Google did not return an ID token.';
    await client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken, accessToken: auth.accessToken);
  }
  Future<void> signInGuest() => client.auth.signInAnonymously();
  Future<void> signOut() async {
    try { await GoogleSignIn().signOut(); } catch (_) {}
    await client.auth.signOut();
  }

  Future<void> updateAvatar(String url) async {
    if (user == null) return;
    await client.from('profiles').update({'avatar_url': url}).eq('id', user!.id);
  }

  Future<void> updateUsername(String name) async {
    if (user == null) return;
    await client.from('profiles').update({'username': name}).eq('id', user!.id);
  }

  Future<Map<String, dynamic>?> myProfile() async {
    if (user == null) return null;
    return await client.from('profiles').select().eq('id', user!.id).maybeSingle();
  }

  /// Cloud progress row (stats / settings / history) or null if none yet.
  Future<Map<String, dynamic>?> fetchProgress() async {
    if (user == null) return null;
    return await client.from('user_progress').select().eq('user_id', user!.id).maybeSingle();
  }

  Future<void> saveProgress(Map<String, dynamic> stats, Map<String, dynamic> settings, List<dynamic> history) async {
    if (user == null) return;
    await client.from('user_progress').upsert({
      'user_id': user!.id, 'stats': stats, 'settings': settings, 'history': history,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> heartbeat() async {
    try {
      await client.rpc('touch_presence');
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> onlinePlayers() async {
    final since = DateTime.now().toUtc().subtract(const Duration(minutes: 3)).toIso8601String();
    final uid = user?.id;
    if (uid == null) return [];
    final r = await client.from('profiles').select('id,username,rating,games_played,avatar_url').gt('last_seen', since).neq('id', uid).order('rating', ascending: false).limit(50);
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
    dynamic d;
    try {
      final res = await client.functions.invoke('game-action', body: {'game_id': gameId, 'action': action, if (uci != null) 'uci': uci});
      d = res.data;
    } catch (e) {
      String? msg;
      try {
        final det = (e as dynamic).details;
        if (det is Map && det['error'] != null) msg = '${det['error']}';
      } catch (_) {}
      if (msg != null) throw msg;
      final s = '$e';
      if (s.contains('NOT_FOUND') || s.contains('404')) {
        throw 'Game server is not deployed. Deploy the "game-action" Edge Function in Supabase (see SETUP_SUPABASE.md, step 4).';
      }
      throw s;
    }
    if (d is Map && d['error'] != null) throw '${d['error']}';
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

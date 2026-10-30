import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state.dart';
import '../../services/multiplayer_service/supabase_service.dart';
import '../../widgets/cards/common.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool friends = false, loading = false;
  String? error;
  List<Map<String, dynamic>> rows = [];
  final sb = SupabaseService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!sb.available || !sb.signedIn) return;
    setState(() { loading = true; error = null; });
    try {
      rows = await sb.leaderboard(friends: friends);
      rows.sort((a, b) => (b['rating'] as int).compareTo(a['rating'] as int));
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<AppState>().stats;
    final online = sb.available && sb.signedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Global')), ButtonSegment(value: true, label: Text('Friends'))],
              selected: {friends},
              onSelectionChanged: (v) { friends = v.first; _load(); },
            ),
          ),
          Expanded(
            child: !online
                ? ListView(padding: const EdgeInsets.all(16), children: [
                    const Text('Rankings come from the online server. Sign in under Play → Online Multiplayer to see real players.', style: TextStyle(color: C.text2)),
                    const SizedBox(height: 12),
                    AppCard(child: Row(children: [Avatar(stats.username), const SizedBox(width: 12), Expanded(child: Text('${stats.username} (you)', style: const TextStyle(fontWeight: FontWeight.w700))), Text('${stats.rating}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.primary))])),
                  ])
                : loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                        ? EmptyState(icon: Icons.error_outline, title: 'Could not load', message: error!, action: ElevatedButton(onPressed: _load, child: const Text('Retry')))
                        : rows.isEmpty
                            ? EmptyState(icon: Icons.groups, title: friends ? 'No friends yet' : 'No ranked players yet', message: friends ? 'Add friends from the Online Multiplayer screen.' : 'Play online to appear here.')
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: rows.length,
                                itemBuilder: (c, i) {
                                  final r = rows[i];
                                  final me = r['id'] == sb.user!.id;
                                  final medal = [const Color(0xFFF59E0B), const Color(0xFF94A3B8), const Color(0xFFEA580C)];
                                  return AppCard(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(children: [
                                      CircleAvatar(radius: 14, backgroundColor: i < 3 ? medal[i] : C.softBlue, child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: i < 3 ? Colors.white : C.text))),
                                      const SizedBox(width: 10),
                                      Avatar(r['username'] ?? '?', size: 34),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text('${r['username']}${me ? ' (you)' : ''}', style: TextStyle(fontWeight: me ? FontWeight.w800 : FontWeight.w600, color: me ? C.primary : C.text))),
                                      Text('${r['rating']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                    ]),
                                  );
                                },
                              ),
          ),
        ]),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/multiplayer_service/challenge_service.dart';
import '../../services/multiplayer_service/supabase_service.dart';
import '../../widgets/cards/common.dart';

/// Bottom sheet: pick a time control and send a challenge to [toId].
Future<void> showChallengeSheet(BuildContext context, String toId, String name) async {
  int tc = 4;
  await showSheet(
    context,
    StatefulBuilder(
      builder: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Challenge $name', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Pick a time control. They get an invitation instantly.', style: TextStyle(color: C.text2)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (int i = 0; i < kTimeControls.length - 1; i++)
            ChoiceChip(
              label: Text(kTimeControls[i].label),
              selected: tc == i,
              onSelected: (_) => set(() => tc = i),
              selectedColor: C.primary,
              showCheckmark: false,
              side: BorderSide.none,
              backgroundColor: C.softBlue,
              labelStyle: TextStyle(color: tc == i ? Colors.white : C.text, fontWeight: FontWeight.w600),
            ),
        ]),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.sports_esports),
          label: const Text('Send challenge'),
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              await ChallengeService.instance.send(toId, kTimeControls[tc].minutes, kTimeControls[tc].inc);
              if (context.mounted) snack(context, 'Challenge sent to $name. Waiting for a reply…');
            } catch (e) {
              if (context.mounted) snack(context, '$e');
            }
          },
        ),
      ]),
    ),
  );
}

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final sb = SupabaseService.instance;
  List<Map<String, dynamic>> friends = [];
  bool loading = true;
  String? error;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  bool _online(Map<String, dynamic> p) {
    final ls = DateTime.tryParse('${p['last_seen']}');
    return ls != null && DateTime.now().toUtc().difference(ls.toUtc()).inMinutes < 3;
  }

  Future<void> _load() async {
    final uid = sb.user?.id;
    if (uid == null) return;
    try {
      final f = await sb.client.from('friendships').select('friend_id').eq('user_id', uid);
      final ids = List<Map<String, dynamic>>.from(f).map((e) => e['friend_id'] as String).toList();
      var list = <Map<String, dynamic>>[];
      if (ids.isNotEmpty) {
        final r = await sb.client.from('profiles').select('id,username,rating,games_played,last_seen,avatar_url').inFilter('id', ids);
        list = List<Map<String, dynamic>>.from(r);
        list.sort((a, b) {
          final o = (_online(b) ? 1 : 0) - (_online(a) ? 1 : 0);
          return o != 0 ? o : '${a['username']}'.toLowerCase().compareTo('${b['username']}'.toLowerCase());
        });
      }
      if (mounted) setState(() { friends = list; loading = false; error = null; });
    } catch (e) {
      if (mounted) setState(() { loading = false; error = '$e'; });
    }
  }

  Future<void> _add() async {
    final c = TextEditingController();
    final n = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Add friend'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Their username')),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Add'))],
      ),
    );
    if (n == null || n.isEmpty) return;
    try {
      await sb.addFriend(n);
      if (mounted) snack(context, 'Friend added');
      _load();
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  Future<void> _remove(Map<String, dynamic> p) async {
    try {
      await sb.client.from('friendships').delete().eq('user_id', sb.user!.id).eq('friend_id', p['id']);
      _load();
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Friends & Challenges'), actions: [IconButton(icon: const Icon(Icons.person_add_alt), tooltip: 'Add friend', onPressed: _add)]),
        body: SafeArea(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: const TextStyle(color: C.error))),
                    if (friends.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: EmptyState(icon: Icons.group_add, title: 'No friends yet', message: 'Add a friend by username, then challenge them to a game. Players you play with via a challenge are added automatically.'),
                      ),
                    for (final p in friends)
                      AppCard(
                        padding: const EdgeInsets.all(10),
                        child: Row(children: [
                          Avatar('${p['username']}', size: 44, url: p['avatar_url'] as String?),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${p['username']}', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                              Row(children: [
                                Icon(Icons.circle, size: 9, color: _online(p) ? C.success : C.border),
                                const SizedBox(width: 4),
                                Text('${_online(p) ? 'Online' : 'Offline'} · ${p['rating']}', style: const TextStyle(color: C.text2, fontSize: 12)),
                              ]),
                            ]),
                          ),
                          FilledButton.tonal(onPressed: () => showChallengeSheet(context, p['id'] as String, '${p['username']}'), child: const Text('Challenge')),
                          PopupMenuButton<String>(
                            onSelected: (_) => _remove(p),
                            itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove friend'))],
                          ),
                        ]),
                      ),
                  ]),
                ),
        ),
      );
}

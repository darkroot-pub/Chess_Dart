import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/multiplayer_service/challenge_service.dart';
import 'common.dart';

/// Wraps the whole app and shows a banner when a friend challenges you.
class ChallengeOverlay extends StatelessWidget {
  final Widget child;
  const ChallengeOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Stack(children: [
        child,
        ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: ChallengeService.instance.incoming,
          builder: (ctx, list, _) {
            if (list.isEmpty) return const SizedBox.shrink();
            final c = list.first;
            final from = (c['from'] as Map?) ?? {};
            final name = '${from['username'] ?? 'A player'}';
            final inc = (c['inc'] ?? 0) as int;
            final tc = '${c['minutes']} min${inc > 0 ? ' + $inc' : ''}';
            return Positioned(
              top: MediaQuery.of(ctx).padding.top + 8, left: 12, right: 12,
              child: Material(
                color: C.surface, elevation: 10, borderRadius: BorderRadius.circular(18), shadowColor: const Color(0x552563EB),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Avatar(name, size: 44, url: from['avatar_url'] as String?),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15), overflow: TextOverflow.ellipsis),
                        Text('challenges you · $tc', style: const TextStyle(color: C.text2, fontSize: 12.5)),
                      ]),
                    ),
                    IconButton(icon: const Icon(Icons.close, color: C.error), onPressed: () => ChallengeService.instance.respond(c, false)),
                    FilledButton(onPressed: () => ChallengeService.instance.respond(c, true), child: const Text('Accept')),
                  ]),
                ),
              ),
            );
          },
        ),
      ]);
}

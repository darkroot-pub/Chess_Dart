import 'package:flutter/material.dart';
import '../../app/nav.dart';
import '../../core/theme/app_theme.dart';
import '../../screens/review/review_screen.dart';
import '../../services/stockfish_service/analysis_jobs.dart';

/// Wraps the whole app. While an analysis runs in the background a small pill shows its progress; when one finishes
/// and the user is not looking at it, a banner offers to open it. Tapping either opens the review.
class AnalysisOverlay extends StatelessWidget {
  final Widget child;
  const AnalysisOverlay({super.key, required this.child});

  void _open(AnalysisJob j) {
    AnalysisJobs.instance.dismissNotice();
    navKey.currentState?.push(MaterialPageRoute(builder: (_) => ReviewScreen(record: j.record)));
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        child,
        ListenableBuilder(
          listenable: AnalysisJobs.instance,
          builder: (ctx, _) {
            final jobs = AnalysisJobs.instance;
            final top = MediaQuery.of(ctx).padding.top + 8;
            final n = jobs.notice;
            if (n != null) {
              return Positioned(
                top: top, left: 12, right: 12,
                child: Material(
                  color: C.surface, elevation: 10, borderRadius: BorderRadius.circular(18), shadowColor: const Color(0x5516A34A),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _open(n),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                      child: Row(children: [
                        const CircleAvatar(backgroundColor: C.success, radius: 18, child: Icon(Icons.check, color: Colors.white)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Game analysis is ready', style: TextStyle(fontWeight: FontWeight.w800)),
                            Text('${n.record.white} vs ${n.record.black}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.text2, fontSize: 12.5)),
                          ]),
                        ),
                        FilledButton(onPressed: () => _open(n), child: const Text('View')),
                        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: jobs.dismissNotice),
                      ]),
                    ),
                  ),
                ),
              );
            }
            final cur = jobs.current;
            if (cur == null || jobs.isViewing(cur.id)) return const SizedBox.shrink();
            return Positioned(
              top: top, left: 0, right: 0,
              child: Center(
                child: Material(
                  color: C.surface, elevation: 6, borderRadius: BorderRadius.circular(24), shadowColor: const Color(0x552563EB),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _open(cur),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 3, value: cur.state == JobState.queued ? null : cur.progress)),
                        const SizedBox(width: 10),
                        Text(
                          cur.paused ? 'Analysis paused while you play' : 'Analysing game… ${(cur.progress * 100).round()}%',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ]);
}

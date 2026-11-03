import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/stockfish_service/analysis_jobs.dart';
import '../../services/stockfish_service/analysis_service.dart' show winPct;

/// Full-screen waiting view for a running analysis: progress ring around the guardian, live evaluation graph that
/// fills in as positions are checked, changing status text, time left, and a clear "continue in background".
class AnalysisWaiting extends StatefulWidget {
  final AnalysisJob job;
  final VoidCallback onBackground;
  final VoidCallback onStop;
  const AnalysisWaiting({super.key, required this.job, required this.onBackground, required this.onStop});
  @override
  State<AnalysisWaiting> createState() => _AnalysisWaitingState();
}

class _AnalysisWaitingState extends State<AnalysisWaiting> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _phase(AnalysisJob j) {
    final total = j.record.ucis.length + 1;
    final done = (j.progress * total).round().clamp(0, total);
    if (j.state == JobState.queued) return 'Waiting for the engine…';
    if (j.paused) return 'Paused while you play a game';
    if (j.progress < 0.04) return 'Setting up the board…';
    final lines = ['Looking for tactics…', 'Checking every move…', 'Searching for better moves…', 'Measuring blunders and brilliancies…', 'Almost there…'];
    final i = j.progress >= 0.92 ? 4 : (j.progress * 4).floor().clamp(0, 3);
    return '${lines[i]}  ($done of $total)';
  }

  String _eta(AnalysisJob j) {
    final e = j.eta;
    if (e == null || j.paused) return '';
    if (e.inSeconds < 10) return 'A few seconds left';
    if (e.inSeconds < 60) return 'About ${e.inSeconds} seconds left';
    return 'About ${(e.inSeconds / 60).ceil()} min left';
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 170,
            height: 170,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(
                painter: _RingPainter(progress: j.progress, t: _c.value, paused: j.paused),
                child: Center(
                  child: Transform.scale(
                    scale: 1 + 0.04 * math.sin(_c.value * 2 * math.pi),
                    child: Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.primary.withAlpha(90), width: 2), boxShadow: const [BoxShadow(color: Color(0x332563EB), blurRadius: 18)]),
                      child: ClipOval(child: Image.asset('assets/images/guardian_head.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.analytics_outlined, size: 48, color: C.primary))),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('${(j.progress * 100).round()}%', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: C.primary)),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: Text(_phase(j), key: ValueKey(_phase(j).split('  ').first), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          const SizedBox(height: 4),
          Text(_eta(j), style: const TextStyle(color: C.text2, fontSize: 12.5)),
          const SizedBox(height: 18),
          SizedBox(
            height: 70,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(painter: _LiveGraphPainter(List<int>.of(j.partial), j.record.ucis.length + 1)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Live evaluation: white area = White is better', style: TextStyle(color: C.text2, fontSize: 11)),
          const SizedBox(height: 22),
          FilledButton.icon(onPressed: widget.onBackground, icon: const Icon(Icons.arrow_back), label: const Text('Continue in background')),
          const SizedBox(height: 6),
          const Text('You can leave this screen. We will tell you when it is ready.', textAlign: TextAlign.center, style: TextStyle(color: C.text2, fontSize: 12)),
          TextButton(onPressed: widget.onStop, child: const Text('Stop analysis')),
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress, t;
  final bool paused;
  _RingPainter({required this.progress, required this.t, required this.paused});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = C.border);
    // a bright comet that keeps circling shows the engine is alive even when a position takes a while
    if (!paused) {
      final a = t * 2 * math.pi - math.pi / 2;
      canvas.drawArc(rect, a, 0.9, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round..color = C.primary.withAlpha(60));
    }
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress.clamp(0.0, 1.0), false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round..color = paused ? C.warning : C.primary);
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.progress != progress || o.t != t || o.paused != paused;
}

class _LiveGraphPainter extends CustomPainter {
  final List<int> evals;
  final int total;
  _LiveGraphPainter(this.evals, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF334155));
    if (evals.isEmpty || total < 2) return;
    final n = total - 1;
    Offset pt(int i) => Offset(i / n * size.width, size.height * (1 - winPct(evals[i]) / 100));
    final path = Path()..moveTo(0, size.height);
    for (int i = 0; i < evals.length; i++) {
      final p = pt(i);
      path.lineTo(p.dx, p.dy);
    }
    path.lineTo(pt(evals.length - 1).dx, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), Paint()..color = const Color(0x66888888));
  }

  @override
  bool shouldRepaint(covariant _LiveGraphPainter o) => o.evals.length != evals.length;
}

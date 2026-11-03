import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../storage_service/storage_service.dart';
import 'analysis_service.dart';

enum JobState { queued, running, done, failed, cancelled }

/// One game analysis. Lives in [AnalysisJobs], NOT in a screen, so it keeps running when the user leaves the review.
class AnalysisJob {
  final GameRecord record;
  final bool deep;
  JobState state = JobState.queued;
  double progress = 0;
  GameAnalysis? result;
  String? error;
  bool cancelRequested = false;
  bool paused = false; // waiting because a game is being played
  final List<int> partial = []; // white-centipawn evaluation of every position finished so far (for the live graph)
  DateTime? startedAt;
  AnalysisJob(this.record, {required this.deep});

  String get id => record.id;
  bool get active => state == JobState.queued || state == JobState.running;

  /// Rough time left, from the speed so far. Null until there is enough progress to say anything useful.
  Duration? get eta {
    final t = startedAt;
    if (t == null || progress < 0.08 || progress >= 1) return null;
    final spent = DateTime.now().difference(t);
    return Duration(milliseconds: (spent.inMilliseconds * (1 - progress) / progress).round());
  }
}

/// Runs game analyses one at a time in the background, remembers the results on the phone, and tells the UI
/// (through listeners) about progress and completion. One engine is shared with the bot, so a job pauses while a
/// game is being played ([hold]/[release]).
class AnalysisJobs extends ChangeNotifier {
  static final AnalysisJobs instance = AnalysisJobs._();
  AnalysisJobs._();

  StorageService? _store;
  final Map<String, AnalysisJob> _jobs = {};
  final Queue<AnalysisJob> _queue = Queue();
  final Set<String> _viewing = {};
  Set<String> _cached = {};
  bool _running = false;
  int _holds = 0;

  /// The job that just finished while nobody was looking at it (drives the "analysis ready" banner).
  AnalysisJob? notice;
  Timer? _noticeTimer;

  /// Notifies after the current frame's build phase. Screens call into this from initState, where notifying
  /// synchronously would make listening widgets rebuild in the middle of a build.
  void _ping() => Future.microtask(notifyListeners);

  void bind(StorageService store) {
    _store = store;
    _cached = store.analysisIndex().toSet();
  }

  AnalysisJob? jobFor(String id) => _jobs[id];
  bool hasResult(String id) => _cached.contains(id) || (_jobs[id]?.state == JobState.done);
  Iterable<AnalysisJob> get activeJobs => _jobs.values.where((j) => j.active);
  AnalysisJob? get current {
    for (final j in _jobs.values) {
      if (j.state == JobState.running) return j;
    }
    return _queue.isEmpty ? null : _queue.first;
  }

  // ---- the screen tells us whether somebody is looking, so a finished job only notifies when nobody is ----
  void attach(String id) {
    _viewing.add(id);
    if (notice?.id == id) _clearNotice();
    _ping(); // hides the background pill for the job that is now on screen
  }
  void detach(String id) {
    _viewing.remove(id);
    _ping();
  }
  bool isViewing(String id) => _viewing.contains(id);

  void hold() { _holds++; notifyListeners(); }
  void release() {
    if (_holds > 0) _holds--;
    notifyListeners();
  }

  GameAnalysis? _load(String id) {
    final raw = _store?.loadAnalysisJson(id);
    if (raw == null) return null;
    try {
      return GameAnalysis.tryFromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  /// Returns the job for [record]. A stored result is reused (no engine work) unless a deeper one is requested.
  AnalysisJob startFor(GameRecord record, {bool deep = false, bool force = false}) {
    final existing = _jobs[record.id];
    if (existing != null && existing.active && (existing.deep || !deep)) return existing; // already on it
    if (!force) {
      final have = existing?.state == JobState.done ? existing!.result : _load(record.id);
      if (have != null && (have.depth >= 18 || !deep)) {
        final j = AnalysisJob(record, deep: have.depth >= 18)
          ..state = JobState.done
          ..progress = 1
          ..result = have;
        _jobs[record.id] = j;
        return j;
      }
    }
    final job = AnalysisJob(record, deep: deep);
    if (record.ucis.isEmpty) {
      job.state = JobState.failed;
      job.error = 'This game has no moves to analyse.';
      _jobs[record.id] = job;
      _ping();
      return job;
    }
    // a deeper re-run keeps showing the old result until it is replaced
    job.result = existing?.result ?? _load(record.id);
    _jobs[record.id] = job;
    _queue.add(job);
    _ping();
    unawaited(_pump());
    return job;
  }

  void cancel(String id) {
    final j = _jobs[id];
    if (j == null || !j.active) return;
    j.cancelRequested = true;
    if (j.state == JobState.queued) {
      _queue.remove(j);
      j.state = JobState.cancelled;
    }
    notifyListeners();
  }

  Future<void> _gate(AnalysisJob job) async {
    if (_holds == 0) return;
    job.paused = true;
    notifyListeners();
    while (_holds > 0 && !job.cancelRequested) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    job.paused = false;
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeFirst();
        if (job.cancelRequested) continue;
        await _run(job);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(AnalysisJob job) async {
    job.state = JobState.running;
    job.startedAt = DateTime.now();
    notifyListeners();
    GameAnalysis? r;
    try {
      r = await AnalysisService.analyse(
        job.record.startFen,
        job.record.ucis,
        movetimeMs: job.deep ? 9000 : 3000,
        depth: job.deep ? 18 : 14,
        gate: () => _gate(job),
        cancelled: () => job.cancelRequested,
        onPosition: (i, cp) {
          job.partial.add(cp);
        },
        onProgress: (p) {
          job.progress = p;
          notifyListeners();
        },
      );
    } catch (_) {
      r = null;
    }
    if (job.cancelRequested) {
      job.state = JobState.cancelled;
    } else if (r == null) {
      job.state = JobState.failed;
      job.error = 'The analysis could not be completed (the engine did not answer, or the game record is invalid). Nothing was classified.';
    } else {
      job.result = r;
      job.progress = 1;
      job.state = JobState.done;
      try {
        await _store?.saveAnalysisJson(job.id, jsonEncode(r.toJson()));
        _cached.add(job.id);
      } catch (_) {/* the result is still shown; it just is not remembered */}
      if (!_viewing.contains(job.id)) {
        notice = job;
        HapticFeedback.mediumImpact();
        _noticeTimer?.cancel();
        _noticeTimer = Timer(const Duration(seconds: 10), _clearNotice);
      }
    }
    notifyListeners();
  }

  void _clearNotice() {
    _noticeTimer?.cancel();
    if (notice != null) {
      notice = null;
      _ping();
    }
  }

  void dismissNotice() => _clearNotice();
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Interactive "3D" character: 48 pre-rendered turntable frames scrubbed by drag.
/// Drag = rotate with inertia, pinch = zoom, double-tap = spin, idle = slow auto-rotate + floating bob.
class CharacterViewer extends StatefulWidget {
  static const frames = 48;
  static String frame(int i) => 'assets/character/kindred/k${(i % frames).toString().padLeft(2, '0')}.webp';
  final bool interactive;
  final bool autoRotate;
  final double? height;
  const CharacterViewer({super.key, this.interactive = true, this.autoRotate = true, this.height});

  @override
  State<CharacterViewer> createState() => _CharacterViewerState();
}

class _CharacterViewerState extends State<CharacterViewer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _angle = 0; // in frames (0..48)
  double _vel = 0; // frames per second
  double _zoom = 1, _zoom0 = 1;
  bool _dragging = false;
  double _idle = 0; // seconds since last touch
  double _t = 0; // time for bob
  bool _ready = false;
  int _lastTick = -1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready) {
      _ready = true;
      for (int i = 0; i < CharacterViewer.frames; i++) {
        precacheImage(AssetImage(CharacterViewer.frame(i)), context);
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration d) {
    final dt = ((d - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = d;
    _t += dt;
    if (!_dragging) {
      _idle += dt;
      _angle += _vel * dt;
      _vel *= math.pow(0.04, dt).toDouble(); // friction
      if (widget.autoRotate && _idle > 1.6 && _vel.abs() < 3) {
        _vel += (3.2 - _vel) * math.min(1, dt * 1.5); // ease into the idle spin
      }
      if (_zoom != 1 && _idle > 3) _zoom += (1 - _zoom) * math.min(1, dt * 2);
    }
    _angle = _angle % CharacterViewer.frames;
    if (_angle < 0) _angle += CharacterViewer.frames;
    setState(() {});
  }

  void _spin() {
    HapticFeedback.mediumImpact();
    _vel = 60;
    _idle = 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _angle.round() % CharacterViewer.frames;
    if (idx != _lastTick && _dragging) {
      _lastTick = idx;
    }
    final bob = math.sin(_t * 1.6) * 5;
    final glow = 0.5 + 0.5 * math.sin(_t * 1.2);
    return LayoutBuilder(builder: (context, c) {
      final h = widget.height ?? c.maxHeight;
      final w = c.maxWidth.isFinite ? c.maxWidth : h * 0.82;
      Widget body = SizedBox(
        width: w,
        height: h,
        child: Stack(alignment: Alignment.center, children: [
          // soft glow behind the character
          Positioned.fill(
            child: Center(
              child: Container(
                width: h * 0.78,
                height: h * 0.78,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color.fromRGBO(167, 139, 250, 0.42 + 0.18 * glow), const Color(0x00A78BFA)])),
              ),
            ),
          ),
          // ground shadow, shrinks as the character floats up
          Positioned(
            bottom: h * 0.02,
            child: Container(
              width: h * 0.42 * (1 - bob / 90),
              height: h * 0.05,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(100), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, spreadRadius: 2)]),
            ),
          ),
          Transform.translate(
            offset: Offset(0, -bob - 6),
            child: Transform.scale(
              scale: _zoom,
              child: Image.asset(CharacterViewer.frame(idx), height: h * 0.94, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium),
            ),
          ),
        ]),
      );
      if (!widget.interactive) return body;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _spin,
        onScaleStart: (d) {
          _dragging = true;
          _vel = 0;
          _idle = 0;
          _zoom0 = _zoom;
        },
        onScaleUpdate: (d) {
          _idle = 0;
          // one full turn per ~1.1x widget width of drag
          final df = d.focalPointDelta.dx / w * CharacterViewer.frames * 0.9;
          _angle -= df;
          _vel = -df * 60;
          if (d.pointerCount > 1) _zoom = (_zoom0 * d.scale).clamp(0.8, 2.2);
        },
        onScaleEnd: (d) {
          _dragging = false;
          _vel = _vel.clamp(-120.0, 120.0);
        },
        child: body,
      );
    });
  }
}

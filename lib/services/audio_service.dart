import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class AudioService {
  static final AudioService instance = AudioService._();
  AudioService._();
  final AudioPlayer _player = AudioPlayer();
  bool sound = true, vibration = true;

  Future<void> play(String name) async {
    if (!sound) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$name.wav'));
    } catch (_) {}
  }

  void haptic({bool heavy = false}) {
    if (!vibration) return;
    heavy ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
  }
}

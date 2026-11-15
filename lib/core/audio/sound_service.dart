import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../constants/app_constants.dart';

class SoundService {
  final AudioPlayer _sfxPlayer = AudioPlayer();
  final AudioPlayer _musicPlayer = AudioPlayer();

  bool _isDisposed = false;

  /// Preload SFX asset
  Future<void> init() async {
    try {
      await _sfxPlayer.setAsset(AppConstants.buzzerSfxPath);
    } catch (e) {
      debugPrint('SFX asset init warning: $e');
    }
  }

  /// Plays the buzzer sound effect instantly
  Future<void> playBuzzer() async {
    try {
      if (_sfxPlayer.playing) {
        await _sfxPlayer.stop();
      }
      await _sfxPlayer.seek(Duration.zero);
      await _sfxPlayer.play();
    } catch (e) {
      debugPrint('Failed to play buzzer sound: $e');
    }
  }

  /// Loads and prepares a streaming trivia audio clue URL
  Future<void> loadAudioClue(String url) async {
    try {
      await _musicPlayer.setUrl(url);
    } catch (e) {
      debugPrint('Failed to load audio clue: $e');
    }
  }

  /// Plays the streaming trivia audio clue
  Future<void> playAudioClue() async {
    try {
      await _musicPlayer.play();
    } catch (e) {
      debugPrint('Failed to play audio clue: $e');
    }
  }

  /// Immediately ducks / pauses clue audio when a player buzzes in
  Future<void> duckAudioOnBuzz() async {
    try {
      if (_musicPlayer.playing) {
        await _musicPlayer.pause();
      }
    } catch (e) {
      debugPrint('Failed to duck audio on buzz: $e');
    }
  }

  /// Stops and resets trivia audio
  Future<void> stopAudioClue() async {
    try {
      await _musicPlayer.stop();
    } catch (e) {
      debugPrint('Failed to stop audio clue: $e');
    }
  }

  Stream<PlayerState> get audioPlayerStateStream => _musicPlayer.playerStateStream;
  Stream<Duration> get audioPositionStream => _musicPlayer.positionStream;
  Stream<Duration?> get audioDurationStream => _musicPlayer.durationStream;

  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      _sfxPlayer.dispose();
      _musicPlayer.dispose();
    }
  }
}

final soundServiceProvider = Provider<SoundService>((ref) {
  final service = SoundService();
  service.init();
  ref.onDispose(() => service.dispose());
  return service;
});

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/vocab_word.dart';

const String _kMusicKey = 'music_on';

/// Hiệu ứng âm thanh ngắn.
enum Sfx {
  tap('audio/sfx/tap.mp3'),
  correct('audio/sfx/correct.mp3'),
  wrong('audio/sfx/wrong.mp3'),
  star('audio/sfx/star.mp3');

  const Sfx(this.asset);
  final String asset;
}

const String _kMusicAsset = 'audio/music/bg.mp3';
const double _kMusicVolume = 0.25;

/// Phát âm thanh đóng gói sẵn trong app (từ, câu ví dụ, hiệu ứng, nhạc nền).
/// Mọi lỗi phát được nuốt và ghi log để app không bao giờ crash vì âm thanh.
class AudioService with WidgetsBindingObserver {
  AudioService._();
  static final AudioService instance = AudioService._();

  /// Tắt hẳn (dùng trong test, nơi không có plugin âm thanh).
  @visibleForTesting
  bool disabled = false;

  AudioPlayer? _speech;
  AudioPlayer? _sfx;
  AudioPlayer? _music;
  SharedPreferences? _prefs;
  bool _initialized = false;

  /// Chỉ dùng trong test: cho phép gọi init() lại với prefs mới.
  @visibleForTesting
  void resetForTest() {
    _initialized = false;
    _prefs = null;
    musicOn.value = true;
  }

  /// Nhạc nền đang bật hay tắt (lưu lại giữa các lần mở app).
  final ValueNotifier<bool> musicOn = ValueNotifier(true);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      musicOn.value = _prefs?.getBool(_kMusicKey) ?? true;
    } catch (e) {
      debugPrint('Audio prefs failed: $e');
    }
    if (disabled) return;
    try {
      // Cho phép nhạc nền, giọng đọc và hiệu ứng phát cùng lúc, không giành focus.
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
    } catch (e) {
      debugPrint('Audio context failed: $e');
    }
    WidgetsBinding.instance.addObserver(this);
    if (musicOn.value) await _startMusic();
  }

  AudioPlayer get _speechPlayer => _speech ??= AudioPlayer();
  AudioPlayer get _sfxPlayer =>
      _sfx ??= (AudioPlayer()..setPlayerMode(PlayerMode.lowLatency));
  AudioPlayer get _musicPlayer => _music ??= AudioPlayer();

  /// `assets/audio/x.mp3` (đường dẫn trong vocab.json) -> `audio/x.mp3`.
  static String assetKey(String path) =>
      path.startsWith('assets/') ? path.substring('assets/'.length) : path;

  Future<void> playWord(VocabWord word) => _playSpeech(word.audio);

  Future<void> playExample(VocabWord word) async {
    final path = word.exampleAudio;
    if (path != null) await _playSpeech(path);
  }

  Future<void> _playSpeech(String path) async {
    if (disabled) return;
    try {
      final p = _speechPlayer;
      await p.stop();
      await p.play(AssetSource(assetKey(path)));
    } catch (e) {
      debugPrint('Speech failed ($path): $e');
    }
  }

  Future<void> playSfx(Sfx sfx) async {
    if (disabled) return;
    try {
      final p = _sfxPlayer;
      await p.stop();
      await p.play(AssetSource(sfx.asset), volume: 0.8);
    } catch (e) {
      debugPrint('Sfx failed (${sfx.name}): $e');
    }
  }

  Future<void> setMusicOn(bool on) async {
    musicOn.value = on;
    try {
      await _prefs?.setBool(_kMusicKey, on);
    } catch (e) {
      debugPrint('Audio prefs save failed: $e');
    }
    if (disabled) return;
    if (on) {
      await _startMusic();
    } else {
      try {
        await _music?.stop();
      } catch (e) {
        debugPrint('Music stop failed: $e');
      }
    }
  }

  Future<void> _startMusic() async {
    if (disabled) return;
    try {
      final p = _musicPlayer;
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(AssetSource(_kMusicAsset), volume: _kMusicVolume);
    } catch (e) {
      debugPrint('Music failed: $e');
    }
  }

  /// Tạm dừng nhạc khi app xuống nền, phát tiếp khi quay lại.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (disabled) return;
    try {
      if (state == AppLifecycleState.resumed) {
        if (musicOn.value) _music?.resume();
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        _music?.pause();
        _speech?.stop();
      }
    } catch (e) {
      debugPrint('Audio lifecycle failed: $e');
    }
  }
}

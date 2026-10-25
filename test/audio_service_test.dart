import 'dart:io';

import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/services/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AudioService.instance
      ..disabled = true
      ..resetForTest();
  });

  test('assetKey bỏ tiền tố assets/ (audioplayers tự thêm)', () {
    expect(
      AudioService.assetKey('assets/audio/words/book.mp3'),
      'audio/words/book.mp3',
    );
    expect(AudioService.assetKey('audio/sfx/tap.mp3'), 'audio/sfx/tap.mp3');
  });

  test(
    'mọi đường dẫn trong vocab.json và Sfx đều trỏ tới file có thật',
    () async {
      final repo = await VocabRepository.load();
      for (final w in repo.words) {
        expect(File(w.audio).existsSync(), isTrue, reason: w.audio);
        expect(
          File(w.exampleAudio!).existsSync(),
          isTrue,
          reason: w.exampleAudio,
        );
      }
      for (final s in Sfx.values) {
        expect(File('assets/${s.asset}').existsSync(), isTrue, reason: s.asset);
      }
      expect(File('assets/audio/music/bg.mp3').existsSync(), isTrue);
    },
  );

  test('nhạc nền: mặc định bật, tắt rồi nhớ lại ở lần mở sau', () async {
    SharedPreferences.setMockInitialValues({});
    await AudioService.instance.init();
    expect(AudioService.instance.musicOn.value, isTrue);

    await AudioService.instance.setMusicOn(false);
    expect(AudioService.instance.musicOn.value, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool('music_on'),
      isFalse,
    );

    // Mở app lần sau.
    AudioService.instance.resetForTest();
    await AudioService.instance.init();
    expect(AudioService.instance.musicOn.value, isFalse);
  });
}

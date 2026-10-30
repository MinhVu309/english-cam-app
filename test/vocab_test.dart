import 'dart:io';

import 'package:english_cam/core/theme.dart';
import 'package:english_cam/data/bundled_images.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/data/vocab_word.dart';
import 'package:english_cam/features/vocab/vocab_detail_screen.dart';
import 'package:english_cam/features/vocab/vocab_list_screen.dart';
import 'package:english_cam/features/vocab/word_visual.dart';
import 'package:english_cam/services/audio_service.dart';
import 'package:english_cam/services/progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget home) => MaterialApp(theme: buildAppTheme(), home: home);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VocabRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AudioService.instance.disabled = true;
    repo = await VocabRepository.load();
    await ProgressService.instance.init();
  });

  test(
    'vocab.json bao phủ labels.txt (24 nhãn) và có thêm từ chỉ để học',
    () async {
      final labels = (await rootBundle.loadString(
        'assets/ml/labels.txt',
      )).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

      expect(labels, hasLength(24));
      final withLabel = repo.words.where((w) => w.label != null).toList();
      expect(withLabel.map((w) => w.label).toSet(), labels.toSet());
      expect(repo.words.length, greaterThan(labels.length));
      // Từ không có label chỉ để học: không làm đích game "Tìm vật".
      for (final w in repo.words.where((w) => w.label == null)) {
        expect(w.hunt, isFalse, reason: w.id);
        expect(w.hasPicture, isTrue, reason: w.id);
      }
      for (final w in repo.words) {
        expect(w.en, isNotEmpty);
        expect(w.vi, isNotEmpty);
        expect(w.phonetic, isNotEmpty);
        expect(repo.category(w.category), isNotNull, reason: w.id);
        expect(w.audio, endsWith('/${w.id}.mp3'));
      }
      expect(repo.byLabel('teddy_bear')!.en, 'teddy bear');
    },
  );

  testWidgets('Danh sách: hiện đủ từ, tìm kiếm và lọc chủ đề', (tester) async {
    tester.view.physicalSize = const Size(2400, 40000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const VocabListScreen()));
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('apple'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'chuối');
    await tester.pump();
    expect(find.text('banana'), findsOneWidget);
    expect(find.text('apple'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    expect(find.textContaining('Chưa tìm thấy'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    // Hàng chip cuộn ngang và font test rất rộng, nên gọi thẳng onSelected.
    final chip = find.widgetWithText(
      ChoiceChip,
      'Trái cây',
    ); // chủ đề có ảnh: chip không còn emoji
    tester.widget<ChoiceChip>(chip).onSelected!(true);
    await tester.pump();
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('book'), findsNothing);
  });

  testWidgets('Chi tiết: đánh dấu đã học và nhớ lại', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final word = repo.byLabel('apple')!;
    await tester.pumpWidget(_app(VocabDetailScreen(word: word)));

    expect(ProgressService.instance.isLearned('apple'), isFalse);
    await tester.tap(find.text('Mình đã học từ này'));
    await tester.pump();

    expect(ProgressService.instance.isLearned('apple'), isTrue);
    expect(find.text('Đã học rồi!'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('learned_words'), ['apple']);
  });

  group('Ảnh minh hoạ thay cho emoji', () {
    List<String> idsIn(String dir) => [
      for (final f in Directory(dir).listSync().whereType<File>())
        f.uri.pathSegments.last.replaceAll('.webp', ''),
    ];

    test(
      'mỗi file ảnh trong assets/images/words và categories khớp một mã trong vocab.json (bắt lỗi chính tả tên file)',
      () {
        final words = repo.words.map((w) => w.id).toSet();
        final cats = repo.categories.map((c) => c.id).toSet();
        expect(
          idsIn('assets/images/words').toSet().difference(words),
          isEmpty,
          reason: 'ảnh từ không có từ tương ứng',
        );
        expect(
          idsIn('assets/images/categories').toSet().difference(cats),
          isEmpty,
          reason: 'ảnh chủ đề không có chủ đề',
        );
        expect(
          Directory(
            'assets/images/words',
          ).listSync().whereType<File>().every((f) => f.path.endsWith('.webp')),
          isTrue,
        );
      },
    );

    test(
      'ảnh nhẹ: mỗi ảnh từ dưới 150 KB, ảnh chủ đề dưới 60 KB, tổng dưới 2 MB (giữ APK nhỏ)',
      () {
        var total = 0;
        for (final f in Directory(
          'assets/images/words',
        ).listSync().whereType<File>()) {
          expect(f.lengthSync(), lessThan(150 * 1024), reason: f.path);
          total += f.lengthSync();
        }
        for (final f in Directory(
          'assets/images/categories',
        ).listSync().whereType<File>()) {
          expect(f.lengthSync(), lessThan(60 * 1024), reason: f.path);
          total += f.lengthSync();
        }
        expect(total, lessThan(2 * 1024 * 1024));
      },
    );

    test(
      'mọi từ đều có ảnh: ảnh đóng gói theo mã từ (4 từ màu dùng viên bi vẽ sẵn)',
      () {
        expect(repo.byId('cat')!.image, 'assets/images/words/cat.webp');
        expect(
          repo.byId('elephant')!.image,
          'assets/images/words/elephant.webp',
        );
        expect(repo.byId('apple')!.image, 'assets/images/words/apple.webp');
        const colours = {'red', 'green', 'blue', 'yellow'};
        for (final w in repo.words.where((w) => !colours.contains(w.id))) {
          expect(w.image, 'assets/images/words/${w.id}.webp', reason: w.id);
        }
        expect(
          repo.words.every((w) => w.image != null),
          isTrue,
          reason: 'không còn từ nào chỉ có emoji',
        );
        // 4 từ màu giữ ảnh viên bi có sẵn trong vocab.json (đẹp hơn mảng màu phẳng, và không dính watermark).
        for (final c in ['red', 'green', 'blue', 'yellow']) {
          expect(repo.byId(c)!.image, 'assets/images/colors/$c.png');
        }
        expect(
          repo.category('animals')!.image,
          'assets/images/categories/animals.webp',
        );
        expect(
          repo.category('clothes')!.image,
          'assets/images/categories/clothes.webp',
        );
        expect(repo.categories.every((c) => c.image != null), isTrue);
      },
    );

    test(
      'mọi ảnh khai báo đều đọc được từ asset bundle (không thiếu trong pubspec)',
      () async {
        for (final w in repo.words.where(
          (w) => w.image != null && w.image!.startsWith(BundledImages.wordsDir),
        )) {
          final data = await rootBundle.load(w.image!);
          expect(data.lengthInBytes, greaterThan(1000), reason: w.id);
          // WebP: "RIFF....WEBP"
          expect(
            String.fromCharCodes(data.buffer.asUint8List(0, 4)),
            'RIFF',
            reason: w.id,
          );
          expect(
            String.fromCharCodes(data.buffer.asUint8List(8, 4)),
            'WEBP',
            reason: w.id,
          );
        }
      },
    );

    test(
      'từ vựng của gói cập nhật (image: null) vẫn có ảnh đóng gói theo mã; gói tự khai báo ảnh thì ảnh của gói thắng',
      () {
        VocabWord parse(Map<String, dynamic> extra) => VocabWord.fromJson({
          'id': 'cat',
          'en': 'cat',
          'vi': 'mèo',
          'phonetic': '/kæt/',
          'exampleEn': 'x',
          'exampleVi': 'y',
          'audio': 'audio/words/cat.mp3',
          'category': 'animals',
          ...extra,
        });
        expect(parse({'image': null}).image, 'assets/images/words/cat.webp');
        expect(parse({}).image, 'assets/images/words/cat.webp');
        expect(
          parse({'image': 'images/cat-new.png'}).image,
          'images/cat-new.png',
        );
        BundledImages.setForTest(); // không có ảnh đóng gói nào
        expect(parse({}).image, isNull);
      },
    );

    testWidgets(
      'WordVisual: có ảnh thì vẽ ảnh cắt tròn; chưa có ảnh thì vẫn là emoji; không emoji thì chữ cái',
      (tester) async {
        Future<void> show(VocabWord w) => tester.pumpWidget(
          _app(Center(child: WordVisual(word: w, size: 100))),
        );
        await show(repo.byId('cat')!);
        expect(find.byType(Image), findsOneWidget);
        expect(find.byType(ClipOval), findsWidgets);
        expect(
          find.text(repo.byId('cat')!.emoji!),
          findsNothing,
          reason: 'ảnh thay emoji',
        );

        // Từ không có ảnh đóng gói (vd. từ mới của gói cập nhật): emoji, rồi chữ cái đầu.
        VocabWord noPhoto({String? emoji}) => VocabWord.fromJson({
          'id': 'zebra',
          'en': 'zebra',
          'vi': 'ngựa vằn',
          'phonetic': '/z/',
          'exampleEn': 'x',
          'exampleVi': 'y',
          'audio': 'audio/words/zebra.mp3',
          'category': 'animals',
          'emoji': emoji,
        });
        await show(noPhoto(emoji: '🦓'));
        expect(find.byType(Image), findsNothing);
        expect(find.text('🦓'), findsOneWidget);

        await show(noPhoto());
        expect(
          find.text('Z'),
          findsOneWidget,
          reason: 'không ảnh, không emoji: chữ cái đầu',
        );
      },
    );

    testWidgets(
      'Danh sách từ vựng: thẻ từ có ảnh dùng ảnh; chip chủ đề có ảnh đại diện',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(const VocabListScreen()));
        await tester.pump();
        final chip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Đồ dùng học tập'),
        );
        expect(chip.avatar, isNotNull);
        expect(find.byType(Image), findsWidgets);
      },
    );
  });
}

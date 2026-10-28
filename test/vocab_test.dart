import 'package:english_cam/core/theme.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/features/vocab/vocab_detail_screen.dart';
import 'package:english_cam/features/vocab/vocab_list_screen.dart';
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
    final chip = find.widgetWithText(ChoiceChip, '🍎 Trái cây');
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
}

import 'dart:math';

import 'package:english_cam/core/theme.dart';
import 'package:english_cam/data/game_badge.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/features/game/hunt/hunt_logic.dart';
import 'package:english_cam/features/game/match/match_questions.dart';
import 'package:english_cam/features/game/match/matching_game_screen.dart';
import 'package:english_cam/ml/classifier_service.dart';
import 'package:english_cam/services/audio_service.dart';
import 'package:english_cam/services/game_progress.dart';
import 'package:english_cam/services/progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ClassificationResult _result(String label, double p) => ClassificationResult(
  top: [Prediction(label, p), const Prediction('zzz', 0.01)],
  inferenceMs: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VocabRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AudioService.instance.disabled = true;
    repo = await VocabRepository.load();
    await BadgeRepository.load();
    await ProgressService.instance.init();
    GameProgress.instance.resetForTest();
    await GameProgress.instance.init();
  });

  group('Nghe & chọn hình: tạo câu hỏi', () {
    test(
      'chỉ dùng từ có hình; mỗi câu có 4 đáp án khác nhau chứa đáp án đúng',
      () {
        final pool = matchPool(repo.words);
        expect(pool.every((w) => w.hasPicture), isTrue);
        expect(
          pool.length,
          lessThan(repo.words.length),
        ); // table, towel không có hình

        final qs = buildMatchQuestions(pool, Random(3));
        expect(qs, hasLength(kMatchQuestions));
        for (final q in qs) {
          expect(q.options, hasLength(kMatchOptions));
          expect(q.options.map((w) => w.id).toSet(), hasLength(kMatchOptions));
          expect(q.options.any((w) => w.id == q.target.id), isTrue);
        }
        // Mỗi từ làm đáp án đúng nhiều nhất một lần trong ván.
        expect(qs.map((q) => q.target.id).toSet(), hasLength(kMatchQuestions));
      },
    );

    test('cùng seed cho cùng câu hỏi, khác seed thì khác', () {
      final pool = matchPool(repo.words);
      List<String> ids(int seed) => [
        for (final q in buildMatchQuestions(pool, Random(seed))) q.target.id,
      ];
      expect(ids(1), ids(1));
      expect(ids(1), isNot(ids(2)));
    });
  });

  group('Tìm vật: logic', () {
    test('thành công khi nhãn cao nhất đúng và đủ chắc', () {
      expect(isHuntSuccess(_result('pen', 0.8), 'pen'), isTrue);
      expect(isHuntSuccess(_result('pen', kHuntThreshold), 'pen'), isTrue);
      expect(isHuntSuccess(_result('pen', 0.49), 'pen'), isFalse);
      expect(isHuntSuccess(_result('cup', 0.95), 'pen'), isFalse);
    });

    test(
      'không bao giờ chọn nhãn yếu (apple, table) và không lặp lại ngay',
      () {
        final rng = Random(5);
        String? prev;
        for (var i = 0; i < 300; i++) {
          final w = pickHuntTarget(repo.words, rng, previous: prev);
          expect(w.hunt, isTrue);
          expect(['apple', 'table'], isNot(contains(w.id)));
          expect(w.id, isNot(prev));
          prev = w.id;
        }
      },
    );
  });

  group('Sao và huy hiệu', () {
    test('cộng sao, không bao giờ trừ, mở huy hiệu đúng ngưỡng', () async {
      var unlocked = await GameProgress.instance.recordRound(
        starsEarned: 0,
        perfect: false,
      );
      expect(GameProgress.instance.stars, 0); // sai hết cũng không bị trừ
      expect(unlocked.map((b) => b.id), ['first_round']);

      unlocked = await GameProgress.instance.recordRound(
        starsEarned: 8,
        perfect: true,
      );
      expect(unlocked.map((b) => b.id), ['perfect']);
      expect(GameProgress.instance.stars, 8);

      unlocked = await GameProgress.instance.recordFound();
      expect(GameProgress.instance.stars, 10);
      expect(unlocked.map((b) => b.id), containsAll(['stars_10', 'finder_1']));
      // Huy hiệu đã có thì không báo lại.
      unlocked = await GameProgress.instance.recordFound();
      expect(unlocked.map((b) => b.id), isNot(contains('finder_1')));
    });

    test('lưu và nhớ lại tiến độ giữa các lần mở app', () async {
      await GameProgress.instance.recordRound(starsEarned: 5, perfect: false);
      await GameProgress.instance.recordFound();

      GameProgress.instance.resetForTest();
      expect(GameProgress.instance.stars, 0);
      await GameProgress.instance.init();

      expect(GameProgress.instance.stars, 7);
      expect(GameProgress.instance.rounds, 1);
      expect(GameProgress.instance.found, 1);
      expect(GameProgress.instance.hasBadge('first_round'), isTrue);
    });

    test('huy hiệu "Chăm học" dựa trên số từ đã học', () async {
      for (final w in repo.words.take(10)) {
        await ProgressService.instance.setLearned(w.id, true);
      }
      final unlocked = GameProgress.instance.checkBadges();
      expect(unlocked.map((b) => b.id), contains('learner_10'));
    });
  });

  group('Nghe & chọn hình: màn chơi', () {
    Future<void> pumpGame(WidgetTester tester, int seed) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: MatchingGameScreen(random: Random(seed)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Đáp án đúng/sai của câu đầu tiên theo cùng seed.
    ({String correct, String wrong}) firstQuestion(int seed) {
      final q = buildMatchQuestions(matchPool(repo.words), Random(seed)).first;
      return (
        correct: q.target.id,
        wrong: q.options.firstWhere((w) => w.id != q.target.id).id,
      );
    }

    Finder option(String id) {
      final word = repo.byId(id)!;
      return find
          .byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Đáp án',
          )
          .at(
            buildMatchQuestions(
              matchPool(repo.words),
              Random(7),
            ).first.options.indexWhere((o) => o.id == word.id),
          );
    }

    testWidgets('chọn sai: khuyến khích, không trừ sao, vẫn ở câu cũ', (
      tester,
    ) async {
      await pumpGame(tester, 7);
      final q = firstQuestion(7);

      await tester.tap(option(q.wrong));
      await tester.pump();

      expect(find.textContaining('thử lại nhé'), findsOneWidget);
      expect(find.text('1/8'), findsOneWidget);
      expect(find.text('⭐ 0'), findsOneWidget);
    });

    testWidgets('chọn đúng ngay lần đầu: +1 sao rồi sang câu sau', (
      tester,
    ) async {
      await pumpGame(tester, 7);
      final q = firstQuestion(7);

      await tester.tap(option(q.correct));
      await tester.pump();
      expect(find.textContaining('Giỏi quá'), findsOneWidget);
      expect(find.text('⭐ 1'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1400));
      expect(find.text('2/8'), findsOneWidget);
    });

    testWidgets('sai rồi mới đúng: sang câu sau nhưng không có sao', (
      tester,
    ) async {
      await pumpGame(tester, 7);
      final q = firstQuestion(7);

      await tester.tap(option(q.wrong));
      await tester.pump();
      await tester.tap(option(q.correct));
      await tester.pump(const Duration(milliseconds: 1400));

      expect(find.text('2/8'), findsOneWidget);
      expect(find.text('⭐ 0'), findsOneWidget);
    });

    testWidgets('chơi hết ván: hiện tổng kết, lưu sao và mở huy hiệu', (
      tester,
    ) async {
      await pumpGame(tester, 7);
      final qs = buildMatchQuestions(matchPool(repo.words), Random(7));

      for (var i = 0; i < qs.length; i++) {
        final idx = qs[i].options.indexWhere((o) => o.id == qs[i].target.id);
        await tester.tap(
          find
              .byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Đáp án',
              )
              .at(idx),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1400));
      }
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('⭐ 8 / 8'), findsOneWidget);
      expect(GameProgress.instance.stars, 8);
      expect(GameProgress.instance.hasBadge('perfect'), isTrue);
      expect(find.text('Huy hiệu mới! 🎉'), findsOneWidget);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:english_cam/core/text_fold.dart';
import 'package:english_cam/core/theme.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/features/result/result_screen.dart';
import 'package:english_cam/features/result/type_answer_dialog.dart';
import 'package:english_cam/ml/classifier_service.dart';
import 'package:english_cam/services/auth_service.dart';
import 'package:english_cam/services/feedback_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PNG 1x1 hợp lệ (màn kết quả cần một file ảnh thật để đọc kích thước).
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

ClassificationResult _result({double hat = 0.81}) => ClassificationResult(
  top: [
    Prediction('hat', hat),
    const Prediction('umbrella', 0.09),
    const Prediction('towel', 0.06),
  ],
  inferenceMs: 12,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String photo;
  late FeedbackService feedback;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await VocabRepository.load();
    tmp = await Directory.systemTemp.createTemp('result_fb');
    photo = '${tmp.path}/p.png';
    File(photo).writeAsBytesSync(_png);
    feedback = FeedbackService.instance = FeedbackService(
      auth: AuthService(),
      autoFlush: false,
    );
  });

  tearDown(() async {
    FeedbackService.instance = FeedbackService();
    await tmp.delete(recursive: true);
  });

  Future<void> open(
    WidgetTester tester, {
    ClassificationResult? result,
    Key? key,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ResultScreen(
          key: key,
          imagePath: photo,
          classify: (_) async => result ?? _result(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.text('Không đúng?'));
    await tester.pump();
  }

  group('chọn trong gợi ý', () {
    testWidgets(
      'mở "Không đúng?": 3 gợi ý và "Khác…"; chưa chọn gì thì chưa có góp ý, chưa cảm ơn',
      (tester) async {
        await open(tester);
        expect(
          find.text('hat'),
          findsOneWidget,
          reason: 'banner của kết quả đang hiện',
        );
        await openPanel(tester);
        for (final w in ['hat', 'umbrella', 'towel']) {
          expect(find.widgetWithText(ChoiceChip, w), findsOneWidget);
        }
        expect(find.byKey(const Key('other-answer')), findsOneWidget);
        expect(find.byKey(const Key('feedback-thanks')), findsNothing);
        expect(feedback.pending, 0);
      },
    );

    testWidgets('chọn umbrella: đổi từ hiện ra, lưu góp ý (chỉ chữ) và cảm ơn', (
      tester,
    ) async {
      await open(tester);
      await openPanel(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'umbrella'));
      await tester.pump();

      expect(
        find.text(
          'Cảm ơn bạn! Sự góp ý của bạn là đóng góp lớn cho ứng dụng sau này.',
        ),
        findsOneWidget,
      );
      final b = feedback.queuedBodies.single;
      expect(b['predictedLabel'], 'hat');
      expect(b['predictedProbability'], 0.81);
      expect(b['correctWordId'], 'umbrella');
      expect(b['correctText'], 'umbrella');
      expect(b['source'], 'top3');
      expect((b['top3'] as List).map((c) => (c as Map)['label']), [
        'hat',
        'umbrella',
        'towel',
      ]);
      expect(b['modelSource'], 'bundled');
      expect(b['vocabVersion'], isNotNull);
      expect(
        jsonEncode(b).toLowerCase(),
        isNot(contains('png')),
        reason: 'không đính kèm ảnh',
      );
      expect(
        jsonEncode(b).contains(photo),
        isFalse,
        reason: 'không lộ cả đường dẫn ảnh',
      );
    });

    testWidgets(
      'chọn lại trên cùng ảnh: vẫn một góp ý (cùng mã), đáp án cuối cùng thắng',
      (tester) async {
        await open(tester);
        await openPanel(tester);
        await tester.tap(find.widgetWithText(ChoiceChip, 'umbrella'));
        await tester.pump();
        final id = feedback.queuedBodies.single['id'];
        await tester.tap(find.widgetWithText(ChoiceChip, 'towel'));
        await tester.pump();
        expect(feedback.pending, 1);
        expect(feedback.queuedBodies.single['id'], id);
        expect(feedback.queuedBodies.single['correctWordId'], 'towel');
      },
    );

    testWidgets('ảnh khác thì góp ý khác (mã khác)', (tester) async {
      await open(tester);
      await openPanel(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'umbrella'));
      await tester.pump();
      final first = feedback.queuedBodies.single['id'];

      await open(
        tester,
        key: UniqueKey(),
      ); // dựng lại màn kết quả cho một ảnh khác (state mới)
      await openPanel(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'umbrella'));
      await tester.pump();
      expect(feedback.pending, 2);
      expect(feedback.queuedBodies.map((b) => b['id']).toSet().length, 2);
      expect(feedback.queuedBodies.first['id'], first);
    });

    testWidgets(
      'model chưa chắc (dưới ngưỡng) mà đáp án đúng là gợi ý đầu: vẫn ghi nhận để biết ngưỡng có chặt quá không',
      (tester) async {
        await open(tester, result: _result(hat: 0.4));
        expect(find.textContaining('chưa chắc'), findsOneWidget);
        await openPanel(tester);
        await tester.tap(find.widgetWithText(ChoiceChip, 'hat'));
        await tester.pump();
        final b = feedback.queuedBodies.single;
        expect(
          (b['predictedLabel'], b['correctWordId'], b['predictedProbability']),
          ('hat', 'hat', 0.4),
        );
      },
    );
  });

  group('"Khác…" (gõ tên đúng)', () {
    Future<void> openOther(WidgetTester tester) async {
      await open(tester);
      await openPanel(tester);
      await tester.tap(find.byKey(const Key('other-answer')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'gõ "cai ban" (không dấu): gợi ý "table · cái bàn"; gửi thì hiện từ table và ghi nhận',
      (tester) async {
        await openOther(tester);
        expect(find.text('Đó là gì nhỉ?'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('type-answer')), 'cai ban');
        await tester.pump();
        expect(find.byKey(const Key('suggest-table')), findsOneWidget);
        await tester.tap(find.byKey(const Key('type-answer-send')));
        await tester.pumpAndSettle();

        expect(find.text('table'), findsWidgets);
        expect(find.byKey(const Key('feedback-thanks')), findsOneWidget);
        final b = feedback.queuedBodies.single;
        expect(
          (
            b['source'],
            b['correctWordId'],
            b['correctText'],
            b['predictedLabel'],
          ),
          ('typed', 'table', 'table', 'hat'),
        );
      },
    );

    testWidgets(
      'bấm một gợi ý trong hộp thoại rồi gửi: dùng đúng từ đó (kể cả từ chỉ để học như banana)',
      (tester) async {
        await openOther(tester);
        await tester.enterText(find.byKey(const Key('type-answer')), 'chu');
        await tester.pump();
        await tester.tap(find.byKey(const Key('suggest-banana')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('type-answer-send')));
        await tester.pumpAndSettle();
        expect(find.text('banana'), findsWidgets);
        final b = feedback.queuedBodies.single;
        expect((b['correctWordId'], b['source']), ('banana', 'typed'));
      },
    );

    testWidgets(
      'gõ một từ app chưa có: hiện "mình chưa biết từ này", ghi nhận từ mới (không có mã từ)',
      (tester) async {
        await openOther(tester);
        await tester.enterText(
          find.byKey(const Key('type-answer')),
          '  con khủng long ',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('type-answer-send')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('unknown-word')), findsOneWidget);
        expect(find.text('"con khủng long"'), findsOneWidget);
        expect(find.textContaining('cảm ơn bạn đã dạy Cam'), findsOneWidget);
        final b = feedback.queuedBodies.single;
        expect(
          (b['correctWordId'], b['correctText'], b['source']),
          (null, 'con khủng long', 'typed'),
        );
      },
    );

    testWidgets(
      'huỷ hộp thoại hoặc để trống: không ghi nhận gì, không cảm ơn',
      (tester) async {
        await openOther(tester);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('type-answer-send')))
              .onPressed,
          isNull,
          reason: 'để trống: không gửi được',
        );
        await tester.tap(find.text('Huỷ'));
        await tester.pumpAndSettle();
        expect(feedback.pending, 0);
        expect(find.byKey(const Key('feedback-thanks')), findsNothing);
      },
    );

    testWidgets(
      'sau khi gõ từ lạ lại chọn một gợi ý: thay đáp án, cùng một góp ý',
      (tester) async {
        await openOther(tester);
        await tester.enterText(find.byKey(const Key('type-answer')), 'xyz lạ');
        await tester.pump();
        await tester.tap(find.byKey(const Key('type-answer-send')));
        await tester.pumpAndSettle();
        final id = feedback.queuedBodies.single['id'];
        await tester.tap(find.widgetWithText(ChoiceChip, 'umbrella'));
        await tester.pump();
        expect(find.byKey(const Key('unknown-word')), findsNothing);
        expect(feedback.pending, 1);
        expect(feedback.queuedBodies.single['id'], id);
        expect(feedback.queuedBodies.single['correctWordId'], 'umbrella');
        expect(feedback.queuedBodies.single['source'], 'top3');
      },
    );
  });

  group('so khớp chữ', () {
    test('foldText bỏ dấu, hoa thường và khoảng trắng thừa', () {
      expect(foldText('  Cái   Bàn '), 'cai ban');
      expect(foldText('đồng hồ'), 'dong ho');
      expect(foldText('Quả Táo'), 'qua tao');
      expect(foldText('ƯỚC MƠ'), 'uoc mo');
      expect(foldText('Teddy Bear'), 'teddy bear');
      expect(foldText(''), '');
    });

    test(
      'suggestWords: khớp tiếng Anh lẫn tiếng Việt, không dấu; khớp đầu chữ lên trước; tối đa 6',
      () {
        expect(suggestWords('cai ban').map((w) => w.id), contains('table'));
        expect(suggestWords('TABLE').map((w) => w.id), contains('table'));
        expect(suggestWords(''), isEmpty);
        expect(suggestWords('   '), isEmpty);
        expect(suggestWords('a').length, lessThanOrEqualTo(6));
        expect(suggestWords('zzzzqq'), isEmpty);
        final first = suggestWords('t').first;
        expect(
          foldText(first.en).startsWith('t') ||
              foldText(first.vi).startsWith('t'),
          isTrue,
          reason: 'khớp đầu chữ đứng trước',
        );
      },
    );

    test(
      'exactWord: khớp đúng tên (Anh/Việt, không dấu) hoặc mã từ; gần đúng thì không',
      () {
        expect(exactWord('Table')!.id, 'table');
        expect(exactWord('quả táo')!.id, 'apple');
        expect(exactWord('qua tao')!.id, 'apple');
        expect(exactWord('teddy bear')!.id, 'teddy_bear');
        expect(exactWord('tab'), isNull);
        expect(exactWord(''), isNull);
      },
    );
  });
}

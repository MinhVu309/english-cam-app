import 'dart:io';
import 'dart:math';

import 'package:english_cam/core/theme.dart';
import 'package:english_cam/data/game_badge.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/features/mascot/mascot.dart';
import 'package:english_cam/features/settings/parent_gate.dart';
import 'package:english_cam/main.dart';
import 'package:english_cam/services/app_settings.dart';
import 'package:english_cam/services/game_progress.dart';
import 'package:english_cam/services/progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _boot({bool onboarded = false}) async {
  SharedPreferences.setMockInitialValues({'onboarding_done': onboarded});
  await VocabRepository.load();
  await BadgeRepository.load();
  await AppSettings.instance.init();
  await ProgressService.instance.init();
  GameProgress.instance.resetForTest();
  await GameProgress.instance.init();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo ngoài vùng giả lập thời gian của testWidgets để rootBundle không bị treo.
  setUp(() => _boot());

  group('Onboarding', () {
    testWidgets('lần đầu: 3 bước rồi vào Home và nhớ đã xem', (tester) async {
      await tester.pumpWidget(const EnglishCamApp());
      await tester.pumpAndSettle();

      expect(find.text('Chào bé! Mình là Cam'), findsOneWidget);
      await tester.tap(find.text('Tiếp'));
      await tester.pumpAndSettle();
      expect(find.text('Chụp ảnh đồ vật'), findsOneWidget);
      await tester.tap(find.text('Tiếp'));
      await tester.pumpAndSettle();
      expect(find.text('Chơi và gom sao'), findsOneWidget);
      expect(find.text('Bắt đầu!'), findsOneWidget);

      await tester.tap(find.text('Bắt đầu!'));
      await tester.pumpAndSettle();

      expect(find.text('Chụp & Học'), findsOneWidget);
      expect(AppSettings.instance.onboardingDone, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool('onboarding_done'),
        isTrue,
      );
    });

    testWidgets('có nút Bỏ qua', (tester) async {
      await tester.pumpWidget(const EnglishCamApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bỏ qua'));
      await tester.pumpAndSettle();

      expect(find.text('Chụp & Học'), findsOneWidget);
    });

    testWidgets('đã xem rồi thì vào thẳng Home', (tester) async {
      await tester.runAsync(() => _boot(onboarded: true));
      await tester.pumpWidget(const EnglishCamApp());
      await tester.pumpAndSettle();

      expect(find.text('Chào bé! Mình là Cam'), findsNothing);
      expect(find.text('Chụp & Học'), findsOneWidget);
    });
  });

  group('Cổng phụ huynh và Cài đặt', () {
    test('câu hỏi là phép nhân 6..9 × 6..9', () {
      final rng = Random(1);
      for (var i = 0; i < 100; i++) {
        final q = generateGateQuestion(rng);
        expect(q.a, inInclusiveRange(6, 9));
        expect(q.b, inInclusiveRange(6, 9));
        expect(q.answer, q.a * q.b);
      }
    });

    Future<void> openGate(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => _boot(onboarded: true));
      await tester.pumpWidget(const EnglishCamApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cài đặt (dành cho bố mẹ)'));
      await tester.pumpAndSettle();
    }

    testWidgets('trả lời sai thì không vào được', (tester) async {
      await openGate(tester);
      expect(find.text('Dành cho bố mẹ'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Chưa đúng'), findsOneWidget);
      expect(find.text('Cài đặt'), findsNothing);
    });

    testWidgets('huỷ thì quay lại Home', (tester) async {
      await openGate(tester);
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();

      expect(find.text('Dành cho bố mẹ'), findsNothing);
      expect(find.text('Chụp & Học'), findsOneWidget);
    });

    testWidgets('trả lời đúng thì vào Cài đặt và xoá được tiến độ', (
      tester,
    ) async {
      await openGate(tester);
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((t) => t.endsWith('= ?'));
      final m = RegExp(r'(\d) × (\d)').firstMatch(text)!;
      final answer = int.parse(m.group(1)!) * int.parse(m.group(2)!);

      await tester.enterText(find.byType(TextField), '$answer');
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();
      expect(find.text('Cài đặt'), findsOneWidget);

      // Có tiến độ để xoá.
      await tester.runAsync(() async {
        await ProgressService.instance.setLearned('apple', true);
        await GameProgress.instance.recordFound();
      });
      expect(GameProgress.instance.stars, 2);

      await tester.tap(find.text('Xoá tiến độ của bé'));
      await tester.pumpAndSettle();
      expect(find.text('Xoá tiến độ?'), findsOneWidget);
      await tester.tap(find.text('Giữ lại'));
      await tester.pumpAndSettle();
      expect(GameProgress.instance.stars, 2); // chưa xoá

      await tester.tap(find.text('Xoá tiến độ của bé'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá hết'));
      await tester.pumpAndSettle();

      expect(GameProgress.instance.stars, 0);
      expect(GameProgress.instance.badges, isEmpty);
      expect(ProgressService.instance.learnedCount, 0);
    });
  });

  group('Mascot', () {
    testWidgets('vẽ được mọi biểu cảm ở nhiều cỡ', (tester) async {
      for (final mood in MascotMood.values) {
        for (final size in [48.0, 120.0, 220.0]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: Mascot(mood: mood, size: size),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(Mascot), findsOneWidget);
        }
      }
    });
  });

  group('Quy chuẩn giao diện', () {
    test('mọi cỡ chữ trong lib/ đều >= 18sp', () {
      final re = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)');
      final bad = <String>[];
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          for (final m in re.allMatches(lines[i])) {
            if (double.parse(m.group(1)!) < 18) {
              bad.add('${f.path}:${i + 1} ${lines[i].trim()}');
            }
          }
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('theme: nút tối thiểu 56dp và dùng font Nunito', () {
      final t = buildAppTheme();
      expect(t.textTheme.bodyMedium?.fontFamily, kFontFamily);
      final filled = t.filledButtonTheme.style!.minimumSize!.resolve({});
      final outlined = t.outlinedButtonTheme.style!.minimumSize!.resolve({});
      final text = t.textButtonTheme.style!.minimumSize!.resolve({});
      for (final s in [filled, outlined, text]) {
        expect(s!.height, greaterThanOrEqualTo(56));
      }
    });
  });
}

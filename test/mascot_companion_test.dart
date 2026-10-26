import 'dart:math';

import 'package:english_cam/core/theme.dart';
import 'package:english_cam/features/mascot/mascot_host.dart';
import 'package:english_cam/features/mascot/mascot_messages.dart';
import 'package:english_cam/features/mascot/speech_bubble.dart';
import 'package:english_cam/services/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Các context mà màn hình thật sự dùng (xem MascotHost/MascotStrip trong lib/).
const _screens = [
  'home',
  'camera',
  'result',
  'vocab',
  'vocab_detail',
  'hub',
  'match',
  'hunt',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MascotMessages messages;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
    messages = await MascotMessages.load();
  });

  tearDown(() => MascotHost.autoEnabled = false);

  group('Kho lời nhắn', () {
    test(
      'mọi màn hình đều có đủ câu, ngắn gọn và không còn {biến} chưa điền',
      () {
        for (final key in _screens) {
          final rng = Random(1);
          final seen = <String>{};
          for (var i = 0; i < 80; i++) {
            final line = messages.pick(
              key,
              rng,
              info: const MascotContext(learned: 3, stars: 5),
            );
            expect(line, isNotNull, reason: key);
            expect(line!.text, isNot(contains('{')), reason: line.text);
            expect(line.text.length, lessThanOrEqualTo(60), reason: line.text);
            seen.add(line.text);
          }
          expect(seen.length, greaterThanOrEqualTo(3), reason: key);
        }
      },
    );

    test('điều kiện when: chưa học thì không khoe số từ đã học', () {
      final rng = Random(2);
      for (var i = 0; i < 100; i++) {
        final none = messages.pick('home', rng, info: const MascotContext())!;
        expect(none.text, isNot(contains('đã học')));
        expect(none.text, isNot(contains('sao lấp lánh')));
      }
      final texts = {
        for (var i = 0; i < 200; i++)
          messages
              .pick(
                'home',
                rng,
                info: const MascotContext(learned: 7, stars: 12),
              )!
              .text,
      };
      expect(texts, contains('Bé đã học 7 từ rồi, giỏi quá!'));
      expect(texts, contains('Bé đang có 12 sao lấp lánh đó!'));
    });

    test('không nhắc lại đúng câu vừa nói', () {
      final rng = Random(3);
      var last = messages.pick('hunt', rng)!.text;
      for (var i = 0; i < 60; i++) {
        final next = messages.pick('hunt', rng, avoid: last)!.text;
        expect(next, isNot(last));
        last = next;
      }
    });

    test('context lạ trả về null thay vì lỗi', () {
      expect(messages.pick('khong-co', Random(1)), isNull);
    });
  });

  group('Cam đồng hành (MascotHost)', () {
    Widget app({Random? rng}) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: MascotHost(
          contextKey: 'hub',
          random: rng ?? Random(5),
          firstDelay: const Duration(seconds: 1),
          minGap: const Duration(seconds: 3),
          maxGap: const Duration(seconds: 3),
          visibleFor: const Duration(seconds: 2),
          child: const SizedBox.expand(),
        ),
      ),
    );

    Future<void> end(WidgetTester tester) async {
      // Gỡ cây widget để mọi timer của Cam bị huỷ.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('lâu lâu tự hiện, rồi tự rút đi và hẹn lần sau', (
      tester,
    ) async {
      MascotHost.autoEnabled = true;
      await tester.pumpWidget(app());
      expect(find.byType(SpeechBubble), findsNothing);

      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SpeechBubble), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SpeechBubble), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SpeechBubble), findsOneWidget);

      await end(tester);
    });

    testWidgets('chạm vào Cam thì nói câu khác', (tester) async {
      MascotHost.autoEnabled = true;
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 500));

      String text() => tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(SpeechBubble),
              matching: find.byType(Text),
            ),
          )
          .first
          .data!;
      final before = text();

      await tester.tap(find.byType(SpeechBubble));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SpeechBubble), findsOneWidget);
      expect(text(), isNot(before));

      await end(tester);
    });

    testWidgets('bố mẹ tắt "Cam nhắn tin" thì Cam im lặng', (tester) async {
      MascotHost.autoEnabled = true;
      await AppSettings.instance.setMascotChatter(false);
      addTearDown(() => AppSettings.instance.setMascotChatter(true));

      await tester.pumpWidget(app());
      await tester.pump(const Duration(seconds: 10));

      expect(find.byType(SpeechBubble), findsNothing);
      await end(tester);
    });

    testWidgets('tắt giữa chừng thì Cam rút ngay', (tester) async {
      MascotHost.autoEnabled = true;
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SpeechBubble), findsOneWidget);

      await AppSettings.instance.setMascotChatter(false);
      addTearDown(() => AppSettings.instance.setMascotChatter(true));
      await tester.pump(); // bắt đầu hiệu ứng rút đi
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(SpeechBubble), findsNothing);
      await end(tester);
    });
  });

  test('cài đặt "Cam nhắn tin" được lưu và nhớ lại', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
    expect(AppSettings.instance.mascotChatter, isTrue);

    await AppSettings.instance.setMascotChatter(false);
    expect(
      (await SharedPreferences.getInstance()).getBool('mascot_chatter'),
      isFalse,
    );
    await AppSettings.instance.init();
    expect(AppSettings.instance.mascotChatter, isFalse);
    await AppSettings.instance.setMascotChatter(true);
  });
}

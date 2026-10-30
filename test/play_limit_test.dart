import 'package:english_cam/features/limit/play_limit_gate.dart';
import 'package:english_cam/services/play_limit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var now = DateTime(2026, 10, 30, 10);
  var live = 0;
  late PlayLimit limit;

  Future<PlayLimit> make({int? limitMinutes = 30, int recorded = 0}) async {
    final l = PlayLimit(clock: () => now)..liveSeconds = () => live;
    await l.useProfile('kid');
    l.applySnapshot(limitMinutes: limitMinutes, serverSeconds: recorded, pendingSeconds: 0);
    return l;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 30, 10);
    live = 0;
    limit = await make();
  });

  group('PlayLimit', () {
    test('không có hồ sơ bé (khách) thì không giới hạn', () async {
      final guest = PlayLimit(clock: () => now)..liveSeconds = () => 99999;
      await guest.useProfile(null);
      expect(guest.evaluate(), isFalse);
      expect(guest.locked, isFalse);
      expect(guest.remainingSeconds, isNull);
    });

    test('khoá đúng lúc dùng đủ giới hạn, không sớm hơn', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1799, pendingSeconds: 0);
      expect(limit.locked, isFalse);
      expect(limit.remainingSeconds, 1);
      limit.addRecorded(1);
      expect(limit.locked, isTrue);
      expect(limit.remainingSeconds, 0);
    });

    test('tính cả thời gian đang mở app chưa ghi', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1000, pendingSeconds: 0);
      live = 799;
      expect(limit.evaluate(), isFalse);
      live = 800;
      expect(limit.evaluate(), isTrue, reason: 'trả true đúng lần vừa chuyển sang khoá');
      expect(limit.evaluate(), isFalse, reason: 'đã khoá rồi thì không báo lại');
    });

    test('đang khoá thì thời gian đang mở app không đếm thêm', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1800, pendingSeconds: 0);
      expect(limit.locked, isTrue);
      live = 5000;
      expect(limit.usedSeconds, 1800);
    });

    test('cho thêm khi đang khoá: được đúng N phút kể từ lúc này, dù đã vượt hạn mức', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1900, pendingSeconds: 0); // vượt 100 giây
      expect(limit.locked, isTrue);
      limit.grantMore(10);
      expect(limit.locked, isFalse);
      expect(limit.remainingSeconds, 600);
    });

    test('cho thêm khi chưa khoá: cộng thêm vào phần còn lại', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1000, pendingSeconds: 0);
      limit.grantMore(10);
      expect(limit.remainingSeconds, 800 + 600);
      limit.grantMore(10);
      expect(limit.remainingSeconds, 800 + 1200);
    });

    test('cho thêm hai lần liên tiếp khi đang khoá: mỗi lần được đủ N phút', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1800, pendingSeconds: 0);
      limit.grantMore(10);
      limit.addRecorded(600);
      expect(limit.locked, isTrue);
      limit.grantMore(20);
      expect(limit.remainingSeconds, 1200);
    });

    test('sang ngày mới thì mở khoá và đếm lại từ 0 (kể cả thời gian cho thêm)', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1800, pendingSeconds: 0);
      limit.grantMore(10);
      expect(limit.bonusSeconds, 600);
      now = now.add(const Duration(hours: 30));
      limit.evaluate();
      expect(limit.locked, isFalse);
      expect(limit.recordedSeconds, 0);
      expect(limit.bonusSeconds, 0);
      expect(limit.remainingSeconds, 1800);
    });

    test('bố mẹ tăng giới hạn trên máy chủ thì mở khoá; bỏ giới hạn thì hết khoá', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1800, pendingSeconds: 0);
      expect(limit.locked, isTrue);
      limit.applySnapshot(limitMinutes: 45, serverSeconds: 1800, pendingSeconds: 0);
      expect(limit.locked, isFalse);
      limit.applySnapshot(limitMinutes: 5, serverSeconds: 1800, pendingSeconds: 0);
      expect(limit.locked, isTrue);
      limit.applySnapshot(limitMinutes: null, serverSeconds: 1800, pendingSeconds: 0);
      expect(limit.locked, isFalse);
      expect(limit.remainingSeconds, isNull);
    });

    test('bố mẹ xoá tiến độ (máy chủ báo 0 giây) thì số đã dùng giảm theo', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1800, pendingSeconds: 0);
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 0, pendingSeconds: 0);
      expect(limit.locked, isFalse);
      expect(limit.recordedSeconds, 0);
    });

    test('nhớ trạng thái theo từng hồ sơ: mở lại app cùng ngày vẫn khoá; sang ngày thì đếm lại', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1800, pendingSeconds: 0);
      await Future<void>.delayed(Duration.zero);
      final reopened = PlayLimit(clock: () => now)..liveSeconds = () => 0;
      await reopened.useProfile('kid');
      expect(reopened.limitMinutes, 30);
      expect(reopened.locked, isTrue);

      final other = PlayLimit(clock: () => now);
      await other.useProfile('kid-2');
      expect(other.locked, isFalse, reason: 'bé khác không dính giới hạn của bé này');

      now = now.add(const Duration(hours: 30));
      final nextDay = PlayLimit(clock: () => now)..liveSeconds = () => 0;
      await nextDay.useProfile('kid');
      expect(nextDay.limitMinutes, 30);
      expect(nextDay.locked, isFalse);
      expect(nextDay.recordedSeconds, 0);
    });

    test('nhắc trước đúng một lần mỗi ngày khi còn ≤ 5 phút; cho thêm thì nhắc lại được', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1400, pendingSeconds: 0);
      expect(limit.takeWarning(), isFalse, reason: 'còn 400 giây');
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1500, pendingSeconds: 0);
      expect(limit.takeWarning(), isTrue);
      expect(limit.takeWarning(), isFalse);
      limit.grantMore(10); // còn 300+600 giây
      expect(limit.takeWarning(), isFalse);
      limit.addRecorded(700); // còn 200 giây
      expect(limit.takeWarning(), isTrue);
    });

    test('không nhắc khi đã khoá hoặc không có giới hạn', () async {
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1800, pendingSeconds: 0);
      expect(limit.takeWarning(), isFalse);
      limit.applySnapshot(limitMinutes: null, serverSeconds: 1800, pendingSeconds: 0);
      expect(limit.takeWarning(), isFalse);
    });
  });

  group('Màn khoá hết giờ', () {
    Widget host(PlayLimit l) => MaterialApp(
      home: PlayLimitGate(limit: l, child: const Scaffold(body: Center(child: Text('NỘI DUNG APP')))),
    );

    testWidgets('chưa hết giờ thì không che app; hết giờ thì phủ màn khoá, cho thêm giờ thì biến mất', (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(limit));
      expect(find.text('Hết giờ chơi hôm nay rồi!'), findsNothing);

      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1800, pendingSeconds: 0);
      await tester.pump();
      expect(find.text('Hết giờ chơi hôm nay rồi!'), findsOneWidget);
      expect(find.textContaining('Bé đã chơi 30 phút'), findsOneWidget);
      expect(find.textContaining('mai chơi tiếp nhé', findRichText: true), findsOneWidget);

      limit.grantMore(10);
      await tester.pump();
      expect(find.text('Hết giờ chơi hôm nay rồi!'), findsNothing);
      expect(find.text('NỘI DUNG APP'), findsOneWidget);
    });

    testWidgets('bố mẹ qua cổng phép nhân rồi chọn số phút thì mở khoá; trả lời sai thì vẫn khoá', (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      limit.applySnapshot(limitMinutes: 30, serverSeconds: 1800, pendingSeconds: 0);
      // Giống main.dart: màn khoá phủ lên Navigator của app.
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => PlayLimitGate(limit: limit, child: child!),
          home: const Scaffold(body: Text('NỘI DUNG APP')),
        ),
      );
      expect(find.text('Hết giờ chơi hôm nay rồi!'), findsOneWidget);

      await tester.tap(find.text('Dành cho bố mẹ'));
      await tester.pumpAndSettle();
      final q = find.textContaining(RegExp(r'\d × \d = \?'));
      final m = RegExp(r'(\d) × (\d)').firstMatch(tester.widget<Text>(q).data!)!;
      final answer = int.parse(m.group(1)!) * int.parse(m.group(2)!);

      await tester.enterText(find.byType(TextField), '${answer + 1}');
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa đúng, thử phép tính mới nhé.'), findsOneWidget);
      expect(limit.locked, isTrue);

      final q2 = find.textContaining(RegExp(r'\d × \d = \?'));
      final m2 = RegExp(r'(\d) × (\d)').firstMatch(tester.widget<Text>(q2).data!)!;
      await tester.enterText(find.byType(TextField), '${int.parse(m2.group(1)!) * int.parse(m2.group(2)!)}');
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();
      expect(find.text('Cho bé chơi thêm'), findsOneWidget);
      await tester.tap(find.text('20 phút'));
      await tester.pumpAndSettle();

      expect(limit.locked, isFalse);
      expect(limit.remainingSeconds, 1200);
      expect(find.text('Hết giờ chơi hôm nay rồi!'), findsNothing);
      expect(answer, greaterThan(0));
    });
  });
}

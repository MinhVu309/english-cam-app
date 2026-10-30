import 'package:english_cam/core/api_client.dart';
import 'package:english_cam/core/router.dart';
import 'package:english_cam/core/theme.dart';
import 'package:english_cam/data/account/account_models.dart';
import 'package:english_cam/data/account/dashboard_models.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/features/account/child_dashboard_screen.dart';
import 'package:english_cam/features/account/dashboard_charts.dart';
import 'package:english_cam/services/audio_service.dart';
import 'package:english_cam/services/auth_service.dart';
import 'package:english_cam/services/key_value_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Định dạng', () {
    test('thời lượng', () {
      expect(formatDuration(0), '0 phút');
      expect(formatDuration(-5), '0 phút');
      expect(formatDuration(30), 'dưới 1 phút');
      expect(formatDuration(60), '1 phút');
      expect(formatDuration(90), '2 phút'); // 1,5 làm tròn lên
      expect(formatDuration(45 * 60), '45 phút');
      expect(formatDuration(60 * 60), '1 giờ');
      expect(formatDuration(80 * 60), '1 giờ 20 phút');
    });

    test('nhãn ngày: thứ khi xem 7 ngày, ngày/tháng khi xem nhiều hơn', () {
      final friday = DateTime(2026, 10, 30); // thứ Sáu
      expect(dayLabel(friday, 7), 'T6');
      expect(dayLabel(DateTime(2026, 11, 1), 7), 'CN');
      expect(dayLabel(DateTime(2026, 11, 2), 7), 'T2');
      expect(dayLabel(friday, 30), '30/10');
    });
  });

  group('Hình học biểu đồ', () {
    const plot = Size(300, 100);

    test('chiều cao cột tỉ lệ với giá trị lớn nhất', () {
      final r = barRects([0, 5, 10], plot);
      expect(r[2].height, 100);
      expect(r[1].height, 50);
      expect(
        r.every((x) => x.bottom == 100),
        isTrue,
        reason: 'mọi cột đứng trên cùng một đường nền',
      );
    });

    test('giá trị 0 vẫn có vạch mảnh; giá trị nhỏ vẫn nhìn thấy được', () {
      final r = barRects([0, 0.01, 100], plot);
      expect(r[0].height, 2);
      expect(r[1].height, 4); // tối thiểu để thấy
      expect(r[2].height, 100);
    });

    test('toàn số 0 hoặc rỗng không lỗi', () {
      expect(barRects([0, 0, 0], plot).map((r) => r.height), [2, 2, 2]);
      expect(barRects(const [], plot), isEmpty);
    });

    test('các cột nằm gọn trong khung, không chồng nhau', () {
      for (final n in [1, 7, 30, 90]) {
        final r = barRects(List.generate(n, (i) => i.toDouble()), plot);
        expect(
          r.last.right,
          lessThanOrEqualTo(plot.width + 0.001),
          reason: 'n=$n',
        );
        for (var i = 1; i < r.length; i++) {
          expect(
            r[i].left,
            greaterThanOrEqualTo(r[i - 1].right),
            reason: 'n=$n',
          );
        }
      }
    });

    test(
      'nhãn trục x: ít cột thì ghi hết, nhiều cột thì thưa nhưng luôn có cột cuối (hôm nay)',
      () {
        expect(labelIndexes(7), [0, 1, 2, 3, 4, 5, 6]);
        final l30 = labelIndexes(30);
        expect(l30.last, 29);
        expect(l30.length, lessThanOrEqualTo(7));
        expect(l30, orderedEquals([...l30]..sort()));
        expect(labelIndexes(0), isEmpty);
        expect(labelIndexes(1), [0]);
      },
    );
  });

  group('Mô hình', () {
    test('đọc dashboard đầy đủ', () {
      final d = ChildDashboard.fromJson(
        dashboardJson(days: 30, limit: 30, accuracy: null),
      );
      expect(d.daysData, hasLength(30));
      expect(d.totals.accuracyPercent, isNull);
      expect(d.dailyLimitMinutes, 30);
      expect(d.categories.first.vi, 'Đồ dùng học tập');
      expect(d.weakWords.first.wordId, 'pen');
      expect(d.recent.last.isHunt, isTrue);
      expect(d.recent.last.wordVi, 'cái cốc');
      expect(d.recentBadges.single.emoji, '🎮');
      expect(d.daysData.last.minutes, 10);
    });

    test('vượt giới hạn chỉ khi có giới hạn và đã dùng quá', () {
      expect(
        ChildDashboard.fromJson(
          dashboardJson(todaySeconds: 31 * 60, limit: 30),
        ).overLimitToday,
        isTrue,
      );
      expect(
        ChildDashboard.fromJson(
          dashboardJson(todaySeconds: 30 * 60, limit: 30),
        ).overLimitToday,
        isFalse,
      );
      expect(
        ChildDashboard.fromJson(
          dashboardJson(todaySeconds: 99999),
        ).overLimitToday,
        isFalse,
      );
    });
  });

  group('Màn dashboard', () {
    late FakeServer server;
    late AuthService auth;
    late VocabRepository repo;
    const child = ChildProfile(id: 'c1', nickname: 'Bi', avatarKey: 'fox');

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      AudioService.instance.disabled = true;
      repo = await VocabRepository.load();
      server = FakeServer()
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('GET /api/parent/children/c1/dashboard', 200, dashboardJson());
      auth = AuthService(
        api: ApiClient(baseUrl: 'https://api.test', transport: server.call),
        store: MemoryKeyValueStore(),
        google: FakeGoogle(),
        device: FakeDevice(),
      );
      AuthService.instance = auth;
    });

    tearDown(() => AuthService.instance = AuthService());

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => auth.verifyOtp('lan@test.com', '123456'));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          // initialRoute '/children/dashboard' được Flutter tách thành '/', '/children', '/children/dashboard'.
          onGenerateRoute: (s) => MaterialPageRoute<void>(
            settings: s,
            builder: (_) => s.name == Routes.childDashboard
                ? const ChildDashboardScreen(child: child)
                : Scaffold(
                    body: Text(
                      s.name == Routes.home ? 'TRANG CHỦ' : 'TRUNG GIAN',
                    ),
                  ),
          ),
          initialRoute: Routes.childDashboard,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'hiện số liệu tổng, biểu đồ, chủ đề, từ cần ôn, huy hiệu, hoạt động',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await open(tester);

        expect(find.text('Tiến độ của Bi'), findsOneWidget);
        expect(find.text('12/60'), findsOneWidget);
        expect(find.text('từ đã học'), findsOneWidget);
        expect(find.text('⭐ 24'), findsOneWidget);
        expect(find.text('4 ván · 1 hoàn hảo'), findsOneWidget);
        expect(find.text('🔥 3'), findsOneWidget);
        expect(find.text('Kỷ lục 5 ngày'), findsOneWidget);
        expect(
          find.text('10 phút'),
          findsOneWidget,
          reason: 'hôm nay 600 giây',
        );
        expect(find.text('2/5 từ mới'), findsOneWidget);
        expect(find.text('78%'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            RegExp(r'Biểu đồ số phút học mỗi ngày trong 7 ngày'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(r'Biểu đồ số từ mới mỗi ngày trong 7 ngày'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('Đã học 12 trên 60 từ')),
          findsOneWidget,
        );
        expect(find.text('Đồ dùng học tập'), findsOneWidget);
        expect(find.text('3/5'), findsOneWidget);
        expect(find.text('pen · cái bút'), findsOneWidget);
        expect(find.text('Đúng ngay lần đầu 50% (1/2 lần)'), findsOneWidget);
        expect(find.text('Huy hiệu (1/10)'), findsOneWidget);
        expect(find.text('Bé tập chơi'), findsOneWidget);
        expect(find.text('Nghe & chọn hình: 8/8 câu'), findsOneWidget);
        expect(find.text('Tìm vật: cup (cái cốc)'), findsOneWidget);
        expect(find.textContaining('5 phút trước'), findsOneWidget);
        semantics.dispose();
      },
    );

    testWidgets('chuyển sang 30 ngày gọi lại với days=30 và vẽ lại biểu đồ', (
      tester,
    ) async {
      server.handle('GET /api/parent/children/c1/dashboard', (r) {
        final days = int.parse(r.url.queryParameters['days']!);
        return FakeServer.json(200, dashboardJson(days: days));
      });
      final semantics = tester.ensureSemantics();
      await open(tester);
      expect(
        server.to('GET /api/parent/children/c1/dashboard').single.url.query,
        'days=7',
      );

      await tester.tap(find.text('30 ngày'));
      await tester.pumpAndSettle();
      expect(
        server.to('GET /api/parent/children/c1/dashboard').last.url.query,
        'days=30',
      );
      expect(find.bySemanticsLabel(RegExp(r'trong 30 ngày')), findsWidgets);
      expect(find.textContaining('học 30 ngày'), findsNothing);
      semantics.dispose();
    });

    testWidgets('lỗi tải: báo lỗi, nút Thử lại tải lại được', (tester) async {
      var fail = true;
      server.handle(
        'GET /api/parent/children/c1/dashboard',
        (_) => fail
            ? FakeServer.json(500, null)
            : FakeServer.json(200, dashboardJson()),
      );
      await open(tester);
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      expect(find.text('12/60'), findsNothing);
      fail = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('12/60'), findsOneWidget);
    });

    testWidgets('bé dùng quá giới hạn: báo đỏ cho bố mẹ biết', (tester) async {
      server.on(
        'GET /api/parent/children/c1/dashboard',
        200,
        dashboardJson(todaySeconds: 45 * 60, limit: 30),
      );
      await open(tester);
      expect(find.text('Vượt giới hạn 30 phút'), findsOneWidget);
      expect(find.text('45 phút'), findsOneWidget);
    });

    testWidgets('còn trong giới hạn và đạt mục tiêu: hiện dấu ✅', (
      tester,
    ) async {
      server.on(
        'GET /api/parent/children/c1/dashboard',
        200,
        dashboardJson(todaySeconds: 10 * 60, limit: 30, todayWords: 5, goal: 5),
      );
      await open(tester);
      expect(find.text('Giới hạn 30 phút'), findsOneWidget);
      expect(find.text('5/5 từ mới ✅'), findsOneWidget);
    });

    testWidgets('bé mới: thông điệp rỗng thân thiện, không lỗi', (
      tester,
    ) async {
      server.on(
        'GET /api/parent/children/c1/dashboard',
        200,
        dashboardJson(
          learned: 0,
          stars: 0,
          streak: 0,
          best: 0,
          accuracy: null,
          todaySeconds: 0,
          todayWords: 0,
          weak: [],
          recent: [],
          badges: [],
        ),
      );
      await open(tester);
      expect(find.text('0/60'), findsOneWidget);
      expect(find.text('0 phút'), findsOneWidget);
      expect(
        find.textContaining('Chưa có ván "Nghe & chọn hình"'),
        findsOneWidget,
      );
      expect(find.textContaining('Chưa có từ nào bé hay nhầm'), findsOneWidget);
      expect(find.text('Chưa có huy hiệu nào.'), findsOneWidget);
      expect(find.text('Chưa có hoạt động nào.'), findsOneWidget);
    });

    testWidgets(
      'nghe lại từ cần ôn không lỗi kể cả khi từ không còn trong từ vựng',
      (tester) async {
        server.on(
          'GET /api/parent/children/c1/dashboard',
          200,
          dashboardJson(
            weak: [
              {
                'wordId': 'pen',
                'en': 'pen',
                'vi': 'cái bút',
                'emoji': null,
                'wrong': 1,
                'total': 2,
                'accuracyPercent': 50,
              },
              {
                'wordId': 'tu_da_xoa',
                'en': 'gone',
                'vi': 'đã xoá',
                'emoji': null,
                'wrong': 1,
                'total': 2,
                'accuracyPercent': 50,
              },
            ],
          ),
        );
        await open(tester);
        expect(repo.byId('pen'), isNotNull);
        await tester.tap(find.byTooltip('Nghe "pen"'));
        await tester.tap(find.byTooltip('Nghe "gone"'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('chép CSV theo ngày và theo từ vào clipboard (bỏ BOM)', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      server.handle('GET /api/parent/children/c1/export.csv', (r) {
        final kind = r.url.queryParameters['kind'];
        return HttpResponseData(
          200,
          '﻿${kind == 'words' ? 'word_id,english\r\ncup,cup\r\n' : 'date,minutes\r\n2026-10-30,1.5\r\n'}',
        );
      });
      await open(tester);

      await tester.ensureVisible(find.text('Chép dữ liệu theo ngày'));
      await tester.tap(find.text('Chép dữ liệu theo ngày'));
      await tester.pumpAndSettle();
      expect(copied, 'date,minutes\r\n2026-10-30,1.5\r\n');
      expect(
        server.to('GET /api/parent/children/c1/export.csv').last.url.query,
        'kind=daily&days=30',
      );
      expect(find.textContaining('Đã chép dữ liệu'), findsOneWidget);

      await tester.tap(find.text('Chép dữ liệu theo từ'));
      await tester.pumpAndSettle();
      expect(copied, 'word_id,english\r\ncup,cup\r\n');
      expect(
        server
            .to('GET /api/parent/children/c1/export.csv')
            .last
            .url
            .queryParameters['kind'],
        'words',
      );
    });

    testWidgets('xuất CSV lỗi: báo lỗi, không ghi gì vào clipboard', (
      tester,
    ) async {
      var wrote = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') wrote = true;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      server.on('GET /api/parent/children/c1/export.csv', 500);
      await open(tester);
      await tester.ensureVisible(find.text('Chép dữ liệu theo ngày'));
      await tester.tap(find.text('Chép dữ liệu theo ngày'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      expect(wrote, isFalse);
    });

    testWidgets('phiên phụ huynh hết hạn (401): về trang chủ', (tester) async {
      server.on('GET /api/parent/children/c1/dashboard', 401);
      await open(tester);
      expect(auth.isParentSignedIn, isFalse);
      expect(find.text('TRANG CHỦ'), findsOneWidget);
      expect(find.byType(ChildDashboardScreen), findsNothing);
    });
  });
}

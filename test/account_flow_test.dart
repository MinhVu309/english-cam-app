import 'package:english_cam/core/api_client.dart';
import 'package:english_cam/data/account/account_models.dart';
import 'package:english_cam/data/game_badge.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/features/account/link_code_dialog.dart';
import 'package:english_cam/main.dart';
import 'package:english_cam/services/app_settings.dart';
import 'package:english_cam/services/audio_service.dart';
import 'package:english_cam/services/auth_service.dart';
import 'package:english_cam/services/game_progress.dart';
import 'package:english_cam/services/key_value_store.dart';
import 'package:english_cam/services/progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

/// Màn hình test cao để ListView dựng đủ mọi mục và mọi nút bấm được (mặc định chỉ 800×600).
void testUi(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await body(tester);
  });
}

/// Luồng người dùng qua đúng `EnglishCamApp` (Home → Cài đặt → ...), máy chủ giả trong bộ nhớ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  late AuthService auth;
  late FakeGoogle google;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    await AppSettings.instance.init();
    AudioService.instance.disabled = true;
    await VocabRepository.load();
    await BadgeRepository.load();
    GameProgress.instance.resetForTest();
    await ProgressService.instance.init();

    server = FakeServer();
    google = FakeGoogle();
    auth = AuthService(
      api: ApiClient(baseUrl: 'https://api.test', transport: server.call),
      store: MemoryKeyValueStore(),
      google: google,
      device: FakeDevice(),
    );
    AuthService.instance = auth;
  });

  tearDown(() => AuthService.instance = AuthService());

  /// Trả lời phép nhân của cổng phụ huynh đang hiện.
  Future<void> passGate(WidgetTester tester) async {
    final q = find.textContaining(RegExp(r'\d × \d = \?'));
    expect(q, findsOneWidget);
    final m = RegExp(r'(\d) × (\d)').firstMatch((tester.widget<Text>(q)).data!)!;
    await tester.enterText(find.byType(TextField), '${int.parse(m[1]!) * int.parse(m[2]!)}');
    await tester.tap(find.widgetWithText(FilledButton, 'Mở'));
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Cài đặt (dành cho bố mẹ)'));
    await tester.pumpAndSettle();
    await passGate(tester);
  }

  Future<void> signInParent(WidgetTester tester, {String role = 'Parent', String name = 'Mẹ Lan'}) async {
    server.on('POST /api/auth/verify-otp', 200, authJson(role: role, name: name));
    await tester.runAsync(() => auth.verifyOtp('lan@test.com', '123456'));
  }

  Future<void> enter(WidgetTester tester, String label, String text) async {
    await tester.enterText(find.widgetWithText(TextField, label), text);
  }

  group('Khách', () {
    testUi('Home không có chip; Cài đặt có Đăng nhập và Nhập mã liên kết', (tester) async {
      await tester.pumpWidget(const EnglishCamApp());
      expect(find.text('Chọn bé'), findsNothing);

      await openSettings(tester);
      expect(find.text('Đăng nhập / Đăng ký'), findsOneWidget);
      expect(find.text('Máy của bé? Nhập mã liên kết'), findsOneWidget);
    });
  });

  group('Đăng nhập', () {
    testUi('email + mật khẩu → OTP → vào Hồ sơ của bé', (tester) async {
      server
        ..on('POST /api/auth/login', 200, {'requiresOtp': true})
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('GET /api/children', 200, <Object>[]);
      await tester.pumpWidget(const EnglishCamApp());
      await openSettings(tester);
      await tester.tap(find.text('Đăng nhập / Đăng ký'));
      await tester.pumpAndSettle();

      await enter(tester, 'Email', 'lan@test.com');
      await enter(tester, 'Mật khẩu', 'Matkhau123');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();

      expect(find.text('Nhập mã OTP'), findsOneWidget);
      expect(find.textContaining('lan@test.com'), findsOneWidget);
      expect(find.text('Gửi lại mã sau 60s'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();

      expect(find.text('Hồ sơ của bé'), findsOneWidget);
      expect(find.textContaining('Chưa có hồ sơ bé'), findsOneWidget);
      expect(auth.isParentSignedIn, isTrue);
      expect(server.bodyOf(server.to('POST /api/auth/verify-otp').single)['code'], '123456');
    });

    testUi('sai mật khẩu: hiện thông báo của máy chủ, ở lại màn đăng nhập', (tester) async {
      server.on('POST /api/auth/login', 401, {'message': 'Sai tài khoản hoặc mật khẩu'});
      await tester.pumpWidget(const EnglishCamApp());
      await openSettings(tester);
      await tester.tap(find.text('Đăng nhập / Đăng ký'));
      await tester.pumpAndSettle();
      await enter(tester, 'Email', 'lan@test.com');
      await enter(tester, 'Mật khẩu', 'saimatkhau1');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();

      expect(find.text('Sai tài khoản hoặc mật khẩu'), findsOneWidget);
      expect(find.text('Nhập mã OTP'), findsNothing);
      expect(auth.notice.value, isNull);
    });

    testUi('nhập thiếu: báo ngay, không gọi máy chủ', (tester) async {
      await tester.pumpWidget(const EnglishCamApp());
      await openSettings(tester);
      await tester.tap(find.text('Đăng nhập / Đăng ký'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập email hợp lệ và mật khẩu.'), findsOneWidget);
      expect(server.calls, isEmpty);
    });

    testUi('OTP: nút gửi lại bật sau 60 giây và gọi resend-otp', (tester) async {
      server
        ..on('POST /api/auth/login', 200, {'requiresOtp': true})
        ..on('POST /api/auth/resend-otp', 200, {'message': 'ok'});
      await tester.pumpWidget(const EnglishCamApp());
      await openSettings(tester);
      await tester.tap(find.text('Đăng nhập / Đăng ký'));
      await tester.pumpAndSettle();
      await enter(tester, 'Email', 'lan@test.com');
      await enter(tester, 'Mật khẩu', 'Matkhau123');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 61));
      expect(find.text('Gửi lại mã'), findsOneWidget);
      await tester.tap(find.text('Gửi lại mã'));
      await tester.pumpAndSettle();
      expect(server.to('POST /api/auth/resend-otp'), hasLength(1));
      expect(find.text('Gửi lại mã sau 60s'), findsOneWidget, reason: 'đếm lại từ đầu');
    });

    testUi('Google huỷ giữa chừng: im lặng, vẫn ở màn đăng nhập', (tester) async {
      google.error = GoogleCancelledForTest();
      await tester.pumpWidget(const EnglishCamApp());
      await openSettings(tester);
      await tester.tap(find.text('Đăng nhập / Đăng ký'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng nhập bằng Google'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Đăng nhập Google không thành công'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
    });

    testUi('Google thành công với tài khoản admin → trang Quản trị', (tester) async {
      server
        ..on('POST /api/auth/google-login', 200, authJson(role: 'Admin', name: 'Quản trị viên'))
        ..on('GET /api/admin/vocab/status', 200, {
          'publishedVersion': 3,
          'publishedAt': null,
          'hasUnpublishedChanges': true,
          'activeWords': 61,
          'activeCategories': 11,
        });
      await tester.pumpWidget(const EnglishCamApp());
      await openSettings(tester);
      await tester.tap(find.text('Đăng nhập / Đăng ký'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng nhập bằng Google'));
      await tester.pumpAndSettle();

      expect(find.text('Quản trị'), findsOneWidget);
      expect(find.textContaining('Phiên bản 3 · 61 từ · 11 chủ đề'), findsOneWidget);
      expect(find.textContaining('chưa xuất bản'), findsOneWidget);
    });
  });

  group('Đăng ký', () {
    testUi('mật khẩu yếu và nhập lại không khớp bị chặn trước khi gọi máy chủ', (tester) async {
      server.on('POST /api/auth/register', 200, {'requiresEmailVerification': true});
      await tester.pumpWidget(const EnglishCamApp());
      await openSettings(tester);
      await tester.tap(find.text('Đăng nhập / Đăng ký'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chưa có tài khoản? Đăng ký'));
      await tester.pumpAndSettle();

      await enter(tester, 'Họ và tên', 'Lan');
      await enter(tester, 'Email', 'lan@test.com');
      await enter(tester, 'Mật khẩu (≥ 8 ký tự, có chữ thường và số)', 'abc');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng ký'));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu tối thiểu 8 ký tự.'), findsOneWidget);

      await enter(tester, 'Mật khẩu (≥ 8 ký tự, có chữ thường và số)', 'Matkhau123');
      await enter(tester, 'Nhập lại mật khẩu', 'Matkhau124');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng ký'));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu nhập lại không khớp.'), findsOneWidget);
      expect(server.calls, isEmpty);

      await enter(tester, 'Nhập lại mật khẩu', 'Matkhau123');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng ký'));
      await tester.pumpAndSettle();
      expect(find.text('Xác minh email'), findsOneWidget);
      expect(server.bodyOf(server.to('POST /api/auth/register').single), {
        'email': 'lan@test.com',
        'password': 'Matkhau123',
        'fullName': 'Lan',
      });
    });
  });

  group('Phụ huynh quản lý bé', () {
    testUi('Home hiện "Chọn bé" → danh sách → Cho bé chơi → Home hiện bé', (tester) async {
      server
        ..on('GET /api/children', 200, [childJson(devices: 2)])
        ..on('POST /api/children/c1/session', 200, authJson(role: 'Child', token: 'tok-child', name: 'Bi', email: ''));
      await tester.pumpWidget(const EnglishCamApp());
      await signInParent(tester);
      await tester.pump();

      expect(find.text('Chọn bé'), findsOneWidget);
      await tester.tap(find.text('Chọn bé'));
      await tester.pumpAndSettle();
      await passGate(tester);

      expect(find.text('Hồ sơ của bé'), findsOneWidget);
      expect(find.text('Bi'), findsOneWidget);
      expect(find.textContaining('2 thiết bị'), findsOneWidget);

      await tester.tap(find.text('Cho bé chơi'));
      await tester.pumpAndSettle();

      expect(find.text('Chụp & Học'), findsOneWidget, reason: 'về Home');
      expect(find.text('Bi'), findsOneWidget, reason: 'chip tên bé');
      expect(find.text('Chọn bé'), findsNothing);
      expect(auth.inChildMode, isTrue);
    });

    testUi('thêm bé: gửi biệt danh + avatar rồi tải lại danh sách', (tester) async {
      var created = false;
      server
        ..handle('GET /api/children', (_) => FakeServer.json(200, created ? [childJson(nickname: 'Na', id: 'c2')] : []))
        ..handle('POST /api/children', (_) {
          created = true;
          return FakeServer.json(201, childJson(nickname: 'Na', id: 'c2'));
        });
      await tester.pumpWidget(const EnglishCamApp());
      await signInParent(tester);
      await tester.pump();
      await tester.tap(find.text('Chọn bé'));
      await tester.pumpAndSettle();
      await passGate(tester);
      expect(find.textContaining('Chưa có hồ sơ bé'), findsOneWidget);

      await tester.tap(find.text('Thêm bé'));
      await tester.pumpAndSettle();
      await enter(tester, 'Biệt danh của bé', '  Na ');
      await tester.tap(find.byTooltip('Cáo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Thêm bé'));
      await tester.pumpAndSettle();

      final body = server.bodyOf(server.to('POST /api/children').single);
      expect(body['nickname'], 'Na');
      expect(body['avatarKey'], 'fox');
      expect(find.text('Na'), findsOneWidget);
    });

    testUi('biệt danh trống bị chặn', (tester) async {
      server.on('GET /api/children', 200, <Object>[]);
      await tester.pumpWidget(const EnglishCamApp());
      await signInParent(tester);
      await tester.pump();
      await tester.tap(find.text('Chọn bé'));
      await tester.pumpAndSettle();
      await passGate(tester);
      await tester.tap(find.text('Thêm bé'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Thêm bé'));
      await tester.pumpAndSettle();
      expect(find.text('Biệt danh cần từ 1 đến 30 ký tự.'), findsOneWidget);
      expect(server.to('POST /api/children'), isEmpty);
    });

    testUi('hồ sơ bị tắt: nút Cho bé chơi vô hiệu', (tester) async {
      server.on('GET /api/children', 200, [childJson(active: false)]);
      await tester.pumpWidget(const EnglishCamApp());
      await signInParent(tester);
      await tester.pump();
      await tester.tap(find.text('Chọn bé'));
      await tester.pumpAndSettle();
      await passGate(tester);
      expect(find.text('Đang tắt'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.ancestor(of: find.text('Cho bé chơi'), matching: find.byType(FilledButton))).onPressed, isNull);
    });

    testUi('lỗi tải danh sách: hiện lỗi và nút Thử lại', (tester) async {
      var fail = true;
      server.handle('GET /api/children', (_) => fail ? FakeServer.json(500, null) : FakeServer.json(200, [childJson()]));
      await tester.pumpWidget(const EnglishCamApp());
      await signInParent(tester);
      await tester.pump();
      await tester.tap(find.text('Chọn bé'));
      await tester.pumpAndSettle();
      await passGate(tester);
      expect(find.textContaining('HTTP 500'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Bi'), findsOneWidget);
    });

    testUi('chi tiết bé: thiết bị, gỡ máy, lưu mục tiêu/giới hạn, mã liên kết', (tester) async {
      server
        ..on('GET /api/children', 200, [childJson()])
        ..on('GET /api/children/c1/sessions', 200, [
          {
            'id': 's1',
            'deviceId': 'd1',
            'deviceName': 'Samsung A51',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'lastUsedAt': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String(),
            'expiresAt': DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String(),
          },
        ])
        ..on('DELETE /api/children/c1/sessions/s1', 204)
        ..on('PUT /api/children/c1/settings', 200, childJson(goal: 6, limit: 35))
        ..on('POST /api/children/c1/link-code', 200, {
          'code': '12345678',
          'expiresAt': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
        });
      await tester.pumpWidget(const EnglishCamApp());
      await signInParent(tester);
      await tester.pump();
      await tester.tap(find.text('Chọn bé'));
      await tester.pumpAndSettle();
      await passGate(tester);
      await tester.tap(find.text('Quản lý'));
      await tester.pumpAndSettle();

      expect(find.text('Samsung A51'), findsOneWidget);
      expect(find.text('Dùng 5 phút trước'), findsOneWidget);

      // mục tiêu 5 → 6; bật giới hạn (mặc định 30) → 35
      await tester.ensureVisible(find.text('Lưu mục tiêu'));
      await tester.tap(find.byTooltip('Tăng').first);
      await tester.pump();
      await tester.tap(find.text('Giới hạn thời gian chơi'));
      await tester.pump();
      await tester.tap(find.byTooltip('Tăng').last);
      await tester.pump();
      await tester.tap(find.text('Lưu mục tiêu'));
      await tester.pumpAndSettle();
      expect(server.bodyOf(server.to('PUT /api/children/c1/settings').single), {
        'dailyLimitMinutes': 35,
        'dailyWordGoal': 6,
      });

      // mã liên kết
      await tester.ensureVisible(find.text('Thêm máy cho bé (nhập mã)'));
      await tester.tap(find.text('Thêm máy cho bé (nhập mã)'));
      await tester.pumpAndSettle();
      expect(find.text('1234 5678'), findsOneWidget);
      expect(find.textContaining('Hết hạn sau'), findsOneWidget);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();

      // gỡ máy
      await tester.ensureVisible(find.byTooltip('Gỡ máy này'));
      await tester.tap(find.byTooltip('Gỡ máy này'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Gỡ máy'));
      await tester.pumpAndSettle();
      expect(server.to('DELETE /api/children/c1/sessions/s1'), hasLength(1));
    });

    testUi('xoá hồ sơ cần xác nhận', (tester) async {
      server
        ..on('GET /api/children', 200, [childJson()])
        ..on('GET /api/children/c1/sessions', 200, <Object>[])
        ..on('DELETE /api/children/c1', 204);
      await tester.pumpWidget(const EnglishCamApp());
      await signInParent(tester);
      await tester.pump();
      await tester.tap(find.text('Chọn bé'));
      await tester.pumpAndSettle();
      await passGate(tester);
      await tester.tap(find.text('Quản lý'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Xoá hồ sơ này'));
      await tester.tap(find.text('Xoá hồ sơ này'));
      await tester.pumpAndSettle();
      expect(server.to('DELETE /api/children/c1'), isEmpty, reason: 'chưa xác nhận thì chưa xoá');
      await tester.tap(find.text('Giữ lại'));
      await tester.pumpAndSettle();
      expect(server.to('DELETE /api/children/c1'), isEmpty);

      await tester.tap(find.text('Xoá hồ sơ này'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Xoá hồ sơ'));
      await tester.pumpAndSettle();
      expect(server.to('DELETE /api/children/c1'), hasLength(1));
    });
  });

  group('Dashboard từ danh sách bé', () {
    testUi('thẻ bé hiện số liệu tóm tắt; nút Tiến độ mở dashboard', (tester) async {
      server
        ..on('GET /api/children', 200, [childJson(devices: 1)])
        ..on('GET /api/parent/overview', 200, [overviewJson()])
        ..on('GET /api/parent/children/c1/dashboard', 200, dashboardJson());
      await tester.pumpWidget(const EnglishCamApp());
      await signInParent(tester);
      await tester.pump();
      await tester.tap(find.text('Chọn bé'));
      await tester.pumpAndSettle();
      await passGate(tester);

      expect(find.text('⭐ 24 · 🔥 3 ngày · 12/60 từ · hôm nay 12 phút'), findsOneWidget);
      await tester.tap(find.text('Tiến độ'));
      await tester.pumpAndSettle();
      expect(find.text('Tiến độ của Bi'), findsOneWidget);
      expect(find.text('12/60'), findsOneWidget);
      expect(server.to('GET /api/parent/children/c1/dashboard').single.url.query, 'days=7');
      expect(server.to('GET /api/parent/children/c1/dashboard').single.headers['Authorization'], 'Bearer tok-parent');
    });

    testUi('không lấy được số liệu tóm tắt thì danh sách bé vẫn dùng được', (tester) async {
      server
        ..on('GET /api/children', 200, [childJson()])
        ..on('GET /api/parent/overview', 500);
      await tester.pumpWidget(const EnglishCamApp());
      await signInParent(tester);
      await tester.pump();
      await tester.tap(find.text('Chọn bé'));
      await tester.pumpAndSettle();
      await passGate(tester);
      expect(find.text('Bi'), findsOneWidget);
      expect(find.textContaining('⭐'), findsNothing);
      expect(find.text('Cho bé chơi'), findsOneWidget);
      expect(find.textContaining('HTTP 500'), findsNothing, reason: 'lỗi số liệu phụ không được hiện như lỗi cả màn');
    });
  });

  group('Máy của bé', () {
    testUi('nhập mã 8 số → liên kết → Home hiện bé, không cần đăng nhập', (tester) async {
      server
        ..on('POST /api/auth/child-link', 200, authJson(role: 'Child', token: 'tok-child', name: 'Bi', email: ''))
        ..on('GET /api/child/me', 200, childJson());
      await tester.pumpWidget(const EnglishCamApp());
      await openSettings(tester);
      await tester.tap(find.text('Máy của bé? Nhập mã liên kết'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Liên kết'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập đủ mã 8 số.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1234 5678');
      await tester.tap(find.text('Liên kết'));
      await tester.pumpAndSettle();

      expect(server.bodyOf(server.to('POST /api/auth/child-link').single)['code'], '12345678');
      expect(find.text('Chụp & Học'), findsOneWidget);
      expect(find.text('Bi'), findsOneWidget);
      expect(auth.inChildMode, isTrue);
      expect(auth.isParentSignedIn, isFalse);
    });

    testUi('mã sai hiện thông báo của máy chủ', (tester) async {
      server.on('POST /api/auth/child-link', 401, {'message': 'Mã không đúng hoặc đã hết hạn'});
      await tester.pumpWidget(const EnglishCamApp());
      await openSettings(tester);
      await tester.tap(find.text('Máy của bé? Nhập mã liên kết'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '00000000');
      await tester.tap(find.text('Liên kết'));
      await tester.pumpAndSettle();
      expect(find.text('Mã không đúng hoặc đã hết hạn'), findsOneWidget);
      expect(auth.inChildMode, isFalse);
    });

    testUi('máy đã liên kết: Cài đặt cho phép gỡ máy khỏi hồ sơ bé (có xác nhận)', (tester) async {
      server
        ..on('POST /api/auth/child-link', 200, authJson(role: 'Child', token: 'tok-child', name: 'Bi', email: ''))
        ..on('GET /api/child/me', 200, childJson())
        ..on('POST /api/auth/logout', 204);
      await tester.runAsync(() => auth.linkWithCode('12345678'));
      await tester.pumpWidget(const EnglishCamApp());
      await openSettings(tester);

      expect(find.text('Bé đang dùng máy này: Bi'), findsOneWidget);
      expect(find.text('Máy của bé? Nhập mã liên kết'), findsNothing);
      await tester.tap(find.text('Bé đang dùng máy này: Bi'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Thoát'));
      await tester.pumpAndSettle();

      expect(auth.inChildMode, isFalse);
      expect(server.to('POST /api/auth/logout'), hasLength(1));
      expect(find.text('Máy của bé? Nhập mã liên kết'), findsOneWidget);
    });

    testUi('bị bố mẹ gỡ máy (401): chip biến mất, có thông báo', (tester) async {
      server
        ..on('POST /api/auth/child-link', 200, authJson(role: 'Child', token: 'tok-child', name: 'Bi', email: ''))
        ..on('GET /api/child/me', 200, childJson());
      await tester.runAsync(() => auth.linkWithCode('12345678'));
      await tester.pumpWidget(const EnglishCamApp());
      expect(find.text('Bi'), findsOneWidget);

      server.on('GET /api/child/me', 401);
      await tester.runAsync(() async {
        try {
          await auth.api.get('/api/child/me', auth: ApiAuth.child);
        } on ApiException {
          // mong đợi
        }
      });
      await tester.pump();
      expect(find.text('Bi'), findsNothing);
      expect(auth.notice.value, contains('gỡ khỏi hồ sơ'));
    });
  });

  group('Đăng xuất', () {
    testUi('từ màn Hồ sơ của bé: hỏi xác nhận rồi về chế độ khách', (tester) async {
      server
        ..on('GET /api/children', 200, <Object>[])
        ..on('POST /api/auth/logout', 204);
      await tester.pumpWidget(const EnglishCamApp());
      await signInParent(tester);
      await tester.pump();
      await tester.tap(find.text('Chọn bé'));
      await tester.pumpAndSettle();
      await passGate(tester);

      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng xuất'));
      await tester.pumpAndSettle();

      expect(auth.isGuest, isTrue);
      expect(find.text('Chụp & Học'), findsOneWidget, reason: 'tự về Home');
      expect(find.text('Chọn bé'), findsNothing);
    });
  });

  group('Hộp thoại mã liên kết', () {  // dùng testWidgets thường
    Future<void> open(WidgetTester tester, Future<LinkCode> Function() create) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showLinkCodeDialog(context, childName: 'Bi', create: create),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
    }

    testWidgets('mã hết hạn hiện gạch ngang và cho tạo mã mới', (tester) async {
      var n = 0;
      await open(tester, () async {
        n++;
        return LinkCode(
          code: n == 1 ? '11112222' : '33334444',
          expiresAt: n == 1
              ? DateTime.now().toUtc().subtract(const Duration(seconds: 5))
              : DateTime.now().toUtc().add(const Duration(minutes: 10)),
        );
      });
      expect(find.text('Mã đã hết hạn'), findsOneWidget);
      await tester.tap(find.text('Tạo mã mới'));
      await tester.pumpAndSettle();
      expect(find.text('3333 4444'), findsOneWidget);
      expect(find.textContaining('Hết hạn sau'), findsOneWidget);
    });

    testWidgets('lỗi mạng: hiện lỗi và cho thử lại', (tester) async {
      await open(tester, () async => throw const ApiException('Không kết nối được máy chủ. Kiểm tra mạng của bạn.'));
      expect(find.textContaining('Không kết nối được'), findsOneWidget);
      expect(find.text('Tạo mã mới'), findsOneWidget);
    });
  });
}

class GoogleCancelledForTest implements Exception {}

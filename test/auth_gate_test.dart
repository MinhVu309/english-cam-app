import 'package:english_cam/core/api_client.dart';
import 'package:english_cam/core/back_interceptor.dart';
import 'package:english_cam/core/widgets/fun_background.dart';
import 'package:english_cam/data/game_badge.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/features/account/auth_gate.dart';
import 'package:english_cam/main.dart';
import 'package:english_cam/services/app_settings.dart';
import 'package:english_cam/services/audio_service.dart';
import 'package:english_cam/services/auth_service.dart';
import 'package:english_cam/services/game_progress.dart';
import 'package:english_cam/services/key_value_store.dart';
import 'package:english_cam/services/progress_service.dart';
import 'package:english_cam/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

void testUi(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await body(tester);
  });
}

/// Bắt buộc đăng nhập: chưa có phiên nào thì chỉ thấy màn chào, chạm vào app bên dưới không được.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  late AuthService auth;
  late MemoryKeyValueStore store;

  AuthService makeAuth() => AuthService(
    api: ApiClient(baseUrl: 'https://api.test', transport: server.call),
    store: store,
    google: FakeGoogle(),
    device: FakeDevice(),
  );

  setUp(() async {
    BackInterceptor.ensureRegistered(); // như main(): trước khi dựng MaterialApp
    AuthGate.required = true;
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    await AppSettings.instance.init();
    AudioService.instance.disabled = true;
    await VocabRepository.load();
    await BadgeRepository.load();
    GameProgress.instance.resetForTest();
    await ProgressService.instance.init();
    server = FakeServer()
      ..on('GET /api/progress/me', 200, {
        'stars': 0,
        'rounds': 0,
        'perfectRounds': 0,
        'found': 0,
        'currentStreak': 0,
        'bestStreak': 0,
        'learnedWordIds': <String>[],
        'badgeIds': <String>[],
        'dailyWordGoal': 5,
        'dailyLimitMinutes': null,
        'today': {'seconds': 0, 'wordsLearned': 0, 'rounds': 0, 'scans': 0},
        'serverTime': DateTime.now().toUtc().toIso8601String(),
      })
      ..on('GET /api/games/badges', 200, <Object>[])
      ..on('POST /api/auth/logout', 204);
    store = MemoryKeyValueStore();
    auth = makeAuth();
    AuthService.instance = auth;
    SyncService.instance = SyncService(auth: auth, autoFlush: false);
    await SyncService.instance.attach();
  });

  tearDown(() {
    SyncService.instance.detach();
    SyncService.instance = SyncService();
    AuthService.instance = AuthService();
    AuthGate.required = false;
  });

  testUi('chưa đăng nhập: thấy màn chào; app bên dưới (Home) không bấm được', (
    tester,
  ) async {
    await tester.pumpWidget(const EnglishCamApp());
    await tester.pumpAndSettle();
    expect(find.text('Chào mừng đến English Cam!'), findsOneWidget);
    expect(find.text('Bố mẹ: đăng nhập / đăng ký'), findsOneWidget);
    expect(find.text('Máy của bé: nhập mã liên kết'), findsOneWidget);
    // Cổng phải có nền đặc riêng (ngoài FunBackground của app), nếu không Home bên dưới lộ xuyên qua các màn đăng nhập.
    expect(
      find.ancestor(
        of: find.byType(AuthGateScope),
        matching: find.byType(FunBackground),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AuthGateScope),
        matching: find.byType(FunBackground),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byTooltip('Cài đặt (dành cho bố mẹ)'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Dành cho bố mẹ'),
      findsNothing,
      reason: 'cổng phụ huynh của Cài đặt không được mở ra',
    );
    expect(find.text('Chào mừng đến English Cam!'), findsOneWidget);
  });

  testUi(
    'nút Back của hệ thống trong cổng: lùi một màn (đăng nhập → màn chào), không thoát app',
    (tester) async {
      await tester.pumpWidget(const EnglishCamApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Máy của bé: nhập mã liên kết'));
      await tester.pumpAndSettle();
      expect(find.text('Máy của bé'), findsOneWidget);

      await tester.binding.handlePopRoute(); // Back của Android
      await tester.pumpAndSettle();
      expect(
        find.text('Chào mừng đến English Cam!'),
        findsOneWidget,
        reason: 'về màn chào của cổng',
      );
      expect(find.text('Máy của bé'), findsNothing);
    },
  );

  testUi(
    'phụ huynh đăng nhập (email + OTP) → cổng biến mất → tới trang Hồ sơ của bé',
    (tester) async {
      server
        ..on('POST /api/auth/login', 200, {'requiresOtp': true})
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('GET /api/children', 200, <Object>[]);
      await tester.pumpWidget(const EnglishCamApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bố mẹ: đăng nhập / đăng ký'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'lan@test.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Mật khẩu'),
        'Matkhau123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập mã OTP'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();

      expect(find.text('Chào mừng đến English Cam!'), findsNothing);
      expect(find.text('Hồ sơ của bé'), findsOneWidget);
      expect(auth.isParentSignedIn, isTrue);
    },
  );

  testUi('admin đăng nhập → tới trang Quản trị', (tester) async {
    server
      ..on('POST /api/auth/login', 200, {'requiresOtp': true})
      ..on(
        'POST /api/auth/verify-otp',
        200,
        authJson(role: 'Admin', name: 'Quản trị viên'),
      )
      ..on('GET /api/admin/vocab/status', 200, {
        'publishedVersion': 1,
        'hasUnpublishedChanges': false,
        'activeWords': 60,
        'activeCategories': 11,
      })
      ..on('GET /api/admin/stats', 500, null);
    await tester.pumpWidget(const EnglishCamApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bố mẹ: đăng nhập / đăng ký'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'admin@test.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Mật khẩu'),
      'Matkhau123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Quản trị'), findsOneWidget);
    expect(find.text('Phiên bản 1 · 60 từ · 11 chủ đề'), findsOneWidget);
  });

  testUi('máy của bé: nhập mã liên kết → vào thẳng Home của bé', (
    tester,
  ) async {
    server
      ..on(
        'POST /api/auth/child-link',
        200,
        authJson(
          role: 'Child',
          token: 'tok-child',
          userId: 'kid-1',
          name: 'Bi',
          email: '',
        ),
      )
      ..on('GET /api/child/me', 200, childJson());
    await tester.pumpWidget(const EnglishCamApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Máy của bé: nhập mã liên kết'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12345678');
    await tester.tap(find.widgetWithText(FilledButton, 'Liên kết'));
    await tester.pumpAndSettle();

    expect(find.text('Chào mừng đến English Cam!'), findsNothing);
    expect(auth.inChildMode, isTrue);
    expect(
      find.byTooltip('Cài đặt (dành cho bố mẹ)'),
      findsOneWidget,
      reason: 'đang ở Home',
    );
  });

  testUi('mã sai: ở lại cổng và hiện lỗi', (tester) async {
    server.on('POST /api/auth/child-link', 401, {
      'message': 'Mã không đúng hoặc đã hết hạn',
    });
    await tester.pumpWidget(const EnglishCamApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Máy của bé: nhập mã liên kết'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12345678');
    await tester.tap(find.widgetWithText(FilledButton, 'Liên kết'));
    await tester.pumpAndSettle();
    expect(find.text('Mã không đúng hoặc đã hết hạn'), findsOneWidget);
    expect(auth.isGuest, isTrue);
  });

  testUi('đã có phiên (kể cả mất mạng): không hiện cổng', (tester) async {
    server.on('POST /api/auth/verify-otp', 200, authJson());
    await tester.runAsync(() => auth.verifyOtp('lan@test.com', '123456'));
    // mở lại app khi mất mạng: phiên đọc từ máy
    server = FakeServer();
    final reopened = makeAuth();
    AuthService.instance = reopened;
    await tester.runAsync(reopened.init);
    await tester.pumpWidget(const EnglishCamApp());
    await tester.pumpAndSettle();
    expect(find.text('Chào mừng đến English Cam!'), findsNothing);
    expect(find.byTooltip('Cài đặt (dành cho bố mẹ)'), findsOneWidget);
  });

  testUi('đăng xuất hoặc phiên bị thu hồi: cổng hiện lại', (tester) async {
    server.on('POST /api/auth/verify-otp', 200, authJson());
    await tester.runAsync(() => auth.verifyOtp('lan@test.com', '123456'));
    await tester.pumpWidget(const EnglishCamApp());
    await tester.pumpAndSettle();
    expect(find.text('Chào mừng đến English Cam!'), findsNothing);

    await tester.runAsync(auth.signOut);
    await tester.pumpAndSettle();
    expect(find.text('Chào mừng đến English Cam!'), findsOneWidget);
  });
}

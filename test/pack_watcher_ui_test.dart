import 'dart:io';

import 'package:english_cam/core/theme.dart';
import 'package:english_cam/data/game_badge.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/main.dart';
import 'package:english_cam/services/game_progress.dart';
import 'package:english_cam/services/progress_service.dart';
import 'package:english_cam/data/pack/pack_manifest.dart';
import 'package:english_cam/data/pack/pack_store.dart';
import 'package:english_cam/data/pack/sha256.dart';
import 'package:english_cam/features/settings/settings_screen.dart';
import 'package:english_cam/services/app_settings.dart';
import 'package:english_cam/services/pack_watcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

PackManifest manifest(int version) => PackManifest(
  version: version,
  files: [
    PackFile(path: 'vocab.json', sha256: Sha256.hex(const [1]), size: 1),
  ],
);

/// Theo dõi trong app thật: hẹn giờ kiểm tra, kiểm tra lại khi app quay lại, và dấu "có bản mới" ở Cài đặt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  var fetches = 0;
  var now = DateTime(2026, 10, 30, 10);

  PackWatcher make({
    int version = 3,
    Duration interval = const Duration(minutes: 30),
  }) => PackWatcher(
    store: () => PackStore.instance,
    enabled: () => true,
    clock: () => now,
    interval: interval,
    fetch: (_) async {
      fetches++;
      return manifest(version);
    },
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
    tmp = await Directory.systemTemp.createTemp('pack_watcher_ui');
    PackStore.instance = PackStore(Directory('${tmp.path}/vocab_pack'));
    fetches = 0;
    now = DateTime(2026, 10, 30, 10);
  });

  tearDown(() async {
    PackStore.instance = null;
    await tmp.delete(recursive: true);
  });

  testWidgets('start(): kiểm tra sau độ trễ đầu rồi định kỳ; stop() thì dừng', (
    tester,
  ) async {
    final w = make();
    w.start();
    await tester.pump(const Duration(seconds: 5));
    expect(fetches, 0, reason: 'chưa tranh mạng với lúc khởi động');
    await tester.pump(const Duration(seconds: 2));
    expect(fetches, 1);
    expect(w.available!.version, 3);

    now = now.add(const Duration(minutes: 31));
    await tester.pump(const Duration(minutes: 30));
    expect(fetches, 2, reason: 'định kỳ mỗi 30 phút');

    w.stop();
    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(hours: 2));
    expect(fetches, 2);
    w.dispose();
  });

  testWidgets(
    'quay lại app (resumed) thì kiểm tra lại, nhưng không dồn dập nếu vừa kiểm tra',
    (tester) async {
      final w = make()..start();
      await tester.pump(const Duration(seconds: 7));
      expect(fetches, 1);

      w.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(fetches, 1, reason: 'vừa kiểm tra xong, chưa tới 5 phút');

      now = now.add(const Duration(minutes: 6));
      w.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(fetches, 1, reason: 'chỉ resumed mới kiểm tra');
      w.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(fetches, 2);
      w.dispose();
    },
  );

  testWidgets(
    'mở app lúc chưa đăng nhập: đăng nhập xong là kiểm tra ngay, không chờ 30 phút',
    (tester) async {
      final auth = ValueNotifier<int>(0);
      var signedIn = false;
      final w = PackWatcher(
        store: () => PackStore.instance,
        enabled: () => signedIn,
        auth: auth,
        clock: () => now,
        fetch: (_) async {
          fetches++;
          return manifest(5);
        },
      )..start();
      await tester.pump(const Duration(seconds: 7));
      expect(fetches, 0, reason: 'chưa đăng nhập: không gọi mạng');

      auth.value++; // phiên đổi nhưng vẫn chưa đăng nhập
      await tester.pump();
      expect(fetches, 0);

      signedIn = true;
      auth.value++;
      await tester.pump();
      expect(fetches, 1);
      expect(w.available!.version, 5);

      auth.value++; // đổi phiên khác khi đã đăng nhập: không kiểm tra lại
      await tester.pump();
      expect(fetches, 1);
      w.dispose();
    },
  );

  testWidgets('start() gọi hai lần không tạo hai bộ hẹn giờ', (tester) async {
    final w = make();
    w.start();
    w.start();
    await tester.pump(const Duration(seconds: 7));
    expect(fetches, 1);
    w.dispose();
  });

  notificationTests();

  group('Cài đặt', () {
    Future<void> openSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const SettingsScreen()),
      );
    }

    tearDown(() => PackWatcher.instance = PackWatcher());

    testWidgets('chưa có bản mới: dòng mô tả bình thường, không có dấu', (
      tester,
    ) async {
      PackWatcher.instance = make(version: kBundledPackVersion);
      await openSettings(tester);
      expect(find.text('Tải thêm từ mới khi có mạng'), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    });

    testWidgets(
      'có bản mới: Cài đặt hiện dấu và "Có bản mới: bản N"; cập nhật xong thì mất',
      (tester) async {
        final w = PackWatcher.instance = make(version: 4);
        await tester.runAsync(() => w.check(force: true));
        await openSettings(tester);
        expect(
          find.text('Có bản mới: bản 4. Bấm để cập nhật.'),
          findsOneWidget,
        );
        expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);

        w.markUpdated();
        await tester.pump();
        expect(find.text('Tải thêm từ mới khi có mạng'), findsOneWidget);
        expect(
          tester.widget<Badge>(find.byType(Badge)).isLabelVisible,
          isFalse,
        );
      },
    );
  });
}

/// Thông báo trong app khi có bản từ vựng mới: SnackBar → (bố mẹ) cổng phép nhân → màn cập nhật.
void notificationTests() {
  group('Thông báo trong app', () {
    late Directory tmp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'onboarding_done': true});
      await AppSettings.instance.init();
      await VocabRepository.load();
      await BadgeRepository.load();
      GameProgress.instance.resetForTest();
      await ProgressService.instance.init();
      tmp = await Directory.systemTemp.createTemp('pack_notice');
      PackStore.instance = PackStore(Directory('${tmp.path}/vocab_pack'));
      PackWatcher.instance = PackWatcher(
        store: () => PackStore.instance,
        enabled: () => true,
        fetch: (_) async => manifest(7),
      );
    });

    tearDown(() async {
      PackWatcher.instance = PackWatcher();
      PackStore.instance = null;
      await tmp.delete(recursive: true);
    });

    testWidgets(
      'có bản mới: SnackBar báo; bấm "Cập nhật" phải qua cổng phép nhân rồi mới mở màn cập nhật',
      (tester) async {
        tester.view.physicalSize = const Size(900, 2600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const EnglishCamApp());
        await tester.pumpAndSettle();

        showPackNotice(manifest(7));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.textContaining('Có từ vựng mới!'), findsOneWidget);
        // Không được che nút chính ở đáy màn hình và phải tự ẩn (SnackBar có nút bấm mặc định không tự ẩn).
        final bar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(bar.persist, isFalse);
        expect(bar.behavior, SnackBarBehavior.floating);
        expect(
          bar.margin!.resolve(TextDirection.ltr).bottom,
          greaterThanOrEqualTo(150),
        );

        await tester.tap(find.text('Cập nhật'));
        await tester.pumpAndSettle();
        expect(
          find.text('Cập nhật từ vựng'),
          findsNothing,
          reason: 'bé chưa qua được cổng phụ huynh',
        );
        final q = find.textContaining(RegExp(r'\d × \d = \?'));
        expect(q, findsOneWidget);
        final m = RegExp(
          r'(\d) × (\d)',
        ).firstMatch(tester.widget<Text>(q).data!)!;
        await tester.enterText(
          find.byType(TextField),
          '${int.parse(m[1]!) * int.parse(m[2]!)}',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Mở'));
        await tester.pumpAndSettle();

        expect(find.text('Cập nhật từ vựng'), findsOneWidget);
      },
    );

    testWidgets('trả lời sai cổng: không vào được màn cập nhật', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const EnglishCamApp());
      await tester.pumpAndSettle();
      showPackNotice(manifest(7));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Cập nhật'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.widgetWithText(FilledButton, 'Mở'));
      await tester.pumpAndSettle();
      expect(find.text('Cập nhật từ vựng'), findsNothing);
      expect(find.text('Chưa đúng, thử phép tính mới nhé.'), findsOneWidget);
    });
  });
}

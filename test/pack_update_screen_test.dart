import 'dart:io';

import 'package:english_cam/core/api_config.dart';
import 'package:english_cam/core/theme.dart';
import 'package:english_cam/data/pack/pack_manifest.dart';
import 'package:english_cam/data/pack/pack_store.dart';
import 'package:english_cam/data/pack/pack_updater.dart';
import 'package:english_cam/data/pack/sha256.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/features/settings/pack_update_screen.dart';
import 'package:english_cam/services/app_settings.dart';
import 'package:english_cam/services/pack_watcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUpdater extends PackUpdater {
  _FakeUpdater(super.store, this.outcome) : super(allowInsecure: true);

  final Future<PackUpdateResult> Function(String url) outcome;
  final urls = <String>[];

  @override
  Future<PackUpdateResult> update(
    String baseUrl, {
    void Function(int done, int total)? onProgress,
  }) {
    urls.add(baseUrl);
    onProgress?.call(1, 2);
    return outcome(baseUrl);
  }
}

PackManifest _manifest(int version, {String? notes}) => PackManifest(
  version: version,
  notes: notes,
  files: [
    PackFile(path: 'vocab.json', sha256: Sha256.hex(const [1]), size: 1),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
    await VocabRepository.load();
    tmp = await Directory.systemTemp.createTemp('pack_screen');
    PackStore.instance = PackStore(Directory('${tmp.path}/vocab_pack'));
  });

  tearDown(() async {
    PackStore.instance = null;
    await tmp.delete(recursive: true);
  });

  /// Theo dõi bản mới với "máy chủ" giả luôn trả [latest] (hoặc lỗi nếu [error]).
  PackWatcher watcherFor({int? latest, Object? error}) => PackWatcher(
    enabled: () => true,
    fetch: (url) async {
      if (error != null) throw error;
      return _manifest(latest ?? 1);
    },
  );

  Future<void> open(
    WidgetTester tester,
    _FakeUpdater updater, {
    PackWatcher? watcher,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: PackUpdateScreen(
          updater: updater,
          reloadModel: () async {},
          watcher: watcher ?? watcherFor(latest: 1),
        ),
      ),
    );
  }

  /// Chờ các tác vụ đọc file/asset thật (ngoài đồng hồ giả của testWidgets).
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  testWidgets('hiện bản đang dùng; chưa cài gói thì không có nút về bản gốc', (
    tester,
  ) async {
    await open(tester, _FakeUpdater(PackStore.instance!, (_) async => throw 0));
    final words = VocabRepository.instance.words.length;
    expect(
      find.text('Đang dùng: Bản đóng gói sẵn · $words từ'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pack-revert')), findsNothing);
  });

  testWidgets(
    'lỗi: hiện thông điệp, không đổi gì, dùng địa chỉ mặc định và không lưu gì',
    (tester) async {
      final updater = _FakeUpdater(
        PackStore.instance!,
        (_) async => throw const PackUpdateException('Không kết nối được.'),
      );
      await open(tester, updater);
      await tester.tap(
        find.byKey(const Key('pack-update')),
      ); // không phải nhập gì
      await settle(tester);

      expect(find.text('Không kết nối được.'), findsOneWidget);
      expect(updater.urls, [kDefaultPackUrl]);
      expect(AppSettings.instance.packUrl, kDefaultPackUrl);
      expect(
        (await SharedPreferences.getInstance()).getString('pack_url'),
        isNull,
      );
    },
  );

  testWidgets('đã mới nhất: báo bản hiện tại', (tester) async {
    final updater = _FakeUpdater(
      PackStore.instance!,
      (_) async => PackUpdateResult(changed: false, manifest: _manifest(4)),
    );
    await open(tester, updater);
    await tester.tap(find.byKey(const Key('pack-update')));
    await settle(tester);

    expect(find.text('Đã là bản mới nhất (bản 4).'), findsOneWidget);
    expect(updater.urls, [kDefaultPackUrl]);
  });

  testWidgets(
    'cập nhật thành công chỉ bằng một lần bấm: nạp lại từ vựng, hiện ghi chú',
    (tester) async {
      final updater = _FakeUpdater(
        PackStore.instance!,
        (_) async => PackUpdateResult(
          changed: true,
          manifest: _manifest(3, notes: 'Thêm 10 từ về nghề nghiệp'),
        ),
      );
      await open(tester, updater);
      await tester.tap(find.byKey(const Key('pack-update')));
      await settle(tester);

      final words = VocabRepository.instance.words.length;
      expect(
        find.textContaining('Đã cập nhật lên bản 3: $words từ.'),
        findsOneWidget,
      );
      expect(find.textContaining('Thêm 10 từ về nghề nghiệp'), findsOneWidget);
      expect(updater.urls, [kDefaultPackUrl]);
    },
  );

  testWidgets(
    'địa chỉ gói mặc định là chính backend của app (không cần PACK_URL)',
    (tester) async {
      expect(kDefaultPackUrl, ApiConfig.packUrl);
      expect(kDefaultPackUrl, endsWith('/api/pack/'));
      expect(kDefaultPackUrl, startsWith(ApiConfig.baseUrl));
    },
  );

  testWidgets(
    'mục Nâng cao: nhập địa chỉ khác thì dùng và nhớ; "dùng lại mặc định" thì quên',
    (tester) async {
      final updater = _FakeUpdater(
        PackStore.instance!,
        (_) async => PackUpdateResult(changed: false, manifest: _manifest(4)),
      );
      await open(tester, updater);
      expect(
        find.byKey(const Key('pack-url')),
        findsNothing,
        reason: 'ô địa chỉ không chiếm màn hình',
      );
      await tester.tap(find.byKey(const Key('pack-advanced')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pack-url')),
        ' https://x.io/p/ ',
      );
      await tester.tap(find.byKey(const Key('pack-update')));
      await settle(tester);

      expect(updater.urls, ['https://x.io/p/']);
      expect(AppSettings.instance.packUrl, 'https://x.io/p/');
      expect(
        (await SharedPreferences.getInstance()).getString('pack_url'),
        'https://x.io/p/',
      );

      await tester.tap(find.byKey(const Key('pack-url-default')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pack-update')));
      await settle(tester);
      expect(AppSettings.instance.packUrl, kDefaultPackUrl);
      expect(
        (await SharedPreferences.getInstance()).getString('pack_url'),
        isNull,
      );
    },
  );

  group('tự biết có bản mới', () {
    testWidgets(
      'mở màn là tự kiểm tra: có bản mới thì nút ghi rõ "Cập nhật ngay (bản N)" kèm ghi chú',
      (tester) async {
        final watcher = PackWatcher(
          enabled: () => true,
          fetch: (_) async => _manifest(3, notes: 'Thêm 2 từ'),
        );
        final updater = _FakeUpdater(
          PackStore.instance!,
          (_) async => PackUpdateResult(changed: true, manifest: _manifest(3)),
        );
        await open(tester, updater, watcher: watcher);
        expect(find.text('Đang kiểm tra bản mới…'), findsOneWidget);
        await settle(tester);

        expect(find.text('Có từ vựng mới: bản 3'), findsOneWidget);
        expect(find.text('Thêm 2 từ'), findsOneWidget);
        expect(find.text('Cập nhật ngay (bản 3)'), findsOneWidget);

        await tester.tap(find.byKey(const Key('pack-update')));
        await settle(tester);
        expect(
          watcher.available,
          isNull,
          reason: 'cập nhật xong thì hết "có bản mới"',
        );
        expect(find.text('Đã là bản mới nhất.'), findsOneWidget);
        expect(find.text('Kiểm tra & cập nhật'), findsOneWidget);
      },
    );

    testWidgets(
      'đang mở màn mà có bản mới hơn: bỏ dòng kết quả của lần cập nhật trước',
      (tester) async {
        var latest = 3;
        final watcher = PackWatcher(
          enabled: () => true,
          fetch: (_) async => _manifest(latest),
        );
        final updater = _FakeUpdater(
          PackStore.instance!,
          (_) async => PackUpdateResult(changed: true, manifest: _manifest(3)),
        );
        await open(tester, updater, watcher: watcher);
        await settle(tester);
        await tester.tap(find.byKey(const Key('pack-update')));
        await settle(tester);
        expect(find.textContaining('Đã cập nhật lên bản 3'), findsOneWidget);

        latest = 4; // Admin vừa xuất bản bản 4
        await tester.runAsync(() => watcher.check(force: true));
        await tester.pump();
        expect(find.text('Có từ vựng mới: bản 4'), findsOneWidget);
        expect(find.textContaining('Đã cập nhật lên bản 3'), findsNothing);
        expect(find.text('Cập nhật ngay (bản 4)'), findsOneWidget);
      },
    );

    testWidgets('đang ở bản mới nhất: nói "Đã là bản mới nhất."', (
      tester,
    ) async {
      await open(
        tester,
        _FakeUpdater(PackStore.instance!, (_) async => throw 0),
        watcher: watcherFor(latest: 1),
      );
      await settle(tester);
      expect(find.text('Đã là bản mới nhất.'), findsOneWidget);
    });

    testWidgets('mất mạng: nói chưa kiểm tra được, vẫn bấm cập nhật được', (
      tester,
    ) async {
      await open(
        tester,
        _FakeUpdater(PackStore.instance!, (_) async => throw 0),
        watcher: watcherFor(
          error: const PackUpdateException('Không kết nối được.'),
        ),
      );
      await settle(tester);
      expect(
        find.textContaining('Chưa kiểm tra được bản mới (Không kết nối được.)'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pack-update')))
            .onPressed,
        isNotNull,
      );
    });
  });
}

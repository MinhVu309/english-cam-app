import 'dart:io';

import 'package:english_cam/core/theme.dart';
import 'package:english_cam/data/pack/pack_manifest.dart';
import 'package:english_cam/data/pack/pack_store.dart';
import 'package:english_cam/data/pack/pack_updater.dart';
import 'package:english_cam/data/pack/sha256.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/features/settings/pack_update_screen.dart';
import 'package:english_cam/services/app_settings.dart';
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

  Future<void> open(WidgetTester tester, _FakeUpdater updater) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: PackUpdateScreen(updater: updater, reloadModel: () async {}),
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

  testWidgets('lỗi: hiện thông điệp, không đổi gì, không lưu địa chỉ', (
    tester,
  ) async {
    final updater = _FakeUpdater(
      PackStore.instance!,
      (_) async => throw const PackUpdateException('Không kết nối được.'),
    );
    await open(tester, updater);
    await tester.enterText(
      find.byKey(const Key('pack-url')),
      'https://x.io/p/',
    );
    await tester.tap(find.byKey(const Key('pack-update')));
    await settle(tester);

    expect(find.text('Không kết nối được.'), findsOneWidget);
    expect(updater.urls, ['https://x.io/p/']);
    expect(AppSettings.instance.packUrl, isEmpty);
  });

  testWidgets('đã mới nhất: báo bản hiện tại', (tester) async {
    final updater = _FakeUpdater(
      PackStore.instance!,
      (_) async => PackUpdateResult(changed: false, manifest: _manifest(4)),
    );
    await open(tester, updater);
    await tester.enterText(
      find.byKey(const Key('pack-url')),
      'https://x.io/p/',
    );
    await tester.tap(find.byKey(const Key('pack-update')));
    await settle(tester);

    expect(find.text('Đã là bản mới nhất (bản 4).'), findsOneWidget);
    expect(AppSettings.instance.packUrl, 'https://x.io/p/');
  });

  testWidgets(
    'cập nhật thành công: nạp lại từ vựng, hiện ghi chú, nhớ địa chỉ',
    (tester) async {
      final updater = _FakeUpdater(
        PackStore.instance!,
        (_) async => PackUpdateResult(
          changed: true,
          manifest: _manifest(3, notes: 'Thêm 10 từ về nghề nghiệp'),
        ),
      );
      await open(tester, updater);
      await tester.enterText(
        find.byKey(const Key('pack-url')),
        ' https://x.io/p/ ',
      );
      await tester.tap(find.byKey(const Key('pack-update')));
      await settle(tester);

      final words = VocabRepository.instance.words.length;
      expect(
        find.textContaining('Đã cập nhật lên bản 3: $words từ.'),
        findsOneWidget,
      );
      expect(find.textContaining('Thêm 10 từ về nghề nghiệp'), findsOneWidget);
      expect(AppSettings.instance.packUrl, 'https://x.io/p/');
      expect(
        (await SharedPreferences.getInstance()).getString('pack_url'),
        'https://x.io/p/',
      );
    },
  );
}

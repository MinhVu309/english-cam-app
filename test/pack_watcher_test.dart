import 'dart:convert';
import 'dart:io';

import 'package:english_cam/data/pack/pack_manifest.dart';
import 'package:english_cam/data/pack/pack_store.dart';
import 'package:english_cam/data/pack/pack_updater.dart';
import 'package:english_cam/data/pack/sha256.dart';
import 'package:english_cam/services/pack_watcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Không gọi TestWidgetsFlutterBinding: binding chặn HttpClient thật, mà nhóm "máy chủ HTTP thật" cần nó.
/// Phần timer/vòng đời của app nằm ở `pack_watcher_ui_test.dart`.

PackManifest manifest(int version, {String? notes}) => PackManifest(
  version: version,
  notes: notes,
  files: [
    PackFile(path: 'vocab.json', sha256: Sha256.hex(const [1]), size: 1),
  ],
);

void main() {
  late Directory tmp;
  late PackStore store;
  var now = DateTime(2026, 10, 30, 10);
  var fetches = 0;
  int? serverVersion;
  Object? serverError;

  PackWatcher make({bool enabled = true, PackStore? Function()? storeFn}) =>
      PackWatcher(
        store: storeFn ?? () => store,
        enabled: () => enabled,
        clock: () => now,
        fetch: (url) async {
          fetches++;
          if (serverError != null) throw serverError!;
          return manifest(serverVersion!, notes: 'ghi chú $serverVersion');
        },
      );

  Future<void> install(int version) async {
    final staging = await store.beginStaging();
    await File('${staging.path}/vocab.json').writeAsString('{}');
    await File(
      '${staging.path}/manifest.json',
    ).writeAsString(jsonEncode(manifest(version).toJson()));
    await store.commit();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('pack_watcher');
    store = PackStore(Directory('${tmp.path}/vocab_pack'));
    now = DateTime(2026, 10, 30, 10);
    fetches = 0;
    serverVersion = 1;
    serverError = null;
  });

  tearDown(() => tmp.delete(recursive: true));

  group('so sánh phiên bản', () {
    test(
      'chưa tải gói nào = bản đóng gói sẵn (bản $kBundledPackVersion): máy chủ cùng bản thì không báo gì',
      () async {
        final w = make();
        final told = <int>[];
        w.onNewVersion = (m) => told.add(m.version);
        serverVersion = kBundledPackVersion;
        expect(await w.check(), isFalse);
        expect(w.available, isNull);
        expect(w.lastError, isNull);
        expect(told, isEmpty);
        expect(w.currentVersion, kBundledPackVersion);
      },
    );

    test('máy chủ có bản mới hơn: đặt available và báo đúng một lần', () async {
      final w = make();
      final told = <int>[];
      var changes = 0;
      w.addListener(() => changes++);
      w.onNewVersion = (m) => told.add(m.version);
      serverVersion = 3;
      expect(await w.check(), isTrue);
      expect(w.available!.version, 3);
      expect(w.available!.notes, 'ghi chú 3');
      expect(told, [3]);
      expect(changes, greaterThan(0));

      expect(await w.check(force: true), isTrue);
      expect(told, [3], reason: 'kiểm tra lại không báo lại cùng phiên bản');
    });

    test(
      'đã báo bản 3 thì mở lại app (đối tượng mới) cũng không báo lại; có bản 4 thì báo',
      () async {
        serverVersion = 3;
        final first = make()..onNewVersion = (_) {};
        await first.check();

        final told = <int>[];
        final second = make()..onNewVersion = (m) => told.add(m.version);
        await second.check();
        expect(
          second.available!.version,
          3,
          reason: 'vẫn đánh dấu "có bản mới" ở Cài đặt',
        );
        expect(
          told,
          isEmpty,
          reason: 'nhưng không làm phiền bằng thông báo lần nữa',
        );

        serverVersion = 4;
        await second.check(force: true);
        expect(told, [4]);
      },
    );

    test(
      'đã tải gói bản 3: máy chủ bản 3 thì không báo, bản 4 thì báo',
      () async {
        await install(3);
        final w = make();
        expect(w.currentVersion, 3);
        serverVersion = 3;
        expect(await w.check(), isFalse);
        serverVersion = 4;
        expect(await w.check(force: true), isTrue);
      },
    );

    test(
      'bản mới biến mất (máy chủ lùi về bản đang dùng, hoặc đã cập nhật): available được xoá',
      () async {
        final w = make();
        serverVersion = 5;
        await w.check();
        expect(w.available, isNotNull);
        var changes = 0;
        w.addListener(() => changes++);
        w.markUpdated();
        expect(w.available, isNull);
        expect(changes, 1);
        w.markUpdated();
        expect(changes, 1, reason: 'không có gì để xoá thì không báo thay đổi');

        await w.check(force: true);
        expect(w.available, isNotNull);
        serverVersion = kBundledPackVersion;
        await w.check(force: true);
        expect(w.available, isNull);
      },
    );
  });

  group('tần suất và điều kiện', () {
    test(
      'không kiểm tra liên tục: trong khoảng giãn cách chỉ hỏi máy chủ một lần; force thì bỏ qua; qua khoảng thì hỏi lại',
      () async {
        final w = make();
        await w.check();
        await w.check();
        await w.check();
        expect(fetches, 1);

        await w.check(force: true);
        expect(fetches, 2);

        now = now.add(const Duration(minutes: 5, seconds: 1));
        await w.check();
        expect(fetches, 3);
      },
    );

    test('hai lần gọi cùng lúc chỉ tải một manifest', () async {
      final w = make();
      await Future.wait([w.check(force: true), w.check(force: true)]);
      expect(fetches, 1);
    });

    test(
      'chưa đăng nhập (khách) hoặc máy không lưu được gói: không gọi mạng',
      () async {
        expect(await make(enabled: false).check(force: true), isFalse);
        expect(await make(storeFn: () => null).check(force: true), isFalse);
        expect(fetches, 0);
      },
    );

    test(
      'lỗi mạng/máy chủ: nuốt lỗi, ghi lastError, không báo, không xoá trạng thái cũ',
      () async {
        final w = make();
        final told = <int>[];
        w.onNewVersion = (m) => told.add(m.version);
        serverVersion = 3;
        await w.check();
        expect(w.available, isNotNull);

        serverError = const PackUpdateException('Không kết nối được.');
        expect(
          await w.check(force: true),
          isTrue,
          reason: 'vẫn nhớ có bản 3 từ lần trước',
        );
        expect(w.lastError, 'Không kết nối được.');
        expect(told, [3]);

        serverError = null;
        await w.check(force: true);
        expect(w.lastError, isNull);
      },
    );
  });

  group('với máy chủ HTTP thật (PackUpdater.fetchLatest)', () {
    late HttpServer server;
    var manifestBody = '';
    var status = 200;
    var hits = <String>[];

    setUp(() async {
      hits = [];
      status = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        hits.add(req.uri.path);
        req.response.statusCode = status;
        if (status == 200) req.response.write(manifestBody);
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    String url() => 'http://127.0.0.1:${server.port}/api/pack/';
    PackWatcher real() => PackWatcher(
      store: () => store,
      enabled: () => true,
      url: url,
      clock: () => now,
    );
    String manifestJson(int v) =>
        jsonEncode(manifest(v, notes: 'Thêm từ mới').toJson());

    test(
      'chỉ tải đúng manifest.json (không tải file nào khác) và phát hiện bản mới',
      () async {
        manifestBody = manifestJson(2);
        final w = real();
        expect(await w.check(), isTrue);
        expect(w.available!.version, 2);
        expect(w.available!.notes, 'Thêm từ mới');
        expect(hits, ['/api/pack/manifest.json']);
      },
    );

    test(
      'máy chủ trả 404/500: báo lỗi bằng tiếng Việt, không có bản mới',
      () async {
        status = 404;
        final w = real();
        expect(await w.check(), isFalse);
        expect(w.lastError, contains('manifest.json'));
        expect(w.lastError, contains('404'));
      },
    );

    test('manifest hỏng: không có bản mới, không văng lỗi', () async {
      manifestBody = '{"version": "x"';
      final w = real();
      expect(await w.check(), isFalse);
      expect(w.lastError, isNotNull);
    });

    test(
      'fetchLatest từ chối địa chỉ không phải https khi chạy thật (allowInsecure=false)',
      () async {
        expect(
          () => PackUpdater(
            store,
            allowInsecure: false,
          ).fetchLatest('http://example.com/p/'),
          throwsA(isA<PackUpdateException>()),
        );
      },
    );
  });
}

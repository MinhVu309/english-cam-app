import 'dart:convert';
import 'dart:io';

import 'package:english_cam/data/pack/pack_manifest.dart';
import 'package:english_cam/data/pack/pack_store.dart';
import 'package:english_cam/data/pack/pack_updater.dart';
import 'package:english_cam/data/pack/sha256.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/services/audio_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Không gọi TestWidgetsFlutterBinding: binding sẽ chặn HttpClient thật,
/// còn các test này cần một máy chủ HTTP cục bộ.

Map<String, dynamic> _word(String id, {String? label, String? audio}) => {
  'id': id,
  'label': ?label,
  'en': id,
  'vi': 'từ $id',
  'phonetic': '/$id/',
  'exampleEn': 'This is $id.',
  'exampleVi': 'Đây là $id.',
  'emoji': '🙂',
  'audio': audio ?? 'audio/words/$id.mp3',
  'category': 'c',
};

String _vocab(List<Map<String, dynamic>> words) => jsonEncode({
  'categories': [
    {'id': 'c', 'vi': 'Chủ đề', 'en': 'Topic'},
  ],
  'words': words,
});

List<Map<String, dynamic>> _fourWords([String extra = 'dog']) => [
  _word('a', label: 'a'),
  _word('b', label: 'b'),
  _word('c', label: 'c'),
  _word(extra),
];

/// Một "hosting" giả: map đường dẫn -> byte, đếm số lần mỗi đường dẫn bị tải.
class _Host {
  final Map<String, List<int>> files = {};
  final Map<String, int> hits = {};
  final Set<String> broken = {}; // trả 500
  final Set<String> corrupt = {}; // trả nội dung sai
  late HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path.substring(1);
      hits[path] = (hits[path] ?? 0) + 1;
      final body = files[path];
      if (body == null) {
        req.response.statusCode = 404;
      } else if (broken.contains(path)) {
        req.response.statusCode = 500;
      } else {
        req.response.add(corrupt.contains(path) ? [...body, 0] : body);
      }
      await req.response.close();
    });
  }

  String get url => 'http://127.0.0.1:${server.port}/pack/';

  /// Đặt file và (tái) tạo manifest.
  void publish(int version, Map<String, List<int>> content, {String? notes}) {
    files.removeWhere((k, _) => k.startsWith('pack/'));
    content.forEach((k, v) => files['pack/$k'] = v);
    files['pack/manifest.json'] = utf8.encode(
      jsonEncode({
        'version': version,
        'notes': ?notes,
        'files': [
          for (final e in content.entries)
            {
              'path': e.key,
              'sha256': Sha256.hex(e.value),
              'size': e.value.length,
            },
        ],
      }),
    );
  }

  Future<void> stop() => server.close(force: true);
}

class _StringBundle extends CachingAssetBundle {
  _StringBundle(this.text);
  final String text;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
}

void main() {
  late Directory tmp;
  late PackStore store;
  late _Host host;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pack_test');
    store = PackStore(Directory('${tmp.path}/vocab_pack'));
    PackStore.instance = store;
    host = _Host();
    await host.start();
  });

  tearDown(() async {
    PackStore.instance = null;
    await host.stop();
    await tmp.delete(recursive: true);
  });

  group('PackManifest', () {
    Map<String, dynamic> manifest(List<Map<String, dynamic>> files) => {
      'version': 1,
      'files': files,
    };
    Map<String, dynamic> file(String path, {String? sha}) => {
      'path': path,
      'sha256': sha ?? Sha256.hex(utf8.encode(path)),
      'size': 3,
    };

    test('chấp nhận gói hợp lệ, kể cả model + labels', () {
      final m = PackManifest.fromJson(
        manifest([
          file('vocab.json'),
          file('audio/words/dog.mp3'),
          file('model.tflite'),
          file('labels.txt'),
        ]),
      );
      expect(m.hasModel, isTrue);
      expect(m.file('audio/words/dog.mp3'), isNotNull);
    });

    test('từ chối đường dẫn nguy hiểm', () {
      for (final bad in [
        '../x.mp3',
        '/etc/passwd',
        'a/../b.mp3',
        'a//b.mp3',
        '.hidden',
        'a b.mp3',
        r'a\b.mp3',
      ]) {
        expect(
          () =>
              PackManifest.fromJson(manifest([file('vocab.json'), file(bad)])),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test(
      'từ chối: thiếu vocab.json, model thiếu labels, sha sai, trùng path',
      () {
        expect(
          () => PackManifest.fromJson(manifest([file('audio/a.mp3')])),
          throwsFormatException,
        );
        expect(
          () => PackManifest.fromJson(
            manifest([file('vocab.json'), file('model.tflite')]),
          ),
          throwsFormatException,
        );
        expect(
          () =>
              PackManifest.fromJson(manifest([file('vocab.json', sha: 'ABC')])),
          throwsFormatException,
        );
        expect(
          () => PackManifest.fromJson(
            manifest([file('vocab.json'), file('vocab.json')]),
          ),
          throwsFormatException,
        );
        expect(
          () => PackManifest.fromJson({'version': 0}),
          throwsFormatException,
        );
      },
    );
  });

  group('VocabRepository', () {
    test(
      'từ không có label vẫn hợp lệ, không nằm trong byLabel, hunt=false',
      () {
        final repo = VocabRepository.fromJsonString(_vocab(_fourWords()));
        expect(repo.words, hasLength(4));
        expect(repo.byId('dog')!.label, isNull);
        expect(repo.byId('dog')!.hunt, isFalse);
        expect(repo.byLabel('a')!.hunt, isTrue);
        expect(repo.byLabel('dog'), isNull);
      },
    );

    test(
      'từ chối vocab sai: trùng id, thiếu chủ đề, path độc hại, ít hình',
      () {
        expect(
          () => VocabRepository.fromJsonString(
            _vocab([..._fourWords(), _word('a')]),
          ),
          throwsFormatException,
        );
        expect(
          () => VocabRepository.fromJsonString(
            _vocab([
              ..._fourWords(),
              {..._word('x'), 'category': 'zzz'},
            ]),
          ),
          throwsFormatException,
        );
        expect(
          () => VocabRepository.fromJsonString(
            _vocab([..._fourWords(), _word('x', audio: '../../secret')]),
          ),
          throwsFormatException,
        );
        expect(
          () =>
              VocabRepository.fromJsonString(_vocab([_word('a'), _word('b')])),
          throwsFormatException,
        );
      },
    );

    test(
      'load(): dùng vocab của gói; gói hỏng thì rơi về bản đóng gói sẵn',
      () async {
        final bundled = _vocab([..._fourWords('bundled')]);
        var repo = await VocabRepository.load(bundle: _StringBundle(bundled));
        expect(repo.byId('bundled'), isNotNull);

        await store.current.create(recursive: true);
        await File(
          '${store.current.path}/vocab.json',
        ).writeAsString(_vocab(_fourWords('fromPack')));
        repo = await VocabRepository.load(bundle: _StringBundle(bundled));
        expect(repo.byId('fromPack'), isNotNull);
        expect(repo.byId('bundled'), isNull);

        await File('${store.current.path}/vocab.json').writeAsString('{hỏng');
        repo = await VocabRepository.load(bundle: _StringBundle(bundled));
        expect(repo.byId('bundled'), isNotNull);
      },
    );
  });

  test('AudioService: asset đóng gói vs file trong gói đã tải', () async {
    expect(
      AudioService.speechSource('assets/audio/words/book.mp3'),
      isA<AssetSource>().having((s) => s.path, 'path', 'audio/words/book.mp3'),
    );
    expect(AudioService.speechSource('audio/words/dog.mp3'), isNull);
    await Directory(
      '${store.current.path}/audio/words',
    ).create(recursive: true);
    await File('${store.current.path}/audio/words/dog.mp3').writeAsBytes([1]);
    expect(
      AudioService.speechSource('audio/words/dog.mp3'),
      isA<DeviceFileSource>(),
    );
    expect(AudioService.speechSource('../vocab_pack/x.mp3'), isNull);
  });

  group('PackStore', () {
    test('fileFor chặn đường dẫn thoát khỏi thư mục gói', () async {
      await store.current.create(recursive: true);
      await File('${tmp.path}/vocab_pack/secret.txt').writeAsString('x');
      expect(store.fileFor('../secret.txt'), isNull);
      expect(store.fileFor('/etc/hosts'), isNull);
    });

    test(
      'recover(): khôi phục bản cũ nếu bị ngắt giữa lúc thay, dọn staging',
      () async {
        await Directory('${store.root.path}/old').create(recursive: true);
        await File('${store.root.path}/old/vocab.json').writeAsString('old');
        await store.beginStaging();
        await store.recover();
        expect(File('${store.current.path}/vocab.json').existsSync(), isTrue);
        expect(store.staging.existsSync(), isFalse);
      },
    );
  });

  group('PackUpdater', () {
    PackUpdater updater() => PackUpdater(store, allowInsecure: true);

    Map<String, List<int>> v1() => {
      'vocab.json': utf8.encode(_vocab(_fourWords('dog'))),
      'audio/words/dog.mp3': [1, 2, 3],
    };

    test('tải gói mới, kiểm tra hash, lưu vào current, báo tiến độ', () async {
      host.publish(1, v1(), notes: 'Thêm con chó');
      final progress = <String>[];
      final r = await updater().update(
        host.url,
        onProgress: (d, t) => progress.add('$d/$t'),
      );
      expect(r.changed, isTrue);
      expect(r.manifest.version, 1);
      expect(progress, ['0/2', '1/2', '2/2']);
      expect(store.readInstalled()!.version, 1);
      expect(store.readInstalled()!.notes, 'Thêm con chó');
      expect(store.fileFor('audio/words/dog.mp3')!.readAsBytesSync(), [
        1,
        2,
        3,
      ]);
      expect(store.staging.existsSync(), isFalse);
      // Từ của gói được nạp vào VocabRepository.
      final repo = await VocabRepository.load(
        bundle: _StringBundle(_vocab(_fourWords('bundled'))),
      );
      expect(repo.byId('dog'), isNotNull);
    });

    test(
      'đã mới nhất thì không tải lại file; bản mới chỉ tải file đổi',
      () async {
        host.publish(1, v1());
        await updater().update(host.url);
        host.hits.clear();

        var r = await updater().update(host.url);
        expect(r.changed, isFalse);
        expect(host.hits.keys, ['pack/manifest.json']);

        // Bản 2: đổi vocab.json, giữ nguyên mp3 cũ, thêm mp3 mới.
        host.publish(2, {
          'vocab.json': utf8.encode(_vocab(_fourWords('cat'))),
          'audio/words/dog.mp3': [1, 2, 3],
          'audio/words/cat.mp3': [9, 9],
        });
        host.hits.clear();
        r = await updater().update(host.url);
        expect(r.changed, isTrue);
        expect(host.hits.containsKey('pack/audio/words/dog.mp3'), isFalse);
        expect(host.hits['pack/audio/words/cat.mp3'], 1);
        expect(store.fileFor('audio/words/dog.mp3')!.readAsBytesSync(), [
          1,
          2,
          3,
        ]);
        expect(store.readInstalled()!.version, 2);
      },
    );

    test(
      'lỗi giữa chừng (500 / sai hash / mất file) giữ nguyên bản đang dùng',
      () async {
        host.publish(1, v1());
        await updater().update(host.url);

        host.publish(2, {
          'vocab.json': utf8.encode(_vocab(_fourWords('cat'))),
          'audio/words/cat.mp3': [9, 9],
        });
        for (final fail in [host.broken, host.corrupt]) {
          fail.add('pack/audio/words/cat.mp3');
          await expectLater(
            updater().update(host.url),
            throwsA(isA<PackUpdateException>()),
          );
          fail.clear();
          expect(store.readInstalled()!.version, 1, reason: 'giữ bản 1');
          expect(store.staging.existsSync(), isFalse);
          expect(store.fileFor('audio/words/dog.mp3'), isNotNull);
        }
        host.files.remove('pack/audio/words/cat.mp3');
        await expectLater(
          updater().update(host.url),
          throwsA(isA<PackUpdateException>()),
        );
        expect(store.readInstalled()!.version, 1);
      },
    );

    test('từ chối vocab.json không hợp lệ dù hash đúng', () async {
      host.publish(1, {
        'vocab.json': utf8.encode('{"categories":[],"words":[]}'),
      });
      await expectLater(
        updater().update(host.url),
        throwsA(isA<PackUpdateException>()),
      );
      expect(store.readInstalled(), isNull);
    });

    test('từ chối model không phải TFLite; nhận model hợp lệ', () async {
      final labels = utf8.encode('a\nb\n');
      host.publish(1, {
        'vocab.json': utf8.encode(_vocab(_fourWords())),
        'model.tflite': utf8.encode('không phải tflite'),
        'labels.txt': labels,
      });
      await expectLater(
        updater().update(host.url),
        throwsA(isA<PackUpdateException>()),
      );

      final fakeModel = [0, 0, 0, 0, ...'TFL3'.codeUnits, 1, 2, 3];
      host.publish(1, {
        'vocab.json': utf8.encode(_vocab(_fourWords())),
        'model.tflite': fakeModel,
        'labels.txt': labels,
      });
      final r = await updater().update(host.url);
      expect(r.manifest.hasModel, isTrue);
      expect(store.fileFor('model.tflite'), isNotNull);
    });

    test('chuẩn hoá địa chỉ và chặn http khi không cho phép', () {
      final strict = PackUpdater(store, allowInsecure: false);
      expect(
        strict.parseBase(' https://x.io/p/manifest.json ').toString(),
        'https://x.io/p/',
      );
      expect(strict.parseBase('https://x.io/p').toString(), 'https://x.io/p/');
      for (final bad in [
        '',
        'http://x.io/p/',
        'ftp://x.io',
        'x.io/p',
        'https://',
      ]) {
        expect(
          () => strict.parseBase(bad),
          throwsA(isA<PackUpdateException>()),
          reason: bad,
        );
      }
      expect(updater().parseBase('http://10.0.2.2:8000/').host, '10.0.2.2');
    });

    test(
      'máy chủ không tồn tại: báo lỗi tiếng Việt, không ném lỗi thô',
      () async {
        final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final url = 'http://127.0.0.1:${dead.port}/';
        await dead.close(force: true);
        await expectLater(
          updater().update(url),
          throwsA(
            isA<PackUpdateException>().having(
              (e) => e.message,
              'message',
              contains('kết nối'),
            ),
          ),
        );
      },
    );
  });
}

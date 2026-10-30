import 'dart:convert';

import 'package:english_cam/core/api_client.dart';
import 'package:english_cam/data/feedback/recognition_feedback.dart';
import 'package:english_cam/services/auth_service.dart';
import 'package:english_cam/services/feedback_service.dart';
import 'package:english_cam/services/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

RecognitionFeedback fb(
  String id, {
  String correct = 'cup',
  String? wordId = 'cup',
  FeedbackSource source = FeedbackSource.top3,
}) => RecognitionFeedback(
  id: id,
  predictedLabel: 'hat',
  predictedProbability: 0.81,
  top3: const [
    FeedbackCandidate('hat', 0.81),
    FeedbackCandidate('umbrella', 0.09),
    FeedbackCandidate('towel', 0.06),
  ],
  correctText: correct,
  correctWordId: wordId,
  source: source,
  modelSource: 'bundled',
  vocabVersion: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  late AuthService auth;
  late FeedbackService svc;
  var now = DateTime.utc(2026, 10, 30, 10);

  Future<void> signInParent() async {
    server.on('POST /api/auth/verify-otp', 200, authJson());
    await auth.verifyOtp('lan@test.com', '123456');
  }

  List<Map<String, dynamic>> sent() => [
    for (final c in server.to('POST /api/feedback/recognition'))
      server.bodyOf(c),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 30, 10);
    server = FakeServer()
      ..on('POST /api/feedback/recognition', 200, {
        'id': 'x',
        'updated': false,
      });
    auth = AuthService(
      api: ApiClient(
        baseUrl: 'https://api.test',
        transport: (r) => server.call(r),
      ),
      store: MemoryKeyValueStore(),
      google: FakeGoogle(),
      device: FakeDevice(),
    );
    svc = FeedbackService(auth: auth, autoFlush: false, clock: () => now);
  });

  test(
    'gửi đúng thân yêu cầu (chỉ chữ, đủ trường) bằng token của phụ huynh',
    () async {
      await signInParent();
      await svc.save(fb('id-1'));
      expect(await svc.flush(), isTrue);
      final c = server.to('POST /api/feedback/recognition').single;
      expect(c.headers['Authorization'], 'Bearer tok-parent');
      expect(server.bodyOf(c), {
        'id': 'id-1',
        'predictedLabel': 'hat',
        'predictedProbability': 0.81,
        'top3': [
          {'label': 'hat', 'probability': 0.81},
          {'label': 'umbrella', 'probability': 0.09},
          {'label': 'towel', 'probability': 0.06},
        ],
        'correctWordId': 'cup',
        'correctText': 'cup',
        'source': 'top3',
        'modelSource': 'bundled',
        'vocabVersion': 1,
      });
      expect(
        jsonEncode(server.bodyOf(c)).toLowerCase(),
        isNot(contains('image')),
        reason: 'không bao giờ gửi ảnh',
      );
      expect(svc.pending, 0);
    },
  );

  test('máy của bé dùng token của bé', () async {
    server
      ..on(
        'POST /api/auth/child-link',
        200,
        authJson(
          role: 'Child',
          token: 'tok-kid',
          userId: 'kid-1',
          name: 'Bi',
          email: '',
        ),
      )
      ..on('GET /api/child/me', 200, childJson());
    await auth.linkWithCode('12345678');
    await svc.save(fb('id-1'));
    await svc.flush();
    expect(
      server
          .to('POST /api/feedback/recognition')
          .single
          .headers['Authorization'],
      'Bearer tok-kid',
    );
  });

  test(
    'chưa đăng nhập: giữ trong hàng đợi, không gọi mạng; có phiên rồi thì gửi bù',
    () async {
      await svc.save(fb('id-1'));
      await svc.save(fb('id-2'));
      expect(await svc.flush(), isFalse);
      expect(svc.pending, 2);
      expect(server.to('POST /api/feedback/recognition'), isEmpty);

      await signInParent();
      expect(await svc.flush(), isTrue);
      expect(sent().map((b) => b['id']), [
        'id-1',
        'id-2',
      ], reason: 'cũ gửi trước');
    },
  );

  test('hàng đợi nhớ qua lần mở app sau (lưu bền)', () async {
    await svc.save(
      fb(
        'id-1',
        correct: 'cái bàn',
        wordId: null,
        source: FeedbackSource.typed,
      ),
    );
    final reopened = FeedbackService(
      auth: auth,
      autoFlush: false,
      clock: () => now,
    );
    await reopened.start();
    expect(reopened.pending, 1);
    await signInParent();
    await reopened.flush();
    expect(sent().single['correctText'], 'cái bàn');
    expect(sent().single['source'], 'typed');
    expect(sent().single['correctWordId'], isNull);
    reopened.stop();
  });

  test(
    'chọn lại trên cùng ảnh (cùng id) thì thay mục cũ, không thêm mục',
    () async {
      await svc.save(fb('id-1', correct: 'cup', wordId: 'cup'));
      await svc.save(fb('id-1', correct: 'umbrella', wordId: 'umbrella'));
      await svc.save(fb('id-2'));
      expect(svc.pending, 2);
      await signInParent();
      await svc.flush();
      expect(sent().map((b) => '${b['id']}:${b['correctWordId']}'), [
        'id-1:umbrella',
        'id-2:cup',
      ]);
    },
  );

  test(
    'máy chủ lỗi 5xx/429: giữ nguyên để gửi lại (thử từng mã một)',
    () async {
      await signInParent();
      var kept = 0;
      for (final status in [500, 503, 429]) {
        server.on('POST /api/feedback/recognition', status, {'message': 'x'});
        await svc.save(fb('id-$status'));
        expect(await svc.flush(), isFalse, reason: 'HTTP $status');
        expect(
          svc.pending,
          ++kept,
          reason: 'HTTP $status không được làm mất góp ý',
        );
      }
      server.on('POST /api/feedback/recognition', 200, {});
      expect(await svc.flush(), isTrue);
      expect(sent().skip(3).map((b) => b['id']).toList(), [
        'id-500',
        'id-503',
        'id-429',
      ]);
    },
  );

  test(
    'hết phiên (401): giữ góp ý, app đã đăng xuất; đăng nhập lại thì gửi bù',
    () async {
      await signInParent();
      server.on('POST /api/feedback/recognition', 401, {'message': 'hết hạn'});
      await svc.save(fb('id-1'));
      expect(await svc.flush(), isFalse);
      expect(svc.pending, 1);
      expect(
        auth.isGuest,
        isTrue,
        reason: 'ApiClient xoá phiên khi token bị từ chối',
      );

      server.on('POST /api/feedback/recognition', 200, {});
      await signInParent();
      expect(await svc.flush(), isTrue);
      expect(sent().last['id'], 'id-1');
    },
  );

  test('mất mạng rồi có lại: gửi đủ, đúng thứ tự', () async {
    await signInParent();
    server.handle(
      'POST /api/feedback/recognition',
      (_) => throw const ApiException('mất mạng'),
    );
    await svc.save(fb('id-1'));
    await svc.save(fb('id-2'));
    expect(await svc.flush(), isFalse);
    expect(svc.pending, 2);
    server.on('POST /api/feedback/recognition', 200, {
      'id': 'x',
      'updated': false,
    });
    expect(await svc.flush(), isTrue);
    // lần gửi đầu (id-1) bị mất mạng nên có ghi nhận nhưng chưa tới nơi; sau đó gửi lại đủ và đúng thứ tự
    expect(sent().skip(1).map((b) => b['id']), ['id-1', 'id-2']);
    expect(svc.pending, 0);
  });

  test(
    'máy chủ từ chối vì dữ liệu (400/409): bỏ mục đó, không kẹt các mục sau',
    () async {
      await signInParent();
      var n = 0;
      server.handle(
        'POST /api/feedback/recognition',
        (_) => ++n == 1
            ? FakeServer.json(400, {
                'errors': ['sai'],
              })
            : FakeServer.json(200, {}),
      );
      await svc.save(fb('bad'));
      await svc.save(fb('good'));
      expect(await svc.flush(), isTrue);
      expect(sent().map((b) => b['id']), ['bad', 'good']);
      expect(svc.pending, 0);
    },
  );

  test(
    'mục cũ quá 7 ngày bị bỏ; hàng đợi giữ tối đa 100 mục (bỏ mục cũ nhất)',
    () async {
      await svc.save(fb('old'));
      now = now.add(const Duration(days: 8));
      await signInParent();
      await svc.flush();
      expect(
        server.to('POST /api/feedback/recognition'),
        isEmpty,
        reason: 'quá hạn: không gửi',
      );
      expect(svc.pending, 0);

      for (var i = 0; i < 105; i++) {
        await svc.save(fb('id-$i'));
      }
      expect(svc.pending, 100);
      await svc.flush();
      expect(sent().first['id'], 'id-5');
      expect(sent().last['id'], 'id-104');
    },
  );

  test(
    'người dùng đổi đáp án đúng lúc đang gửi: bản mới không bị xoá nhầm và được gửi tiếp',
    () async {
      await signInParent();
      await svc.save(fb('id-1', correct: 'cup', wordId: 'cup'));
      var swapped = false;
      server.handle('POST /api/feedback/recognition', (_) {
        if (!swapped) {
          // đang "gửi" bản cũ thì người dùng chọn lại (chỉ một lần)
          swapped = true;
          svc.save(fb('id-1', correct: 'umbrella', wordId: 'umbrella'));
        }
        return FakeServer.json(200, {});
      });
      await svc.flush();
      // Bản mới chọn trong lúc gửi cũng được gửi ngay trong cùng lượt (không bị xoá nhầm, không phải chờ).
      expect(svc.pending, 0);
      final calls = server.to('POST /api/feedback/recognition');
      expect(calls.length, 2);
      expect(server.bodyOf(calls.first)['correctWordId'], 'cup');
      expect(server.bodyOf(calls.last)['correctWordId'], 'umbrella');
    },
  );
}

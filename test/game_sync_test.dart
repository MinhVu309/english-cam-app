import 'dart:math';

import 'package:english_cam/core/api_client.dart';
import 'package:english_cam/core/theme.dart';
import 'package:english_cam/data/account/account_models.dart';
import 'package:english_cam/data/game_badge.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/features/game/hunt/hunt_game_screen.dart';
import 'package:english_cam/features/game/match/match_questions.dart';
import 'package:english_cam/features/game/match/matching_game_screen.dart';
import 'package:english_cam/features/settings/settings_screen.dart';
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
import 'sync_service_test.dart' show sessionResult, snapshot;

/// Game và Cài đặt khi bé đã đăng nhập: câu hỏi từ máy chủ, dự phòng khi lỗi, ghi nhận ván vào hàng đợi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  late AuthService auth;
  late SyncService sync;
  late VocabRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    await AppSettings.instance.init();
    AudioService.instance.disabled = true;
    repo = await VocabRepository.load();
    await BadgeRepository.load();
    GameProgress.instance.resetForTest();
    await GameProgress.instance.init();
    await ProgressService.instance.useProfile(null);

    server = FakeServer()
      ..on('GET /api/progress/me', 200, snapshot())
      ..on('GET /api/games/badges', 200, <Object>[])
      ..on('POST /api/auth/logout', 204)
      ..on('GET /api/child/me', 200, childJson())
      ..on('POST /api/auth/child-link', 200, authJson(role: 'Child', userId: 'kid-1', token: 'tok-kid', name: 'Bi', email: ''));
    auth = AuthService(
      api: ApiClient(baseUrl: 'https://api.test', transport: server.call),
      store: MemoryKeyValueStore(),
      google: FakeGoogle(),
      device: FakeDevice(),
    );
    AuthService.instance = auth;
    sync = SyncService(auth: auth, autoFlush: false);
    SyncService.instance = sync;
    await sync.attach();
  });

  tearDown(() async {
    sync.detach();
    ProgressService.instance.onLearnedChanged = null;
    AuthService.instance = AuthService();
    SyncService.instance = SyncService();
    GameProgress.instance.resetForTest();
    await ProgressService.instance.useProfile(null);
  });

  Future<void> enterChildMode(WidgetTester tester) async {
    await tester.runAsync(() async {
      await auth.linkWithCode('12345678');
      await sync.settled;
    });
  }

  Future<void> pumpGame(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: screen));
  }

  /// 8 câu hỏi máy chủ chọn: từ có hình, đáp án đúng nằm ở vị trí khác nhau.
  List<Map<String, dynamic>> serverQuestions() {
    final pool = matchPool(repo.words);
    return [
      for (var i = 0; i < 8; i++)
        {
          'wordId': pool[i].id,
          'optionIds': [
            for (var k = 0; k < 4; k++) k == i % 4 ? pool[i].id : pool[(i + 10 + k) % pool.length].id,
          ],
        },
    ];
  }

  Finder option(String id) => find.byKey(ValueKey('option-$id'));

  Set<String> shownOptions() => {
    for (final w in repo.words)
      if (option(w.id).evaluate().isNotEmpty) w.id,
  };

  group('Nghe & chọn hình', () {
    testWidgets('khách: câu hỏi hiện ngay, không gọi máy chủ', (tester) async {
      await pumpGame(tester, MatchingGameScreen(random: Random(1)));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(shownOptions(), hasLength(4));
      expect(server.calls, isEmpty);
    });

    testWidgets('bé đã đăng nhập: dùng câu hỏi của máy chủ rồi đưa ván vào hàng đợi với số lần chọn từng câu', (tester) async {
      await enterChildMode(tester);
      final qs = serverQuestions();
      server.on('GET /api/games/match/questions', 200, {'vocabVersion': 1, 'questions': qs});
      await pumpGame(tester, MatchingGameScreen(random: Random(1)));
      await tester.pump(); // chờ máy chủ trả lời
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(shownOptions(), (qs.first['optionIds'] as List).cast<String>().toSet(), reason: 'đúng bộ đáp án máy chủ chọn');
      expect(find.text('1/8'), findsOneWidget);

      for (var i = 0; i < 8; i++) {
        final target = qs[i]['wordId'] as String;
        if (i == 2) {
          // câu 3: chọn sai một lần trước
          final wrong = (qs[i]['optionIds'] as List).cast<String>().firstWhere((id) => id != target);
          await tester.tap(option(wrong));
          await tester.pump();
        }
        await tester.tap(option(target));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1400));
        await tester.pump();
      }
      await tester.pump();

      expect(find.text('⭐ 7 / 8'), findsOneWidget);
      expect(sync.pendingCount, 1);
      server.on('POST /api/games/sessions', 200, sessionResult(snapshot(stars: 7, rounds: 1)));
      await tester.runAsync(sync.flush);
      final body = server.bodyOf(server.to('POST /api/games/sessions').single);
      expect(body['gameType'], 'match');
      final answers = (body['answers'] as List).cast<Map<String, dynamic>>();
      expect(answers.map((a) => a['wordId']), [for (final q in qs) q['wordId']]);
      expect(answers.map((a) => a['attempts']), [1, 1, 2, 1, 1, 1, 1, 1]);
      expect(GameProgress.instance.stars, 7);
    });

    testWidgets('máy chủ lỗi: tự tạo câu hỏi trên máy, bé vẫn chơi được', (tester) async {
      await enterChildMode(tester);
      server.on('GET /api/games/match/questions', 500);
      await pumpGame(tester, MatchingGameScreen(random: Random(1)));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(shownOptions(), hasLength(4));
    });

    testWidgets('máy chủ gợi ý từ mà máy chưa có (từ vựng cũ hơn): bỏ cả bộ, dùng câu hỏi cục bộ', (tester) async {
      await enterChildMode(tester);
      final qs = serverQuestions();
      (qs[4]['optionIds'] as List)[0] = 'tu_chua_co_tren_may';
      qs[4]['wordId'] = 'tu_chua_co_tren_may';
      server.on('GET /api/games/match/questions', 200, {'vocabVersion': 9, 'questions': qs});
      await pumpGame(tester, MatchingGameScreen(random: Random(1)));
      await tester.pump();
      await tester.pump();
      expect(shownOptions(), isNot((qs.first['optionIds'] as List).cast<String>().toSet()));
      expect(shownOptions(), hasLength(4));
    });

    testWidgets('máy chủ chậm hơn 3 giây: không bắt bé chờ, dùng câu hỏi cục bộ', (tester) async {
      // Máy chủ miễn phí "ngủ": trả lời câu hỏi sau 10 giây, các yêu cầu khác nhanh.
      // Dựng trong runAsync (vùng thời gian thật) để hàng đợi nội bộ của SyncService chạy được.
      late SyncService slowSync;
      await tester.runAsync(() async {
        final slowAuth = AuthService(
          api: ApiClient(
            baseUrl: 'https://api.test',
            transport: (r) => r.url.path == '/api/games/match/questions'
                ? Future<HttpResponseData>.delayed(const Duration(seconds: 10), () => FakeServer.json(200, {'questions': <Object>[]}))
                : server.call(r),
          ),
          store: MemoryKeyValueStore(),
          google: FakeGoogle(),
          device: FakeDevice(),
        );
        AuthService.instance = slowAuth;
        slowSync = SyncService(auth: slowAuth, autoFlush: false);
        SyncService.instance = slowSync;
        await slowSync.attach();
        await slowAuth.linkWithCode('12345678');
        await slowSync.settled;
      });
      addTearDown(slowSync.detach);

      await pumpGame(tester, MatchingGameScreen(random: Random(1)));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'đang chờ tối đa 3 giây');
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(shownOptions(), hasLength(4));
      await tester.pump(const Duration(seconds: 10)); // xả timer của yêu cầu chậm
    });
  });

  group('Tìm vật', () {
    testWidgets('khách: chọn vật ngẫu nhiên như cũ, không bao giờ apple/table', (tester) async {
      await pumpGame(tester, HuntGameScreen(random: Random(2)));
      expect(find.textContaining('apple'), findsNothing);
      expect(server.calls, isEmpty);
    });

    testWidgets('bé đã đăng nhập: vật cần tìm theo gợi ý của máy chủ (chỉ vật được phép)', (tester) async {
      await enterChildMode(tester);
      server.on('GET /api/games/hunt/targets', 200, {'vocabVersion': 1, 'wordIds': ['apple', 'pen']});
      sync.huntHints = ['apple', 'pen']; // apple không được phép làm đích → bỏ qua, lấy pen
      await pumpGame(tester, HuntGameScreen(random: Random(2)));
      await tester.pump();
      expect(find.text(repo.byId('pen')!.en), findsOneWidget);
      expect(find.text(repo.byId('pen')!.vi), findsOneWidget);
    });
  });

  group('Cài đặt: xoá tiến độ', () {
    Future<void> openReset(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const SettingsScreen()));
      await tester.tap(find.text('Xoá tiến độ của bé'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá hết'));
      await tester.pumpAndSettle();
    }

    testWidgets('khách: xoá tại máy như cũ', (tester) async {
      await tester.runAsync(() async {
        await GameProgress.instance.recordRound(starsEarned: 5, perfect: false);
        await ProgressService.instance.setLearned('cup', true);
      });
      await openReset(tester);
      expect((GameProgress.instance.stars, ProgressService.instance.learnedCount), (0, 0));
      expect(find.text('Đã xoá tiến độ của bé.'), findsOneWidget);
    });

    testWidgets('máy của bé không có tài khoản bố mẹ: không xoá, nhắc đăng nhập bố mẹ', (tester) async {
      server.on('GET /api/progress/me', 200, snapshot(stars: 9));
      await enterChildMode(tester);
      expect(GameProgress.instance.stars, 9);
      await openReset(tester);
      expect(find.textContaining('tài khoản của bố mẹ'), findsOneWidget);
      expect(GameProgress.instance.stars, 9);
      expect(server.to('DELETE /api/children/c1/progress'), isEmpty);
    });

    testWidgets('bố mẹ đã đăng nhập: xoá trên máy chủ rồi tải trạng thái trống về', (tester) async {
      server
        ..on('POST /api/auth/verify-otp', 200, authJson())
        ..on('POST /api/children/c1/session', 200, authJson(role: 'Child', userId: 'kid-1', token: 'tok-kid', name: 'Bi', email: ''))
        ..on('GET /api/progress/me', 200, snapshot(stars: 9, learned: ['cup']))
        ..on('DELETE /api/children/c1/progress', 204);
      await tester.runAsync(() async {
        await auth.verifyOtp('lan@test.com', '123456');
        await auth.startChildSession(ChildProfile.fromJson(childJson()));
        await sync.settled;
      });
      expect(GameProgress.instance.stars, 9);
      server.on('GET /api/progress/me', 200, snapshot());
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const SettingsScreen()));
      await tester.tap(find.text('Xoá tiến độ của bé'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Xoá hết'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(server.to('DELETE /api/children/c1/progress').single.headers['Authorization'], 'Bearer tok-parent');
      expect(GameProgress.instance.stars, 0);
      expect(ProgressService.instance.learnedCount, 0);
    });
  });

  group('Home theo hồ sơ bé', () {
    testWidgets('sao và số từ trên Home là của bé đang dùng máy, thoát ra thì về của khách', (tester) async {
      await tester.runAsync(() async {
        await GameProgress.instance.recordRound(starsEarned: 3, perfect: false);
      });
      await tester.pumpWidget(const EnglishCamApp());
      expect(find.text('3 sao'), findsOneWidget);

      server.on('GET /api/progress/me', 200, snapshot(stars: 21, learned: ['cup', 'bowl']));
      await enterChildMode(tester);
      await tester.pump();
      expect(find.text('21 sao'), findsOneWidget);
      expect(find.text('Bi'), findsOneWidget);

      await tester.runAsync(() async {
        await auth.leaveChildMode();
        await sync.settled;
      });
      await tester.pump();
      expect(find.text('3 sao'), findsOneWidget);
    });
  });
}

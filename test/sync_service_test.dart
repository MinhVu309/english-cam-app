import 'dart:async';
import 'dart:convert';

import 'package:english_cam/core/api_client.dart';
import 'package:english_cam/data/game_badge.dart';
import 'package:english_cam/services/auth_service.dart';
import 'package:english_cam/services/game_progress.dart';
import 'package:english_cam/services/key_value_store.dart';
import 'package:english_cam/services/progress_service.dart';
import 'package:english_cam/services/sync_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

/// Trạng thái học mà máy chủ trả về (`ProgressSnapshotDto`).
Map<String, dynamic> snapshot({
  int stars = 0,
  int rounds = 0,
  int perfect = 0,
  int found = 0,
  int best = 0,
  List<String> learned = const [],
  List<String> badges = const [],
  int? limitMinutes,
  int todaySeconds = 0,
}) => {
  'stars': stars,
  'rounds': rounds,
  'perfectRounds': perfect,
  'found': found,
  'currentStreak': best,
  'bestStreak': best,
  'learnedWordIds': learned,
  'badgeIds': badges,
  'dailyWordGoal': 5,
  'dailyLimitMinutes': limitMinutes,
  'today': {'seconds': todaySeconds, 'wordsLearned': 0, 'rounds': 0, 'scans': 0},
  'serverTime': DateTime.now().toUtc().toIso8601String(),
};

Map<String, dynamic> sessionResult(Map<String, dynamic> progress, {int stars = 0}) => {
  'starsEarned': stars,
  'duplicate': false,
  'newBadges': <Object>[],
  'progress': progress,
};

Map<String, dynamic> eventResult(Map<String, dynamic> progress, {int applied = 1}) => {
  'applied': applied,
  'duplicates': 0,
  'ignored': 0,
  'newBadges': <Object>[],
  'progress': progress,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  late AuthService auth;
  late SyncService sync;
  late Transport transport;
  var now = DateTime.utc(2026, 10, 30, 10);

  final progress = ProgressService.instance;
  final game = GameProgress.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 30, 10);
    await BadgeRepository.load();
    game.resetForTest();
    await game.init();
    await progress.useProfile(null);
    server = FakeServer()
      ..on('GET /api/progress/me', 200, snapshot())
      ..on('GET /api/games/badges', 200, <Object>[])
      ..on('POST /api/auth/logout', 204)
      ..on('GET /api/child/me', 200, childJson());
    transport = server.call;
    auth = AuthService(
      api: ApiClient(baseUrl: 'https://api.test', transport: (r) => transport(r)),
      store: MemoryKeyValueStore(),
      google: FakeGoogle(),
      device: FakeDevice(),
    );
    sync = SyncService(auth: auth, autoFlush: false, clock: () => now);
    await sync.attach();
  });

  tearDown(() async {
    sync.detach();
    progress.onLearnedChanged = null;
    game.resetForTest();
    await progress.useProfile(null);
  });

  Future<void> linkChild({String userId = 'kid-1', String name = 'Bi'}) async {
    server.on('POST /api/auth/child-link', 200, authJson(role: 'Child', userId: userId, token: 'tok-$userId', name: name, email: ''));
    await auth.linkWithCode('12345678');
    await sync.settled;
  }

  Future<void> leave() async {
    await auth.leaveChildMode();
    await sync.settled;
  }

  List<Map<String, dynamic>> eventsSent() => [
    for (final c in server.to('POST /api/progress/events')) ...(server.bodyOf(c)['events'] as List<dynamic>).cast<Map<String, dynamic>>(),
  ];

  group('Chế độ khách', () {
    test('không ghi nhận, không gọi máy chủ', () async {
      await progress.setLearned('cup', true);
      sync.recordScan('cup');
      sync.recordHuntFound(wordId: 'cup', byParent: false, stars: 2);
      sync.recordMatchRound(startedAt: now, durationSec: 5, answers: const [MatchAnswer('cup', 1)], stars: 1, perfect: false);
      await sync.flush();
      expect(sync.active, isFalse);
      expect(sync.pendingCount, 0);
      expect(server.calls, isEmpty);
      expect(progress.isLearned('cup'), isTrue, reason: 'khách vẫn lưu cục bộ như cũ');
      expect(await sync.fetchMatchQuestions(8), isNull);
    });
  });

  group('Mỗi hồ sơ một ngăn lưu', () {
    test('vào chế độ bé: số liệu của bé tách khỏi khách và được khôi phục khi thoát', () async {
      await game.recordRound(starsEarned: 5, perfect: false);
      await progress.setLearned('pen', true);
      expect((game.stars, progress.learnedCount), (5, 1));

      server.on('GET /api/progress/me', 200, snapshot(stars: 12, rounds: 2, learned: ['cup', 'bowl'], badges: ['first_round']));
      await linkChild();
      expect(sync.active, isTrue);
      expect(game.stars, 12, reason: 'lấy từ máy chủ, không lẫn sao của khách');
      expect(progress.learnedCount, 2);
      expect(progress.isLearned('pen'), isFalse);
      expect(game.hasBadge('first_round'), isTrue);

      await leave();
      expect(sync.active, isFalse);
      expect((game.stars, progress.learnedCount), (5, 1));
      expect(progress.isLearned('pen'), isTrue);
    });

    test('hai bé dùng chung một máy không lẫn tiến độ; quay lại bé cũ vẫn còn nguyên', () async {
      server.on('GET /api/progress/me', 200, snapshot(stars: 7));
      await linkChild(userId: 'kid-a', name: 'A');
      await game.recordRound(starsEarned: 3, perfect: false);
      sync.recordMatchRound(startedAt: now, durationSec: 5, answers: const [MatchAnswer('cup', 1)], stars: 3, perfect: false);
      expect(game.stars, 10);
      await leave();

      server.on('GET /api/progress/me', 200, snapshot(stars: 1));
      await linkChild(userId: 'kid-b', name: 'B');
      expect(game.stars, 1);
      expect(sync.pendingCount, 0, reason: 'hàng đợi của A không rò sang B');
      await leave();

      server
        ..on('GET /api/progress/me', 500)
        ..on('POST /api/games/sessions', 500);
      await linkChild(userId: 'kid-a', name: 'A'); // máy chủ lỗi: dùng số đã lưu trên máy
      expect(game.stars, 10);
      expect(sync.pendingCount, 1, reason: 'ván chưa gửi của A vẫn còn trong hàng đợi');
    });
  });

  group('Hàng đợi và gửi', () {
    test('đánh dấu đã học → sự kiện có id/giờ → gửi xong thì hàng đợi trống và số liệu theo máy chủ', () async {
      await linkChild();
      await progress.setLearned('cup', true);
      await progress.setLearned('bowl', true);
      await progress.setLearned('cup', false);
      expect(sync.pendingCount, 3);
      server.on('POST /api/progress/events', 200, eventResult(snapshot(learned: ['bowl', 'zebra'])));

      expect(await sync.flush(), isTrue);

      final sent = eventsSent();
      expect(sent.map((e) => (e['type'], e['wordId'], e['learned'])), [('learned', 'cup', true), ('learned', 'bowl', true), ('learned', 'cup', false)]);
      expect(sent.map((e) => e['id']).toSet(), hasLength(3), reason: 'mỗi sự kiện một id riêng');
      expect(sent.first['id'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(sent.first['at'], now.toIso8601String());
      expect(sync.pendingCount, 0);
      expect(progress.learned, {'bowl', 'zebra'}, reason: 'tập từ đã học = của máy chủ (có cả từ học trên máy khác)');
    });

    test('ván chơi được gửi trước sự kiện; thân yêu cầu không mang số sao do máy tự tính', () async {
      await linkChild();
      await progress.setLearned('cup', true);
      sync.recordMatchRound(
        startedAt: now,
        durationSec: 42,
        answers: const [MatchAnswer('cup', 1), MatchAnswer('bowl', 3)],
        stars: 1,
        perfect: false,
      );
      sync.recordHuntFound(wordId: 'pen', byParent: true, stars: 1);
      final order = <String>[];
      server
        ..handle('POST /api/games/sessions', (r) {
          order.add('session:${server.bodyOf(r)['gameType']}');
          return FakeServer.json(200, sessionResult(snapshot(stars: 2, rounds: 1, found: 1)));
        })
        ..handle('POST /api/progress/events', (r) {
          order.add('events');
          return FakeServer.json(200, eventResult(snapshot(stars: 2, rounds: 1, found: 1, learned: ['cup'])));
        });

      await sync.flush();

      expect(order, ['session:match', 'session:hunt', 'events']);
      final match = server.bodyOf(server.to('POST /api/games/sessions').first);
      expect(match.keys.toSet(), {'id', 'gameType', 'startedAt', 'durationSec', 'answers'});
      expect(match['durationSec'], 42);
      expect(match['answers'], [
        {'wordId': 'cup', 'correct': true, 'attempts': 1},
        {'wordId': 'bowl', 'correct': true, 'attempts': 3},
      ]);
      final hunt = server.bodyOf(server.to('POST /api/games/sessions').last);
      expect(hunt['answers'], [
        {'wordId': 'pen', 'correct': true, 'attempts': 1, 'via': 'parent'},
      ]);
      expect(sync.pendingCount, 0);
    });

    test('mất mạng: giữ nguyên hàng đợi, số liệu trên máy không lùi; có mạng lại thì gửi đúng các id cũ', () async {
      server.on('GET /api/progress/me', 200, snapshot(stars: 10));
      await linkChild();
      await game.recordRound(starsEarned: 3, perfect: false);
      sync.recordMatchRound(startedAt: now, durationSec: 5, answers: const [MatchAnswer('cup', 1)], stars: 3, perfect: false);
      await progress.setLearned('cup', true);
      expect(game.stars, 13);

      transport = (_) async => throw const ApiException('mất mạng');
      expect(await sync.flush(), isFalse);
      expect(sync.pendingCount, 2);
      expect(game.stars, 13);

      // Khởi động lại app (bộ nhớ mất, prefs còn): hàng đợi được nạp lại từ máy.
      sync.detach();
      sync = SyncService(auth: auth, autoFlush: false, clock: () => now);
      await sync.attach();
      await sync.settled; // lần đồng bộ lúc mở app cũng thất bại vì vẫn mất mạng
      expect(sync.pendingCount, 2);
      transport = server.call;
      final ids = <String>[];
      server
        ..handle('POST /api/games/sessions', (r) {
          ids.add(server.bodyOf(r)['id'] as String);
          return FakeServer.json(200, sessionResult(snapshot(stars: 13, rounds: 1)));
        })
        ..handle('POST /api/progress/events', (r) {
          ids.addAll([for (final e in server.bodyOf(r)['events'] as List<dynamic>) (e as Map<String, dynamic>)['id'] as String]);
          return FakeServer.json(200, eventResult(snapshot(stars: 13, rounds: 1, learned: ['cup'])));
        });
      expect(await sync.flush(), isTrue);
      expect(ids, hasLength(2));
      expect(sync.pendingCount, 0);
      expect((game.stars, game.rounds), (13, 1));
    });

    test('máy chủ lỗi 500 hoặc 429 thì giữ lại; lỗi dữ liệu 400 thì bỏ để không kẹt hàng đợi', () async {
      await linkChild();
      sync.recordHuntFound(wordId: 'pen', byParent: false, stars: 2);
      sync.recordHuntFound(wordId: 'cup', byParent: false, stars: 2);

      server.on('POST /api/games/sessions', 500);
      expect(await sync.flush(), isFalse);
      expect(sync.pendingCount, 2);
      server.on('POST /api/games/sessions', 429, {'message': 'nghỉ chút nhé'});
      expect(await sync.flush(), isFalse);
      expect(sync.pendingCount, 2);

      var n = 0;
      server.handle('POST /api/games/sessions', (_) => ++n == 1 ? FakeServer.json(400, {'errors': ['sai']}) : FakeServer.json(200, sessionResult(snapshot(stars: 2, found: 1))));
      expect(await sync.flush(), isTrue);
      expect(n, 2, reason: 'ván hỏng bị bỏ, ván sau vẫn được gửi');
      expect(sync.pendingCount, 0);
    });

    test('lô sự kiện tối đa 100 mỗi lần', () async {
      await linkChild();
      for (var i = 0; i < 250; i++) {
        sync.recordScan('cup');
      }
      server.on('POST /api/progress/events', 200, eventResult(snapshot()));
      await sync.flush();
      final sizes = [for (final c in server.to('POST /api/progress/events')) (server.bodyOf(c)['events'] as List).length];
      expect(sizes, [100, 100, 50]);
      expect(sync.pendingCount, 0);
    });

    test('hàng đợi quá đầy thì bỏ sự kiện cũ nhưng giữ các ván (mang sao của bé)', () async {
      await linkChild();
      sync.recordHuntFound(wordId: 'cup', byParent: false, stars: 2);
      for (var i = 0; i < 2100; i++) {
        sync.recordScan('cup');
      }
      expect(sync.pendingCount, 2000);
      server.on('POST /api/games/sessions', 200, sessionResult(snapshot(stars: 2, found: 1)));
      server.on('POST /api/progress/events', 200, eventResult(snapshot(stars: 2, found: 1)));
      await sync.flush();
      expect(server.to('POST /api/games/sessions'), hasLength(1), reason: 'ván vẫn còn');
    });
  });

  group('Gộp với máy chủ', () {
    test('sao của máy khác được cộng vào, phần chưa gửi của máy này vẫn giữ', () async {
      server.on('GET /api/progress/me', 200, snapshot(stars: 10, rounds: 2, found: 1));
      await linkChild();
      expect(game.stars, 10);
      await game.recordRound(starsEarned: 4, perfect: true);
      sync.recordMatchRound(startedAt: now, durationSec: 5, answers: const [MatchAnswer('cup', 1)], stars: 4, perfect: true);
      server.on('GET /api/progress/me', 200, snapshot(stars: 15, rounds: 3, perfect: 1, found: 1)); // máy kia vừa chơi thêm
      expect(await sync.hydrate(), isTrue);
      expect((game.stars, game.rounds, game.perfectRounds, game.found), (19, 4, 2, 1));
    });

    test('từ đã học: máy chủ + bật/tắt chưa gửi của máy này', () async {
      server.on('GET /api/progress/me', 200, snapshot(learned: ['a', 'b']));
      await linkChild();
      expect(progress.learned, {'a', 'b'});
      await progress.setLearned('a', false);
      await progress.setLearned('c', true);
      await sync.hydrate();
      expect(progress.learned, {'b', 'c'});
    });

    test('máy chủ báo huy hiệu; xoá tiến độ từ xa thì huy hiệu và số liệu về 0', () async {
      server.on('GET /api/progress/me', 200, snapshot(stars: 12, rounds: 1, badges: ['first_round', 'stars_10']));
      await linkChild();
      expect(game.badges, {'first_round', 'stars_10'});
      server.on('GET /api/progress/me', 200, snapshot());
      await sync.discardPendingAndHydrate();
      expect(game.stars, 0);
      expect(game.rounds, 0);
      expect(game.badges, isEmpty);
    });

    test('huy hiệu đạt nhờ phần chưa gửi vẫn được giữ khi máy chủ chưa biết', () async {
      await linkChild();
      await game.recordRound(starsEarned: 1, perfect: false);
      sync.recordMatchRound(startedAt: now, durationSec: 5, answers: const [MatchAnswer('cup', 1)], stars: 1, perfect: false);
      await sync.hydrate(); // máy chủ chưa nhận ván này → badgeIds rỗng
      expect(game.hasBadge('first_round'), isTrue);
    });

    test('danh sách huy hiệu máy chủ thay bản đóng gói và được nhớ cho lần mở sau', () async {
      server.on('GET /api/games/badges', 200, [
        {'id': 'streak_3', 'name': 'Chăm chỉ', 'description': '3 ngày liền', 'emoji': '🔥', 'metric': 'streak', 'threshold': 3, 'unlocked': false, 'unlockedAt': null},
        {'id': 'first_round', 'name': 'Bé tập chơi', 'description': '1 ván', 'emoji': '🎮', 'metric': 'rounds', 'threshold': 1, 'unlocked': true, 'unlockedAt': null},
      ]);
      server.on('GET /api/progress/me', 200, snapshot(rounds: 1, best: 3, badges: ['first_round', 'streak_3']));
      await linkChild();
      expect(BadgeRepository.instance.badges.map((b) => b.id), ['streak_3', 'first_round']);
      expect(game.streakBest, 3);
      expect(game.hasBadge('streak_3'), isTrue);

      final reloaded = await BadgeRepository.load(); // "mở app lại"
      expect(reloaded.badges.map((b) => b.id), ['streak_3', 'first_round']);
    });
  });

  group('Chọn hồ sơ giữa lúc đang gửi', () {
    test('trạng thái của bé cũ không được áp lên bé mới', () async {
      server.on('GET /api/progress/me', 200, snapshot());
      await linkChild(userId: 'kid-a', name: 'A');
      await progress.setLearned('cup', true);
      final hold = Completer<HttpResponseData>();
      transport = (r) => r.url.path == '/api/progress/events' ? hold.future : server.call(r);

      final inFlight = sync.flush();
      await Future<void>.delayed(Duration.zero);
      await leave();
      await linkChild(userId: 'kid-b', name: 'B');
      hold.complete(FakeServer.json(200, eventResult(snapshot(stars: 99, learned: ['zebra']))));
      await inFlight;

      expect(game.stars, 0, reason: 'sao 99 của bé A không được rò sang B');
      expect(progress.learned, isEmpty);
    });
  });

  group('Câu hỏi từ máy chủ', () {
    test('đọc câu hỏi và gợi ý vật cần tìm', () async {
      await linkChild();
      server
        ..on('GET /api/games/match/questions', 200, {
          'vocabVersion': 3,
          'questions': [
            {'wordId': 'cup', 'optionIds': ['bowl', 'cup', 'pen', 'bag']},
          ],
        })
        ..on('GET /api/games/hunt/targets', 200, {'vocabVersion': 3, 'wordIds': ['pen', 'cup']});
      final qs = (await sync.fetchMatchQuestions(8))!;
      expect(qs.single.target, 'cup');
      expect(qs.single.options, ['bowl', 'cup', 'pen', 'bag']);
      expect(server.to('GET /api/games/match/questions').single.url.query, 'count=8');
      expect(server.to('GET /api/games/match/questions').single.headers['Authorization'], 'Bearer tok-kid-1');

      await sync.fetchHuntTargets(10);
      expect(sync.huntHints, ['pen', 'cup']);
    });

    test('lỗi hoặc quá chậm → null để game tự tạo câu hỏi', () async {
      await linkChild();
      server.on('GET /api/games/match/questions', 500);
      expect(await sync.fetchMatchQuestions(8), isNull);
      server.on('GET /api/games/match/questions', 200, {'questions': 'hỏng'});
      expect(await sync.fetchMatchQuestions(8), isNull);

      final never = Completer<HttpResponseData>();
      transport = (r) => r.url.path == '/api/games/match/questions' ? never.future : server.call(r);
      final slow = await sync.fetchMatchQuestions(8, timeout: const Duration(milliseconds: 30));
      expect(slow, isNull);
    });
  });

  group('Thời gian dùng app', () {
    test('ghi số giây ở chế độ bé khi rời app; dưới 2 giây thì bỏ; tối đa 1 giờ mỗi sự kiện', () async {
      await linkChild();
      server.on('POST /api/progress/events', 200, eventResult(snapshot()));
      List<Object?> seconds() => eventsSent().where((e) => e['type'] == 'screenTime').map((e) => e['seconds']).toList();
      Future<void> background(Duration after) async {
        sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
        now = now.add(after);
        sync.didChangeAppLifecycleState(AppLifecycleState.paused); // ghi thời gian rồi gửi ngay
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      await background(const Duration(seconds: 90));
      expect(seconds(), [90]);
      await background(const Duration(seconds: 1));
      expect(seconds(), [90], reason: 'dưới 2 giây thì bỏ');
      await background(const Duration(hours: 5));
      expect(seconds(), [90, 3600], reason: 'một sự kiện tối đa 1 giờ');
    });

    test('hộp thoại hệ thống (inactive) không bị tính là rời app', () async {
      await linkChild();
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      now = now.add(const Duration(minutes: 2));
      sync.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(sync.pendingCount, 0);
    });
  });

  group('Giới hạn thời gian chơi', () {
    Future<void> background(Duration after) async {
      now = now.add(after);
      sync.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test('lấy giới hạn và số giây hôm nay từ máy chủ; chưa chạm thì chưa khoá', () async {
      server.on('GET /api/progress/me', 200, snapshot(limitMinutes: 30, todaySeconds: 1700));
      await linkChild();
      expect(sync.limit.limitMinutes, 30);
      expect(sync.limit.recordedSeconds, 1700);
      expect(sync.limit.locked, isFalse);
      expect(sync.limit.remainingSeconds, 100);
    });

    test('đang mở app mà chạm giới hạn thì khoá và ghi nốt thời gian đã dùng', () async {
      server.on('GET /api/progress/me', 200, snapshot(limitMinutes: 30, todaySeconds: 1700));
      server.on('POST /api/progress/events', 200, eventResult(snapshot(limitMinutes: 30, todaySeconds: 1810)));
      await linkChild();
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      now = now.add(const Duration(seconds: 60));
      sync.checkLimit();
      expect(sync.limit.locked, isFalse, reason: 'mới dùng 1760/1800 giây');
      now = now.add(const Duration(seconds: 50));
      sync.checkLimit();
      expect(sync.limit.locked, isTrue);
      await sync.flush();
      final times = eventsSent().where((e) => e['type'] == 'screenTime').map((e) => e['seconds']).toList();
      expect(times, [110], reason: 'đủ 110 giây đã dùng, không thiếu không thừa');
    });

    test('đang khoá thì không đếm thêm thời gian (máy nằm yên ở màn hình khoá)', () async {
      server.on('GET /api/progress/me', 200, snapshot(limitMinutes: 30, todaySeconds: 1799));
      server.on('POST /api/progress/events', 200, eventResult(snapshot(limitMinutes: 30, todaySeconds: 1800)));
      await linkChild();
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      now = now.add(const Duration(seconds: 3));
      sync.checkLimit();
      expect(sync.limit.locked, isTrue);
      await background(const Duration(minutes: 20));
      await sync.flush();
      final total = eventsSent().where((e) => e['type'] == 'screenTime').fold<int>(0, (a, e) => a + (e['seconds'] as int));
      expect(total, 3, reason: '20 phút ở màn hình khoá không tính');
    });

    test('bố mẹ cho chơi thêm: mở khoá, đếm lại từ lúc mở khoá', () async {
      server.on('GET /api/progress/me', 200, snapshot(limitMinutes: 30, todaySeconds: 1799));
      server.on('POST /api/progress/events', 200, eventResult(snapshot(limitMinutes: 30, todaySeconds: 1800)));
      await linkChild();
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      now = now.add(const Duration(seconds: 3));
      sync.checkLimit();
      expect(sync.limit.locked, isTrue);
      now = now.add(const Duration(minutes: 5)); // máy nằm ở màn hình khoá
      sync.limit.grantMore(10);
      expect(sync.limit.locked, isFalse);
      now = now.add(const Duration(minutes: 9));
      sync.checkLimit();
      expect(sync.limit.locked, isFalse, reason: 'được đúng 10 phút kể từ lúc mở khoá, 9 phút chưa hết');
      now = now.add(const Duration(minutes: 2));
      sync.checkLimit();
      expect(sync.limit.locked, isTrue);
    });

    test('không có giới hạn thì không bao giờ khoá', () async {
      server.on('GET /api/progress/me', 200, snapshot(limitMinutes: null, todaySeconds: 99999));
      await linkChild();
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      now = now.add(const Duration(hours: 3));
      sync.checkLimit();
      expect(sync.limit.locked, isFalse);
      expect(sync.limit.remainingSeconds, isNull);
    });

    test('chế độ khách không bị giới hạn; thoát chế độ bé thì mở khoá', () async {
      expect(sync.limit.locked, isFalse);
      server.on('GET /api/progress/me', 200, snapshot(limitMinutes: 5, todaySeconds: 600));
      await linkChild();
      expect(sync.limit.locked, isTrue);
      await leave();
      expect(sync.limit.locked, isFalse);
      expect(sync.limit.limitMinutes, isNull);
    });

    test('phần chưa gửi (mất mạng) vẫn được tính vào số giây đã dùng', () async {
      server.on('GET /api/progress/me', 200, snapshot(limitMinutes: 30, todaySeconds: 600));
      await linkChild();
      server.on('POST /api/progress/events', 503, {'message': 'x'});
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await background(const Duration(seconds: 300)); // ghi 300 giây vào hàng đợi, gửi lỗi
      expect(sync.pendingCount, 1);
      // Mở lại ứng dụng: máy chủ vẫn nói 600, nhưng 300 giây chưa gửi phải được cộng vào.
      await sync.hydrate();
      expect(sync.limit.recordedSeconds, 900);
    });

    test('mở lại app khi mất mạng vẫn nhớ giờ đã dùng và giới hạn (không né được bằng tắt mạng)', () async {
      server.on('GET /api/progress/me', 200, snapshot(limitMinutes: 10, todaySeconds: 600));
      await linkChild();
      expect(sync.limit.locked, isTrue);
      final restarted = SyncService(auth: auth, autoFlush: false, clock: () => now);
      transport = (_) async => throw const ApiException('mất mạng');
      await restarted.attach();
      expect(restarted.limit.limitMinutes, 10);
      expect(restarted.limit.locked, isTrue);
      restarted.detach();
    });
  });

  group('Sự kiện kèm dữ liệu', () {
    test('phần body của sự kiện scan không có trường thừa', () async {
      await linkChild();
      sync.recordScan('cup');
      server.on('POST /api/progress/events', 200, eventResult(snapshot()));
      await sync.flush();
      final e = eventsSent().single;
      expect(e.keys.toSet(), {'id', 'type', 'at', 'wordId'});
      expect(jsonEncode(e), isNot(contains('null')));
    });
  });
}

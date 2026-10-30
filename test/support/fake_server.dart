import 'dart:convert';

import 'package:english_cam/core/api_client.dart';
import 'package:english_cam/services/device_identity.dart';
import 'package:english_cam/services/google_auth.dart';

typedef Handler = HttpResponseData Function(HttpRequestData request);

/// Máy chủ giả trong bộ nhớ: khớp theo "METHOD /đường/dẫn", ghi lại mọi request để test kiểm tra.
class FakeServer {
  final List<HttpRequestData> calls = [];
  final Map<String, Handler> _routes = {};

  Future<HttpResponseData> call(HttpRequestData r) async {
    calls.add(r);
    final h = _routes['${r.method} ${r.url.path}'];
    return h == null ? json(404, {'message': 'chưa khai báo route'}) : h(r);
  }

  static HttpResponseData json(int status, Object? body) =>
      HttpResponseData(status, body == null ? '' : jsonEncode(body));

  /// Trả cố định [body] với mã [status].
  void on(String key, int status, [Object? body]) =>
      _routes[key] = (_) => json(status, body);

  void handle(String key, Handler h) => _routes[key] = h;

  List<HttpRequestData> to(String key) => [
    for (final c in calls)
      if ('${c.method} ${c.url.path}' == key) c,
  ];

  Map<String, dynamic> bodyOf(HttpRequestData r) =>
      jsonDecode(r.body!) as Map<String, dynamic>;
}

/// Kết quả đăng nhập mẫu của máy chủ (`AuthResultDto`).
Map<String, dynamic> authJson({
  String role = 'Parent',
  String token = 'tok-parent',
  String userId = 'u1',
  String name = 'Mẹ Lan',
  String email = 'lan@test.com',
  Duration lifetime = const Duration(days: 7),
}) => {
  'token': token,
  'expiresAt': DateTime.now().add(lifetime).toUtc().toIso8601String(),
  'role': role,
  'userId': userId,
  'fullName': name,
  'email': email,
};

/// Hồ sơ bé mẫu (`ChildDto`).
Map<String, dynamic> childJson({
  String id = 'c1',
  String nickname = 'Bi',
  String avatarKey = 'cat',
  int goal = 5,
  int? limit,
  bool active = true,
  int devices = 0,
}) => {
  'id': id,
  'nickname': nickname,
  'avatarKey': avatarKey,
  'birthYear': null,
  'dailyLimitMinutes': limit,
  'dailyWordGoal': goal,
  'isActive': active,
  'activeDevices': devices,
  'lastActiveAt': null,
  'createdAt': DateTime.now().toUtc().toIso8601String(),
};

class FakeGoogle implements GoogleAuth {
  String? idToken = 'google-id-token';
  Object? error;
  int signOuts = 0;

  @override
  Future<String> getIdToken() async {
    if (error != null) throw error!;
    return idToken!;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

class FakeDevice implements DeviceIdentity {
  @override
  Future<DeviceInfo> get() async => const DeviceInfo('device-123', 'Máy thử');
}

/// Dashboard mẫu (`ChildDashboardDto`): [days] ngày, ngày cuối là hôm nay.
Map<String, dynamic> dashboardJson({
  int days = 7,
  int learned = 12,
  int total = 60,
  int stars = 24,
  int streak = 3,
  int best = 5,
  int? accuracy = 78,
  int todaySeconds = 600,
  int todayWords = 2,
  int goal = 5,
  int? limit,
  List<Map<String, dynamic>>? weak,
  List<Map<String, dynamic>>? recent,
  List<Map<String, dynamic>>? badges,
}) {
  final today = DateTime.now();
  return {
    'childId': 'c1',
    'nickname': 'Bi',
    'avatarKey': 'fox',
    'isActive': true,
    'dailyWordGoal': goal,
    'dailyLimitMinutes': limit,
    'days': days,
    'vocabVersion': 1,
    'totals': {
      'learnedWords': learned,
      'totalWords': total,
      'stars': stars,
      'rounds': 4,
      'perfectRounds': 1,
      'found': 2,
      'currentStreak': streak,
      'bestStreak': best,
      'totalMinutes': 95,
      'accuracyPercent': accuracy,
    },
    'today': {
      'seconds': todaySeconds,
      'wordsLearned': todayWords,
      'rounds': 1,
      'scans': 1,
      'goalMet': todayWords >= goal,
    },
    'daysData': [
      for (var i = 0; i < days; i++)
        () {
          final d = today.subtract(Duration(days: days - 1 - i));
          final last = i == days - 1;
          return {
            'date': '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
            'seconds': last ? todaySeconds : (i % 2 == 0 ? 300 : 0),
            'wordsLearned': last ? todayWords : (i % 3 == 0 ? 1 : 0),
            'rounds': 0,
            'scans': 0,
          };
        }(),
    ],
    'categories': [
      {'id': 'school', 'vi': 'Đồ dùng học tập', 'en': 'School', 'emoji': '🎒', 'color': '#FFE0B2', 'learned': 3, 'total': 5},
      {'id': 'animals', 'vi': 'Động vật', 'en': 'Animals', 'emoji': '🐶', 'color': '#E3F2C1', 'learned': 0, 'total': 8},
    ],
    'weakWords': weak ??
        [
          {'wordId': 'pen', 'en': 'pen', 'vi': 'cái bút', 'emoji': '🖊️', 'wrong': 2, 'total': 2, 'accuracyPercent': 0},
          {'wordId': 'cup', 'en': 'cup', 'vi': 'cái cốc', 'emoji': '☕', 'wrong': 1, 'total': 2, 'accuracyPercent': 50},
        ],
    'recentBadges': badges ??
        [
          {'id': 'first_round', 'name': 'Bé tập chơi', 'emoji': '🎮', 'description': 'Hoàn thành 1 ván chơi', 'unlockedAt': DateTime.now().toUtc().toIso8601String()},
        ],
    'badgesUnlocked': badges?.length ?? 1,
    'badgesTotal': 10,
    'recent': recent ??
        [
          {'at': DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String(), 'kind': 'match', 'stars': 6, 'correct': 8, 'questions': 8, 'durationSec': 60, 'wordId': null, 'wordEn': null, 'wordVi': null},
          {'at': DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String(), 'kind': 'hunt', 'stars': 2, 'correct': 1, 'questions': 1, 'durationSec': 0, 'wordId': 'cup', 'wordEn': 'cup', 'wordVi': 'cái cốc'},
        ],
  };
}

/// Thẻ tóm tắt mẫu (`OverviewChildDto`).
Map<String, dynamic> overviewJson({String id = 'c1', int stars = 24, int streak = 3, int minutes = 12, int learned = 12}) => {
  'id': id,
  'nickname': 'Bi',
  'avatarKey': 'cat',
  'isActive': true,
  'dailyWordGoal': 5,
  'dailyLimitMinutes': null,
  'learnedWords': learned,
  'totalWords': 60,
  'stars': stars,
  'currentStreak': streak,
  'minutesToday': minutes,
  'wordsLearnedToday': 2,
  'activeDevices': 1,
  'lastActiveDate': null,
};

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../data/game_badge.dart';
import 'auth_service.dart';
import 'game_progress.dart';
import 'play_limit.dart';
import 'progress_service.dart';

/// Một câu hỏi "Nghe & chọn hình" do máy chủ chọn (theo từ bé hay sai / chưa gặp).
class ServerQuestion {
  const ServerQuestion(this.target, this.options);

  final String target;
  final List<String> options;
}

/// Đáp án một câu trong ván "Nghe & chọn hình": số lần bé chọn ở câu đó (đúng ngay lần đầu = 1).
class MatchAnswer {
  const MatchAnswer(this.wordId, this.attempts);

  final String wordId;
  final int attempts;
}

const int _kMaxOutbox = 2000;
const int _kEventBatch = 100;
const Duration _kDebounce = Duration(seconds: 3);
const Duration _kTick = Duration(seconds: 60);
const Duration _kLimitTick = Duration(seconds: 10);

/// Đồng bộ tiến độ của bé với máy chủ, theo kiểu **offline-first**: mọi thay đổi ghi ngay vào máy (bé thấy liền) và vào
/// một hàng đợi (outbox) lưu bền; khi có mạng thì gửi lên. Mỗi mục có id riêng nên gửi lại không bị cộng đôi. Sau mỗi lần
/// gửi, máy chủ trả trạng thái tổng hợp từ MỌI thiết bị của bé; máy đặt lại số liệu = trạng thái máy chủ + phần chưa gửi.
///
/// Chỉ hoạt động khi máy đang ở chế độ bé (đã đăng nhập). Chế độ khách không gửi gì. Mỗi hồ sơ bé có ngăn lưu và hàng đợi
/// riêng, nên hai bé dùng chung một máy không lẫn tiến độ của nhau.
class SyncService with WidgetsBindingObserver {
  SyncService({
    AuthService? auth,
    ProgressService? progress,
    GameProgress? game,
    this.autoFlush = true,
    DateTime Function()? clock,
    Random? random,
    PlayLimit? limit,
  }) : _authOverride = auth,
       _progress = progress ?? ProgressService.instance,
       _game = game ?? GameProgress.instance,
       _clock = clock ?? DateTime.now,
       limit = limit ?? PlayLimit(clock: clock),
       _rng = random ?? Random.secure();

  static SyncService instance = SyncService();

  final AuthService? _authOverride;
  final ProgressService _progress;
  final GameProgress _game;
  final DateTime Function() _clock;
  final Random _rng;

  /// Giới hạn thời gian chơi mỗi ngày của bé đang dùng máy (xem [PlayLimit]); màn khoá lắng nghe đối tượng này.
  final PlayLimit limit;

  /// Tự gửi sau mỗi thay đổi, theo chu kỳ và khi app quay lại. Test đặt false rồi gọi [flush] bằng tay.
  final bool autoFlush;

  AuthService get _auth => _authOverride ?? AuthService.instance;

  String? _profile;
  List<Map<String, dynamic>> _outbox = [];
  bool _flushing = false;
  bool _attached = false;
  Future<void> _profileQueue = Future.value();
  Timer? _debounce;
  Timer? _ticker;
  Timer? _limitTimer;
  DateTime? _fgSince;
  bool _wasLocked = false;

  /// Vật nên tìm tiếp theo do máy chủ gợi ý (theo từ bé ít thuộc); rỗng nếu chưa tải được.
  List<String> huntHints = const [];

  /// true khi máy đang ở chế độ bé và có thể đồng bộ.
  bool get active => _profile != null;
  int get pendingCount => _outbox.length;

  String get _outboxKey => 'sync.outbox.$_profile';

  // ---------- Khởi động và đổi hồ sơ ----------

  /// Gọi một lần sau khi [AuthService.init]: theo dõi đăng nhập/đăng xuất của bé, đo thời gian dùng, nạp ngăn lưu đúng.
  Future<void> attach() async {
    if (!_attached) {
      _attached = true;
      _auth.addListener(_onAuthChanged);
      _progress.onLearnedChanged = recordLearned;
      limit.liveSeconds = _liveSeconds;
      limit.addListener(_onLimitChanged);
      if (autoFlush) {
        WidgetsBinding.instance.addObserver(this);
        _fgSince = _clock();
        _ticker = Timer.periodic(_kTick, (_) => _tick());
        _limitTimer = Timer.periodic(_kLimitTick, (_) => checkLimit());
      }
    }
    await _applyProfile();
  }

  void detach() {
    _auth.removeListener(_onAuthChanged);
    _progress.onLearnedChanged = null;
    _debounce?.cancel();
    _ticker?.cancel();
    _limitTimer?.cancel();
    limit.removeListener(_onLimitChanged);
    if (autoFlush && _attached) WidgetsBinding.instance.removeObserver(this);
    _attached = false;
  }

  void _onAuthChanged() {
    // Tuần tự hoá: đổi hồ sơ liên tiếp không được chạy chồng lên nhau.
    _profileQueue = _profileQueue.then((_) => _applyProfile()).catchError((Object e) {
      debugPrint('Sync profile switch failed: $e');
    });
  }

  Future<void> _applyProfile() async {
    final want = _auth.child?.userId;
    if (want == _profile) return;
    _flushScreenTime();
    _debounce?.cancel();
    _profile = want;
    huntHints = const [];
    await _loadOutbox();
    await _progress.useProfile(want);
    await _game.useProfile(want);
    await limit.useProfile(want);
    if (want != null) _initialSync = sync(forceHydrate: true);
  }

  Future<void>? _initialSync;

  /// Chờ việc đổi hồ sơ và lần đồng bộ đầu tiên của hồ sơ đó xong (cho test).
  @visibleForTesting
  Future<void> get settled async {
    await _profileQueue;
    await _initialSync;
  }

  // ---------- Ghi nhận thay đổi ----------

  void recordLearned(String wordId, bool learned) {
    if (!active) return;
    _enqueue({'k': 'e', 'id': _uuid(), 'type': 'learned', 'wordId': wordId, 'learned': learned, 'at': _iso()});
  }

  /// Máy nhận ra một vật qua camera (chỉ khi đủ tự tin).
  void recordScan(String wordId) {
    if (!active) return;
    _enqueue({'k': 'e', 'id': _uuid(), 'type': 'scan', 'wordId': wordId, 'at': _iso()});
  }

  /// Một ván "Nghe & chọn hình" đã xong. [stars]/[perfect] là số máy đã tính cho bé xem ngay; máy chủ tính lại từ [answers].
  void recordMatchRound({
    required DateTime startedAt,
    required int durationSec,
    required List<MatchAnswer> answers,
    required int stars,
    required bool perfect,
  }) {
    if (!active) return;
    _enqueue({
      'k': 's',
      'id': _uuid(),
      'game': 'match',
      'startedAt': startedAt.toUtc().toIso8601String(),
      'durationSec': durationSec,
      'answers': [for (final a in answers) {'wordId': a.wordId, 'correct': true, 'attempts': a.attempts}],
      'stars': stars,
      'perfect': perfect,
      'found': 0,
      'rounds': 1,
    });
  }

  /// Bé tìm được một vật. [byParent] = bố mẹ xác nhận tay (1 sao) thay vì model nhận ra (2 sao).
  void recordHuntFound({required String wordId, required bool byParent, required int stars}) {
    if (!active) return;
    _enqueue({
      'k': 's',
      'id': _uuid(),
      'game': 'hunt',
      'startedAt': _iso(),
      'durationSec': 0,
      'answers': [{'wordId': wordId, 'correct': true, 'attempts': 1, 'via': byParent ? 'parent' : 'model'}],
      'stars': stars,
      'perfect': false,
      'found': 1,
      'rounds': 0,
    });
  }

  void _enqueue(Map<String, dynamic> item) {
    _outbox.add(item);
    if (_outbox.length > _kMaxOutbox) {
      // Quá đầy (mất mạng rất lâu): bỏ sự kiện cũ nhất; giữ các ván vì chúng mang sao của bé.
      final i = _outbox.indexWhere((e) => e['k'] == 'e');
      if (i >= 0) _outbox.removeAt(i);
    }
    unawaited(_saveOutbox());
    if (autoFlush) {
      _debounce?.cancel();
      _debounce = Timer(_kDebounce, () => unawaited(flush()));
    }
  }

  // ---------- Câu hỏi từ máy chủ ----------

  /// Câu hỏi do máy chủ chọn. Trả null nếu không ở chế độ bé, mất mạng, quá [timeout] hoặc có lỗi — khi đó game tự tạo câu hỏi.
  Future<List<ServerQuestion>?> fetchMatchQuestions(int count, {Duration timeout = const Duration(seconds: 3)}) async {
    if (!active) return null;
    try {
      final json = await _auth.api
          .get('/api/games/match/questions?count=$count', auth: ApiAuth.child)
          .timeout(timeout) as Map<String, dynamic>;
      return [
        for (final q in json['questions'] as List<dynamic>)
          ServerQuestion(
            (q as Map<String, dynamic>)['wordId'] as String,
            [for (final o in q['optionIds'] as List<dynamic>) o as String],
          ),
      ];
    } catch (e) {
      debugPrint('fetchMatchQuestions failed: $e');
      return null;
    }
  }

  /// Gợi ý vật cần tìm (lưu vào [huntHints]); lỗi thì để nguyên danh sách cũ.
  Future<void> fetchHuntTargets(int count, {Duration timeout = const Duration(seconds: 3)}) async {
    if (!active) return;
    try {
      final json = await _auth.api
          .get('/api/games/hunt/targets?count=$count', auth: ApiAuth.child)
          .timeout(timeout) as Map<String, dynamic>;
      huntHints = [for (final id in json['wordIds'] as List<dynamic>) id as String];
    } catch (e) {
      debugPrint('fetchHuntTargets failed: $e');
    }
  }

  // ---------- Gửi và nhận ----------

  /// Gửi hàng đợi rồi (nếu cần) tải trạng thái mới. [forceHydrate]: luôn làm tươi cả huy hiệu và trạng thái.
  Future<void> sync({bool forceHydrate = false}) async {
    if (!active) return;
    final got = await flush();
    if (!active) return;
    if (!got) {
      await hydrate();
    } else if (forceHydrate) {
      await _refreshBadges();
    }
  }

  /// Gửi các ván rồi các sự kiện trong hàng đợi, theo thứ tự. Lỗi mạng/máy chủ: giữ lại, lần sau gửi tiếp.
  /// Lỗi 4xx do dữ liệu (không thể thành công dù thử lại): bỏ mục đó để không kẹt hàng đợi.
  /// Trả true nếu nhận được trạng thái mới từ máy chủ.
  Future<bool> flush() async {
    if (!active) return false;
    if (_flushing) {
      _flushAgain = true; // có thay đổi mới trong lúc đang gửi: gửi tiếp ngay khi xong, không để chờ lần kích hoạt sau
      return false;
    }
    _flushing = true;
    final profile = _profile;
    Map<String, dynamic>? snapshot;
    try {
      while (_profile == profile) {
        final session = _outbox.cast<Map<String, dynamic>?>().firstWhere((e) => e!['k'] == 's', orElse: () => null);
        if (session == null) break;
        try {
          final res = await _auth.api.post('/api/games/sessions', body: _sessionBody(session), auth: ApiAuth.child);
          snapshot = (res as Map<String, dynamic>)['progress'] as Map<String, dynamic>;
          await _remove([session['id'] as String]);
        } on ApiException catch (e) {
          if (_retryable(e)) return await _finishFlush(snapshot, profile);
          debugPrint('Sync: bỏ ván không gửi được (${e.status}): ${e.message}');
          await _remove([session['id'] as String]);
        }
      }
      while (_profile == profile) {
        final events = [for (final e in _outbox) if (e['k'] == 'e') e].take(_kEventBatch).toList();
        if (events.isEmpty) break;
        try {
          final res = await _auth.api.post(
            '/api/progress/events',
            body: {'events': [for (final e in events) _eventBody(e)]},
            auth: ApiAuth.child,
          );
          snapshot = (res as Map<String, dynamic>)['progress'] as Map<String, dynamic>;
          await _remove([for (final e in events) e['id'] as String]);
        } on ApiException catch (e) {
          if (_retryable(e)) return await _finishFlush(snapshot, profile);
          debugPrint('Sync: bỏ lô sự kiện không gửi được (${e.status}): ${e.message}');
          await _remove([for (final e in events) e['id'] as String]);
        }
      }
      return await _finishFlush(snapshot, profile);
    } catch (e) {
      debugPrint('Sync flush failed: $e');
      return false;
    } finally {
      _flushing = false;
      if (_flushAgain) {
        _flushAgain = false;
        if (active && _outbox.isNotEmpty) unawaited(flush());
      }
    }
  }

  bool _flushAgain = false;

  static bool _retryable(ApiException e) =>
      e.isNetwork || e.status == 401 || e.status == 429 || (e.status ?? 0) >= 500;

  Future<bool> _finishFlush(Map<String, dynamic>? snapshot, String? profile) async {
    // Đổi hồ sơ giữa chừng thì không được áp trạng thái của bé cũ lên bé mới.
    if (snapshot == null || !active || _profile != profile) return false;
    await _applySnapshot(snapshot);
    return true;
  }

  Map<String, dynamic> _sessionBody(Map<String, dynamic> s) => {
    'id': s['id'],
    'gameType': s['game'],
    'startedAt': s['startedAt'],
    'durationSec': s['durationSec'],
    'answers': s['answers'],
  };

  Map<String, dynamic> _eventBody(Map<String, dynamic> e) => {
    'id': e['id'],
    'type': e['type'],
    'at': e['at'],
    'wordId': ?e['wordId'],
    'learned': ?e['learned'],
    'seconds': ?e['seconds'],
  };

  /// Tải trạng thái hiện tại của bé và danh sách huy hiệu. Lỗi thì giữ nguyên số liệu trên máy.
  Future<bool> hydrate() async {
    if (!active) return false;
    final profile = _profile;
    try {
      final me = await _auth.api.get('/api/progress/me', auth: ApiAuth.child);
      if (_profile != profile) return false;
      await _applySnapshot(me as Map<String, dynamic>);
      await _refreshBadges();
      return true;
    } catch (e) {
      debugPrint('Sync hydrate failed: $e');
      return false;
    }
  }

  Future<void> _refreshBadges() async {
    try {
      final list = await _auth.api.get('/api/games/badges', auth: ApiAuth.child);
      await BadgeRepository.replace([
        for (final b in list as List<dynamic>) GameBadge.fromJson(b as Map<String, dynamic>),
      ]);
      _game.checkBadges();
    } catch (e) {
      debugPrint('Sync badges failed: $e');
    }
  }

  /// Đặt số liệu trên máy = máy chủ + phần chưa gửi (để bé không thấy sao "lùi" khi đang offline).
  Future<void> _applySnapshot(Map<String, dynamic> s) async {
    var stars = 0, rounds = 0, perfect = 0, found = 0;
    final learned = {for (final id in s['learnedWordIds'] as List<dynamic>) id as String};
    for (final item in _outbox) {
      if (item['k'] == 's') {
        stars += item['stars'] as int;
        rounds += item['rounds'] as int;
        perfect += (item['perfect'] as bool) ? 1 : 0;
        found += item['found'] as int;
      } else if (item['type'] == 'learned') {
        (item['learned'] as bool) ? learned.add(item['wordId'] as String) : learned.remove(item['wordId'] as String);
      }
    }
    await _progress.replaceLearned(learned);
    await _game.applyServer(
      stars: (s['stars'] as int) + stars,
      rounds: (s['rounds'] as int) + rounds,
      perfect: (s['perfectRounds'] as int) + perfect,
      found: (s['found'] as int) + found,
      bestStreak: s['bestStreak'] as int,
      badgeIds: [for (final id in s['badgeIds'] as List<dynamic>) id as String],
    );
    final today = s['today'] as Map<String, dynamic>?;
    limit.applySnapshot(
      limitMinutes: s['dailyLimitMinutes'] as int?,
      serverSeconds: today?['seconds'] as int? ?? 0,
      pendingSeconds: _pendingScreenSecondsToday(),
    );
  }

  /// Giây dùng app hôm nay còn nằm trong hàng đợi (chưa được máy chủ xác nhận).
  int _pendingScreenSecondsToday() {
    final now = _clock().toLocal();
    var total = 0;
    for (final e in _outbox) {
      if (e['type'] != 'screenTime') continue;
      final at = DateTime.tryParse(e['at'] as String? ?? '')?.toLocal();
      if (at == null || at.year != now.year || at.month != now.month || at.day != now.day) continue;
      total += e['seconds'] as int;
    }
    return total;
  }

  /// Sau khi bố mẹ xoá tiến độ của bé trên máy chủ: bỏ phần chưa gửi (thuộc về tiến độ cũ) rồi tải trạng thái trống về.
  Future<void> discardPendingAndHydrate() async {
    _outbox = [];
    await _saveOutbox();
    await hydrate();
  }

  // ---------- Thời gian dùng ----------

  void _tick() {
    _flushScreenTime();
    if (_outbox.isNotEmpty) unawaited(flush());
  }

  /// Ghi số giây app đã mở ở chế độ bé kể từ lần ghi trước (tối thiểu 2 giây mới ghi). Khi đang khoá vì hết giờ thì
  /// không ghi (màn khoá để đó không phải là bé đang chơi), trừ lần ghi nốt đúng lúc khoá ([beforeLock]).
  void _flushScreenTime({bool beforeLock = false}) {
    final since = _fgSince;
    if (since == null) return;
    final now = _clock();
    _fgSince = now;
    if (!active) return;
    if (limit.locked && !beforeLock) return;
    final seconds = min(now.difference(since).inSeconds, 3600);
    if (seconds < 2) return;
    _enqueue({'k': 'e', 'id': _uuid(), 'type': 'screenTime', 'seconds': seconds, 'at': _iso()});
    limit.addRecorded(seconds);
  }

  /// Số giây app đã mở (chế độ bé) mà chưa ghi vào hàng đợi.
  int _liveSeconds() {
    final since = _fgSince;
    if (since == null || !active) return 0;
    return max(0, _clock().difference(since).inSeconds);
  }

  /// Kiểm tra hết giờ chơi (mỗi 10 giây). Vừa hết giờ thì ghi nốt thời gian đang đếm rồi khoá.
  @visibleForTesting
  void checkLimit() {
    if (limit.evaluate()) _flushScreenTime(beforeLock: true);
    if (limit.takeWarning()) onLimitWarning?.call();
  }

  /// Được gọi một lần mỗi ngày khi bé còn không quá 5 phút (main.dart cho Cam nhắc bằng SnackBar).
  VoidCallback? onLimitWarning;

  void _onLimitChanged() {
    final locked = limit.locked;
    if (_wasLocked && !locked && _fgSince != null) _fgSince = _clock(); // mở khoá: đếm lại từ bây giờ
    _wasLocked = locked;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _fgSince = _clock();
        checkLimit();
        unawaited(sync());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _flushScreenTime();
        _fgSince = null;
        unawaited(flush());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break; // hộp thoại hệ thống (quyền camera...) không phải là rời app
    }
  }

  // ---------- Lưu hàng đợi ----------

  Future<void> _loadOutbox() async {
    _outbox = [];
    if (_profile == null) return;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_outboxKey);
      if (raw != null) {
        _outbox = [for (final e in jsonDecode(raw) as List<dynamic>) e as Map<String, dynamic>];
      }
    } catch (e) {
      debugPrint('Sync outbox unreadable, starting empty: $e');
    }
  }

  Future<void> _saveOutbox() async {
    if (_profile == null) return;
    try {
      await (await SharedPreferences.getInstance()).setString(_outboxKey, jsonEncode(_outbox));
    } catch (e) {
      debugPrint('Sync outbox save failed: $e');
    }
  }

  Future<void> _remove(List<String> ids) async {
    final set = ids.toSet();
    _outbox.removeWhere((e) => set.contains(e['id']));
    await _saveOutbox();
  }

  // ---------- Tiện ích ----------

  String _iso() => _clock().toUtc().toIso8601String();

  String _uuid() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

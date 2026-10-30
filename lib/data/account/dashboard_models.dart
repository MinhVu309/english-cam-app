/// Dữ liệu dashboard phụ huynh từ `GET /api/parent/...` (xem `english-cam-api/Dtos/DashboardDtos.cs`).
library;

DateTime _utc(Object? v) => DateTime.parse(v as String).toUtc();

/// Thẻ tóm tắt một bé trong danh sách (`OverviewChildDto`).
class ChildOverview {
  const ChildOverview({
    required this.id,
    required this.stars,
    required this.learnedWords,
    required this.totalWords,
    required this.currentStreak,
    required this.minutesToday,
    required this.wordsLearnedToday,
  });

  factory ChildOverview.fromJson(Map<String, dynamic> j) => ChildOverview(
    id: j['id'] as String,
    stars: j['stars'] as int,
    learnedWords: j['learnedWords'] as int,
    totalWords: j['totalWords'] as int,
    currentStreak: j['currentStreak'] as int,
    minutesToday: j['minutesToday'] as int,
    wordsLearnedToday: j['wordsLearnedToday'] as int,
  );

  final String id;
  final int stars;
  final int learnedWords;
  final int totalWords;
  final int currentStreak;
  final int minutesToday;
  final int wordsLearnedToday;
}

class DashboardTotals {
  const DashboardTotals({
    required this.learnedWords,
    required this.totalWords,
    required this.stars,
    required this.rounds,
    required this.perfectRounds,
    required this.found,
    required this.currentStreak,
    required this.bestStreak,
    required this.totalMinutes,
    this.accuracyPercent,
  });

  factory DashboardTotals.fromJson(Map<String, dynamic> j) => DashboardTotals(
    learnedWords: j['learnedWords'] as int,
    totalWords: j['totalWords'] as int,
    stars: j['stars'] as int,
    rounds: j['rounds'] as int,
    perfectRounds: j['perfectRounds'] as int,
    found: j['found'] as int,
    currentStreak: j['currentStreak'] as int,
    bestStreak: j['bestStreak'] as int,
    totalMinutes: j['totalMinutes'] as int,
    accuracyPercent: j['accuracyPercent'] as int?,
  );

  final int learnedWords;
  final int totalWords;
  final int stars;
  final int rounds;
  final int perfectRounds;
  final int found;
  final int currentStreak;
  final int bestStreak;
  final int totalMinutes;

  /// Tỉ lệ câu đúng ngay lần đầu trong khoảng đang xem; null nếu chưa có ván nào.
  final int? accuracyPercent;
}

class DashboardToday {
  const DashboardToday({
    required this.seconds,
    required this.wordsLearned,
    required this.rounds,
    required this.scans,
    required this.goalMet,
  });

  factory DashboardToday.fromJson(Map<String, dynamic> j) => DashboardToday(
    seconds: j['seconds'] as int,
    wordsLearned: j['wordsLearned'] as int,
    rounds: j['rounds'] as int,
    scans: j['scans'] as int,
    goalMet: j['goalMet'] as bool,
  );

  final int seconds;
  final int wordsLearned;
  final int rounds;
  final int scans;
  final bool goalMet;
}

class DashboardDay {
  const DashboardDay({
    required this.date,
    required this.seconds,
    required this.wordsLearned,
    required this.rounds,
    required this.scans,
  });

  factory DashboardDay.fromJson(Map<String, dynamic> j) => DashboardDay(
    date: DateTime.parse(j['date'] as String), // ngày địa phương (yyyy-MM-dd)
    seconds: j['seconds'] as int,
    wordsLearned: j['wordsLearned'] as int,
    rounds: j['rounds'] as int,
    scans: j['scans'] as int,
  );

  final DateTime date;
  final int seconds;
  final int wordsLearned;
  final int rounds;
  final int scans;

  double get minutes => seconds / 60;
}

class CategoryProgress {
  const CategoryProgress({
    required this.id,
    required this.vi,
    required this.learned,
    required this.total,
    this.emoji,
  });

  factory CategoryProgress.fromJson(Map<String, dynamic> j) => CategoryProgress(
    id: j['id'] as String,
    vi: j['vi'] as String,
    emoji: j['emoji'] as String?,
    learned: j['learned'] as int,
    total: j['total'] as int,
  );

  final String id;
  final String vi;
  final String? emoji;
  final int learned;
  final int total;
}

class WeakWord {
  const WeakWord({
    required this.wordId,
    required this.en,
    required this.vi,
    required this.wrong,
    required this.total,
    required this.accuracyPercent,
    this.emoji,
  });

  factory WeakWord.fromJson(Map<String, dynamic> j) => WeakWord(
    wordId: j['wordId'] as String,
    en: j['en'] as String,
    vi: j['vi'] as String,
    emoji: j['emoji'] as String?,
    wrong: j['wrong'] as int,
    total: j['total'] as int,
    accuracyPercent: j['accuracyPercent'] as int,
  );

  final String wordId;
  final String en;
  final String vi;
  final String? emoji;
  final int wrong;
  final int total;
  final int accuracyPercent;
}

class DashboardBadge {
  const DashboardBadge({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
  });

  factory DashboardBadge.fromJson(Map<String, dynamic> j) => DashboardBadge(
    id: j['id'] as String,
    name: j['name'] as String,
    emoji: j['emoji'] as String,
    description: j['description'] as String,
  );

  final String id;
  final String name;
  final String emoji;
  final String description;
}

/// Một hoạt động gần đây: ván "Nghe & chọn hình" (`match`) hoặc một vật đã tìm thấy (`hunt`).
class RecentActivity {
  const RecentActivity({
    required this.at,
    required this.kind,
    required this.stars,
    required this.correct,
    required this.questions,
    this.wordEn,
    this.wordVi,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> j) => RecentActivity(
    at: _utc(j['at']),
    kind: j['kind'] as String,
    stars: j['stars'] as int,
    correct: j['correct'] as int,
    questions: j['questions'] as int,
    wordEn: j['wordEn'] as String?,
    wordVi: j['wordVi'] as String?,
  );

  final DateTime at;
  final String kind;
  final int stars;
  final int correct;
  final int questions;
  final String? wordEn;
  final String? wordVi;

  bool get isHunt => kind == 'hunt';
}

class ChildDashboard {
  const ChildDashboard({
    required this.childId,
    required this.nickname,
    required this.avatarKey,
    required this.dailyWordGoal,
    required this.dailyLimitMinutes,
    required this.days,
    required this.totals,
    required this.today,
    required this.daysData,
    required this.categories,
    required this.weakWords,
    required this.recentBadges,
    required this.badgesUnlocked,
    required this.badgesTotal,
    required this.recent,
  });

  factory ChildDashboard.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) => [
      for (final e in j[key] as List<dynamic>) f(e as Map<String, dynamic>),
    ];
    return ChildDashboard(
      childId: j['childId'] as String,
      nickname: j['nickname'] as String,
      avatarKey: j['avatarKey'] as String?,
      dailyWordGoal: j['dailyWordGoal'] as int,
      dailyLimitMinutes: j['dailyLimitMinutes'] as int?,
      days: j['days'] as int,
      totals: DashboardTotals.fromJson(j['totals'] as Map<String, dynamic>),
      today: DashboardToday.fromJson(j['today'] as Map<String, dynamic>),
      daysData: list('daysData', DashboardDay.fromJson),
      categories: list('categories', CategoryProgress.fromJson),
      weakWords: list('weakWords', WeakWord.fromJson),
      recentBadges: list('recentBadges', DashboardBadge.fromJson),
      badgesUnlocked: j['badgesUnlocked'] as int,
      badgesTotal: j['badgesTotal'] as int,
      recent: list('recent', RecentActivity.fromJson),
    );
  }

  final String childId;
  final String nickname;
  final String? avatarKey;
  final int dailyWordGoal;
  final int? dailyLimitMinutes;
  final int days;
  final DashboardTotals totals;
  final DashboardToday today;
  final List<DashboardDay> daysData;
  final List<CategoryProgress> categories;
  final List<WeakWord> weakWords;
  final List<DashboardBadge> recentBadges;
  final int badgesUnlocked;
  final int badgesTotal;
  final List<RecentActivity> recent;

  /// Bé đã dùng quá giới hạn thời gian hôm nay (chỉ để báo cho bố mẹ biết; app không tự khoá).
  bool get overLimitToday =>
      dailyLimitMinutes != null && today.seconds > dailyLimitMinutes! * 60;
}

/// "dưới 1 phút", "5 phút", "1 giờ 20 phút".
String formatDuration(int seconds) {
  if (seconds <= 0) return '0 phút';
  if (seconds < 60) return 'dưới 1 phút';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes phút';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h giờ' : '$h giờ $m phút';
}

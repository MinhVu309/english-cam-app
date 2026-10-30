/// Mô hình dữ liệu của khu quản trị (khớp các DTO trong `english-cam-api/Dtos/AdminDtos.cs`, `VocabDtos.cs`).
library;

class PagedList<T> {
  const PagedList(this.total, this.page, this.pageSize, this.items);

  factory PagedList.fromJson(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) item,
  ) => PagedList(j['total'] as int, j['page'] as int, j['pageSize'] as int, [
    for (final e in j['items'] as List<dynamic>)
      item(e as Map<String, dynamic>),
  ]);

  final int total;
  final int page;
  final int pageSize;
  final List<T> items;

  bool get hasMore => page * pageSize < total;
}

class AdminStats {
  const AdminStats({
    required this.admins,
    required this.parents,
    required this.childAccounts,
    required this.lockedAccounts,
    required this.newParents7d,
    required this.children,
    required this.activeChildren,
    required this.activeToday,
    required this.active7d,
    required this.devices,
    required this.publishedVersion,
    required this.words,
    required this.categories,
    required this.sessionsTotal,
    required this.sessions7d,
    required this.minutes7d,
    required this.starsTotal,
    required this.hardestWords,
  });

  factory AdminStats.fromJson(Map<String, dynamic> j) {
    final u = j['users'] as Map<String, dynamic>;
    final c = j['children'] as Map<String, dynamic>;
    final v = j['vocab'] as Map<String, dynamic>;
    final a = j['activity'] as Map<String, dynamic>;
    return AdminStats(
      admins: u['admins'] as int,
      parents: u['parents'] as int,
      childAccounts: u['children'] as int,
      lockedAccounts: u['locked'] as int,
      newParents7d: u['newParentsLast7Days'] as int,
      children: c['total'] as int,
      activeChildren: c['active'] as int,
      activeToday: c['activeToday'] as int,
      active7d: c['activeLast7Days'] as int,
      devices: c['linkedDevices'] as int,
      publishedVersion: v['publishedVersion'] as int?,
      words: v['words'] as int,
      categories: v['categories'] as int,
      sessionsTotal: a['sessionsTotal'] as int,
      sessions7d: a['sessionsLast7Days'] as int,
      minutes7d: a['minutesLast7Days'] as int,
      starsTotal: (a['starsTotal'] as num).toInt(),
      hardestWords: [
        for (final w in j['hardestWords'] as List<dynamic>)
          HardWord.fromJson(w as Map<String, dynamic>),
      ],
    );
  }

  final int admins, parents, childAccounts, lockedAccounts, newParents7d;
  final int children, activeChildren, activeToday, active7d, devices;
  final int? publishedVersion;
  final int words, categories;
  final int sessionsTotal, sessions7d, minutes7d, starsTotal;
  final List<HardWord> hardestWords;
}

class HardWord {
  const HardWord({
    required this.wordId,
    required this.en,
    required this.vi,
    required this.answers,
    required this.wrong,
    required this.wrongRate,
    required this.children,
  });

  factory HardWord.fromJson(Map<String, dynamic> j) => HardWord(
    wordId: j['wordId'] as String,
    en: j['en'] as String,
    vi: j['vi'] as String,
    answers: j['answers'] as int,
    wrong: j['wrong'] as int,
    wrongRate: (j['wrongRate'] as num).toDouble(),
    children: j['children'] as int,
  );

  final String wordId, en, vi;
  final int answers, wrong, children;
  final double wrongRate;
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isActive,
    required this.childCount,
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
    id: j['id'] as String,
    fullName: j['fullName'] as String,
    email: j['email'] as String,
    role: j['role'] as String,
    isActive: j['isActive'] as bool,
    childCount: j['childCount'] as int,
  );

  final String id, fullName, email, role;
  final bool isActive;
  final int childCount;

  bool get isAdmin => role == 'Admin';
}

class AdminCategory {
  const AdminCategory({
    required this.id,
    required this.vi,
    required this.en,
    required this.emoji,
    required this.color,
    required this.sortOrder,
    required this.isDeleted,
    required this.wordCount,
  });

  factory AdminCategory.fromJson(Map<String, dynamic> j) => AdminCategory(
    id: j['id'] as String,
    vi: j['vi'] as String,
    en: j['en'] as String,
    emoji: j['emoji'] as String?,
    color: j['color'] as String?,
    sortOrder: j['sortOrder'] as int,
    isDeleted: j['isDeleted'] as bool,
    wordCount: j['wordCount'] as int,
  );

  final String id, vi, en;
  final String? emoji, color;
  final int sortOrder, wordCount;
  final bool isDeleted;
}

class AdminWord {
  const AdminWord({
    required this.id,
    required this.label,
    required this.en,
    required this.vi,
    required this.phonetic,
    required this.exampleEn,
    required this.exampleVi,
    required this.category,
    required this.audio,
    required this.exampleAudio,
    required this.image,
    required this.emoji,
    required this.hunt,
    required this.isDeleted,
  });

  factory AdminWord.fromJson(Map<String, dynamic> j) => AdminWord(
    id: j['id'] as String,
    label: j['label'] as String?,
    en: j['en'] as String,
    vi: j['vi'] as String,
    phonetic: j['phonetic'] as String,
    exampleEn: j['exampleEn'] as String,
    exampleVi: j['exampleVi'] as String,
    category: j['category'] as String,
    audio: j['audio'] as String,
    exampleAudio: j['exampleAudio'] as String?,
    image: j['image'] as String?,
    emoji: j['emoji'] as String?,
    hunt: j['hunt'] as bool,
    isDeleted: j['isDeleted'] as bool,
  );

  final String id, en, vi, phonetic, exampleEn, exampleVi, category, audio;
  final String? label, exampleAudio, image, emoji;
  final bool hunt, isDeleted;
}

/// Nội dung gửi lên khi tạo/sửa một từ (`WordWriteDto`).
class WordDraft {
  const WordDraft({
    this.id,
    this.label,
    required this.en,
    required this.vi,
    required this.phonetic,
    required this.exampleEn,
    required this.exampleVi,
    required this.category,
    required this.audio,
    this.exampleAudio,
    this.image,
    this.emoji,
    this.hunt = true,
  });

  final String? id, label, exampleAudio, image, emoji;
  final String en, vi, phonetic, exampleEn, exampleVi, category, audio;
  final bool hunt;

  Map<String, dynamic> toJson() => {
    'id': ?id,
    'label': label,
    'en': en,
    'vi': vi,
    'phonetic': phonetic,
    'exampleEn': exampleEn,
    'exampleVi': exampleVi,
    'category': category,
    'audio': audio,
    'exampleAudio': exampleAudio,
    'image': image,
    'emoji': emoji,
    'hunt': hunt,
  };
}

class VocabStatus {
  const VocabStatus({
    required this.publishedVersion,
    required this.hasUnpublishedChanges,
    required this.activeWords,
    required this.activeCategories,
  });

  factory VocabStatus.fromJson(Map<String, dynamic> j) => VocabStatus(
    publishedVersion: j['publishedVersion'] as int?,
    hasUnpublishedChanges: j['hasUnpublishedChanges'] as bool,
    activeWords: j['activeWords'] as int,
    activeCategories: j['activeCategories'] as int,
  );

  final int? publishedVersion;
  final bool hasUnpublishedChanges;
  final int activeWords, activeCategories;
}

class ReleaseInfo {
  const ReleaseInfo(this.version, this.notes, this.wordCount, this.createdAt);

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) => ReleaseInfo(
    j['version'] as int,
    j['notes'] as String?,
    j['wordCount'] as int,
    DateTime.parse(j['createdAt'] as String),
  );

  final int version, wordCount;
  final String? notes;
  final DateTime createdAt;
}

/// Một tệp media đã tải lên (hoặc asset đóng gói sẵn) mà từ có thể dùng.
class MediaItem {
  const MediaItem(this.path, this.size, this.bundled);

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
    j['path'] as String,
    (j['size'] as num).toInt(),
    j['bundled'] as bool,
  );

  final String path;
  final int size;
  final bool bundled;
}

/// Nhãn model nhận ra và từ đang dùng nhãn đó (null = chưa từ nào dùng).
class ModelLabel {
  const ModelLabel(this.label, this.usedBy);

  factory ModelLabel.fromJson(Map<String, dynamic> j) =>
      ModelLabel(j['label'] as String, j['usedBy'] as String?);

  final String label;
  final String? usedBy;
}

/// Một góp ý nhận diện (chỉ chữ, không có ảnh).
class AdminFeedback {
  const AdminFeedback({
    required this.id,
    required this.updatedAt,
    required this.predictedLabel,
    required this.predictedProbability,
    required this.correctWordId,
    required this.correctText,
    required this.source,
  });

  factory AdminFeedback.fromJson(Map<String, dynamic> j) => AdminFeedback(
    id: j['id'] as String,
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    predictedLabel: j['predictedLabel'] as String,
    predictedProbability: (j['predictedProbability'] as num).toDouble(),
    correctWordId: j['correctWordId'] as String?,
    correctText: j['correctText'] as String,
    source: j['source'] as String,
  );

  final String id;
  final DateTime updatedAt;
  final String predictedLabel;
  final double predictedProbability;
  final String? correctWordId;
  final String correctText;
  final String source;

  bool get isConfirmation => correctWordId == predictedLabel;
}

/// Cặp "model đoán X nhưng đúng là Y" và số lần gặp.
class FeedbackPair {
  const FeedbackPair(this.predictedLabel, this.correct, this.count);

  factory FeedbackPair.fromJson(Map<String, dynamic> j) => FeedbackPair(
    j['predictedLabel'] as String,
    j['correct'] as String,
    j['count'] as int,
  );

  final String predictedLabel, correct;
  final int count;
}

class FeedbackText {
  const FeedbackText(this.text, this.count);

  factory FeedbackText.fromJson(Map<String, dynamic> j) =>
      FeedbackText(j['text'] as String, j['count'] as int);

  final String text;
  final int count;
}

class FeedbackSummary {
  const FeedbackSummary({
    required this.total,
    required this.last7Days,
    required this.sameAsPrediction,
    required this.topConfusions,
    required this.unknownWords,
  });

  factory FeedbackSummary.fromJson(Map<String, dynamic> j) => FeedbackSummary(
    total: j['total'] as int,
    last7Days: j['last7Days'] as int,
    sameAsPrediction: j['sameAsPrediction'] as int,
    topConfusions: [
      for (final p in j['topConfusions'] as List<dynamic>)
        FeedbackPair.fromJson(p as Map<String, dynamic>),
    ],
    unknownWords: [
      for (final t in j['unknownWords'] as List<dynamic>)
        FeedbackText.fromJson(t as Map<String, dynamic>),
    ],
  );

  final int total, last7Days, sameAsPrediction;
  final List<FeedbackPair> topConfusions;
  final List<FeedbackText> unknownWords;
}

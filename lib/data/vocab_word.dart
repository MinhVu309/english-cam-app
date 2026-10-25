class VocabCategory {
  const VocabCategory({
    required this.id,
    required this.vi,
    required this.en,
    this.emoji,
  });

  factory VocabCategory.fromJson(Map<String, dynamic> j) => VocabCategory(
    id: j['id'] as String,
    vi: j['vi'] as String,
    en: j['en'] as String,
    emoji: j['emoji'] as String?,
  );

  final String id;
  final String vi;
  final String en;
  final String? emoji;
}

class VocabWord {
  const VocabWord({
    required this.id,
    required this.label,
    required this.en,
    required this.vi,
    required this.phonetic,
    required this.exampleEn,
    required this.exampleVi,
    required this.audio,
    required this.category,
    this.exampleAudio,
    this.image,
    this.emoji,
  });

  factory VocabWord.fromJson(Map<String, dynamic> j) => VocabWord(
    id: j['id'] as String,
    label: j['label'] as String,
    en: j['en'] as String,
    vi: j['vi'] as String,
    phonetic: j['phonetic'] as String,
    exampleEn: j['exampleEn'] as String,
    exampleVi: j['exampleVi'] as String,
    audio: j['audio'] as String,
    exampleAudio: j['exampleAudio'] as String?,
    category: j['category'] as String,
    image: j['image'] as String?,
    emoji: j['emoji'] as String?,
  );

  /// Khoá nội bộ, cũng là tên file âm thanh.
  final String id;

  /// Nhãn đúng như trong labels.txt của model.
  final String label;
  final String en;
  final String vi;
  final String phonetic;
  final String exampleEn;
  final String exampleVi;

  /// Đường dẫn asset mp3 của từ / câu ví dụ.
  final String audio;
  final String? exampleAudio;
  final String category;

  /// Ảnh minh hoạ (asset). Nếu không có thì dùng [emoji], cuối cùng là chữ cái.
  final String? image;
  final String? emoji;
}

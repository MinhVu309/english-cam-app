/// Cách người dùng chọn từ đúng khi sửa kết quả nhận diện (khớp `FeedbackSources` của backend).
enum FeedbackSource { top3, typed }

class FeedbackCandidate {
  const FeedbackCandidate(this.label, this.probability);

  final String label;
  final double probability;

  Map<String, dynamic> toJson() => {'label': label, 'probability': probability};
}

/// Một góp ý "nhận diện sai": model đoán gì, người dùng nói đó là gì. **Chỉ có chữ, không có ảnh chụp.**
/// [id] sinh theo từng ảnh chụp: chọn lại trên cùng ảnh thì cập nhật cùng một góp ý.
class RecognitionFeedback {
  const RecognitionFeedback({
    required this.id,
    required this.predictedLabel,
    required this.predictedProbability,
    required this.top3,
    required this.correctText,
    required this.source,
    this.correctWordId,
    this.modelSource,
    this.vocabVersion,
  });

  factory RecognitionFeedback.fromJson(Map<String, dynamic> j) =>
      RecognitionFeedback(
        id: j['id'] as String,
        predictedLabel: j['predictedLabel'] as String,
        predictedProbability: (j['predictedProbability'] as num).toDouble(),
        top3: [
          for (final c in (j['top3'] as List<dynamic>? ?? const []))
            FeedbackCandidate(
              (c as Map<String, dynamic>)['label'] as String,
              (c['probability'] as num).toDouble(),
            ),
        ],
        correctWordId: j['correctWordId'] as String?,
        correctText: j['correctText'] as String,
        source: FeedbackSource.values.byName(j['source'] as String),
        modelSource: j['modelSource'] as String?,
        vocabVersion: j['vocabVersion'] as int?,
      );

  final String id;
  final String predictedLabel;
  final double predictedProbability;
  final List<FeedbackCandidate> top3;

  /// Mã từ trong từ vựng nếu chọn/gõ đúng một từ có sẵn; null nếu là từ app chưa có.
  final String? correctWordId;
  final String correctText;
  final FeedbackSource source;

  /// "bundled" hoặc "pack" (mô hình đang dùng) và phiên bản từ vựng, để biết góp ý ứng với bản nào.
  final String? modelSource;
  final int? vocabVersion;

  Map<String, dynamic> toJson() => {
    'id': id,
    'predictedLabel': predictedLabel,
    'predictedProbability': predictedProbability,
    'top3': [for (final c in top3) c.toJson()],
    'correctWordId': correctWordId,
    'correctText': correctText,
    'source': source.name,
    'modelSource': modelSource,
    'vocabVersion': vocabVersion,
  };
}

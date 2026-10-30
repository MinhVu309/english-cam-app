import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../mascot/mascot_host.dart';

import '../../core/palette.dart';
import '../../core/router.dart';
import '../../core/uuid.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../data/feedback/recognition_feedback.dart';
import '../../data/vocab_repository.dart';
import '../../data/vocab_word.dart';
import '../../ml/classifier_service.dart';
import '../../services/feedback_service.dart';
import '../../services/pack_watcher.dart';
import '../../services/sync_service.dart';
import '../../ml/object_localizer.dart';
import '../../services/audio_service.dart';
import '../mascot/mascot.dart';
import '../vocab/word_visual.dart';
import 'detection_box_painter.dart';
import 'type_answer_dialog.dart';

/// Pop `true` nếu người dùng muốn chụp lại.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.imagePath, this.classify});

  final String imagePath;

  /// Hàm phân loại ảnh; mặc định chạy model thật. Test truyền kết quả giả (model cần thư viện native).
  final Future<ClassificationResult> Function(String path)? classify;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late Future<ClassificationResult> _future;

  /// Nhãn do bé/phụ huynh chọn lại ở "Không đúng?".
  String? _override;
  bool _showAlternatives = false;

  /// Từ do bé/phụ huynh gõ ở "Khác…" và có trong từ vựng (kể cả từ chỉ để học, chưa có nhãn model).
  VocabWord? _overrideWord;

  /// Chữ đã gõ nhưng app chưa có từ này.
  String? _unknownTyped;

  /// Mã góp ý của ảnh chụp này (chọn lại đáp án thì cập nhật cùng một góp ý) và đã cảm ơn chưa.
  String _photoId = newUuid();
  bool _thanked = false;

  /// Khung quanh vật (ước lượng) và trạng thái đang tìm.
  DetectionBox? _box;
  bool _locating = false;
  int _locateToken = 0;
  bool _disposed = false;

  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
    _future = _classify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _loadImageSize() {
    final stream = FileImage(
      File(widget.imagePath),
    ).resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      if (_disposed) return;
      setState(() {
        _imageSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
      });
    }, onError: (error, stack) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  Future<ClassificationResult> _classify() async {
    final r =
        await (widget.classify ?? ClassifierService.instance.classifyFile)(
          widget.imagePath,
        );
    debugPrint(
      '[perf] classify ${r.inferenceMs}ms best=${r.best.label} '
      'p=${r.best.probability.toStringAsFixed(2)}',
    );
    if (!_disposed && r.isConfident) {
      _locate(r.best.label);
      _speak(r.best.label);
      final word = VocabRepository.instance.byLabel(r.best.label);
      if (word != null) SyncService.instance.recordScan(word.id);
    }
    return r;
  }

  /// Lưu góp ý (vào hàng đợi trên máy, tự gửi lên backend khi có mạng). Chỉ gửi chữ, không gửi ảnh.
  void _sendFeedback(
    ClassificationResult r, {
    required FeedbackSource source,
    required String text,
    String? wordId,
  }) {
    FeedbackService.instance.save(
      RecognitionFeedback(
        id: _photoId,
        predictedLabel: r.best.label,
        predictedProbability: r.best.probability,
        top3: [
          for (final p in r.top) FeedbackCandidate(p.label, p.probability),
        ],
        correctWordId: wordId,
        correctText: text,
        source: source,
        modelSource: ClassifierService.instance.source.name,
        vocabVersion: PackWatcher.instance.currentVersion,
      ),
    );
    if (!_thanked && mounted) setState(() => _thanked = true);
  }

  void _pickSuggestion(ClassificationResult r, Prediction p) {
    final word = VocabRepository.instance.byLabel(p.label);
    setState(() {
      _override = p.label;
      _overrideWord = null;
      _unknownTyped = null;
    });
    _locate(p.label);
    _speak(p.label);
    _sendFeedback(
      r,
      source: FeedbackSource.top3,
      text: word?.en ?? p.label,
      wordId: word?.id,
    );
  }

  /// "Khác…": gõ tên đúng. Khớp một từ trong từ vựng thì hiện từ đó; chưa có thì ghi nhận từ mới để nhóm cân nhắc thêm.
  Future<void> _askOther(ClassificationResult r) async {
    final answer = await showTypeAnswerDialog(context);
    if (answer == null || !mounted) return;
    final word = answer.word;
    setState(() {
      _overrideWord = word;
      _override = word?.label;
      _unknownTyped = word == null ? answer.text : null;
      _box = null;
      _locating = false;
      _locateToken++;
    });
    if (word != null) {
      if (word.label != null) _locate(word.label!);
      AudioService.instance.playWord(word);
    }
    _sendFeedback(
      r,
      source: FeedbackSource.typed,
      text: word?.en ?? answer.text,
      wordId: word?.id,
    );
  }

  /// Tự đọc từ vừa nhận diện.
  void _speak(String label) {
    final word = VocabRepository.instance.byLabel(label);
    if (word != null) AudioService.instance.playWord(word);
  }

  /// Tìm khung quanh vật có nhãn [label] (chạy nền, vẽ khi xong).
  Future<void> _locate(String label) async {
    final token = ++_locateToken;
    setState(() {
      _box = null;
      _locating = true;
    });
    final sw = Stopwatch()..start();
    DetectionBox? box;
    try {
      box = await ObjectLocalizer.instance.localize(
        widget.imagePath,
        label,
        isCancelled: () => _disposed || token != _locateToken,
      );
    } catch (e) {
      debugPrint('Localize failed: $e');
    }
    debugPrint(
      '[perf] locate $label ${sw.elapsedMilliseconds}ms found=${box != null}',
    );
    if (_disposed || token != _locateToken) return;
    setState(() {
      _box = box;
      _locating = false;
    });
  }

  void _retry() {
    setState(() {
      _override = null;
      _overrideWord = null;
      _unknownTyped = null;
      _thanked = false;
      _photoId = newUuid();
      _showAlternatives = false;
      _box = null;
      _locating = false;
      _locateToken++;
      _future = _classify();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MascotHost(
      contextKey: 'result',
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            iconSize: 32,
            tooltip: 'Quay lại',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                Expanded(flex: 5, child: _buildPhoto()),
                const SizedBox(height: 16),
                Expanded(
                  flex: 6,
                  child: FutureBuilder<ClassificationResult>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return _ErrorView(onRetry: _retry);
                      }
                      return _buildResult(snap.data!);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ảnh vừa chụp, có khung vuông quanh vật khi tìm xong.
  Widget _buildPhoto() {
    final size = _imageSize;
    if (size == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final fitted = applyBoxFit(BoxFit.contain, size, box.biggest);
        final w = fitted.destination.width;
        final h = fitted.destination.height;
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5A2B).withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(widget.imagePath), fit: BoxFit.fill),
                    if (_box != null)
                      TweenAnimationBuilder<double>(
                        key: ValueKey(_box),
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, _) => CustomPaint(
                          painter: DetectionBoxPainter(_box!.rect, progress: t),
                        ),
                      ),
                    if (_locating)
                      const Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: _SearchingChip(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResult(ClassificationResult r) {
    final repo = VocabRepository.instance;
    final label = _override ?? (r.isConfident ? r.best.label : null);
    final word = _unknownTyped != null
        ? null
        : (_overrideWord ?? (label == null ? null : repo.byLabel(label)));
    return SingleChildScrollView(
      child: Column(
        children: [
          if (word != null)
            _WordBanner(word: word)
          else if (_unknownTyped != null)
            _UnknownWordCard(text: _unknownTyped!)
          else
            const Column(
              children: [
                Mascot(mood: MascotMood.thinking, size: 72),
                SizedBox(height: 4),
                Text(
                  'Mình chưa chắc, thử chụp lại nhé!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          if (kDebugMode)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${r.inferenceMs} ms · ${r.top.map((p) => '${p.label} ${(p.probability * 100).toStringAsFixed(0)}%').join(', ')}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 16),
          if (_showAlternatives) ...[
            const Text('Đây là gì nhỉ?', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                for (final p in r.top)
                  ChoiceChip(
                    label: Text(
                      repo.byLabel(p.label)?.en ?? p.label,
                      style: const TextStyle(fontSize: 22),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    selected: label == p.label,
                    onSelected: (_) => _pickSuggestion(r, p),
                  ),
                ActionChip(
                  key: const Key('other-answer'),
                  avatar: const Icon(Icons.edit_rounded, size: 24),
                  label: const Text('Khác…', style: TextStyle(fontSize: 22)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  onPressed: () => _askOther(r),
                ),
              ],
            ),
            if (_thanked) const _ThanksNote(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed(Routes.vocab),
              icon: const Icon(Icons.menu_book_rounded),
              label: const Text('Xem tất cả từ vựng'),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Chụp lại'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      setState(() => _showAlternatives = !_showAlternatives),
                  child: const Text('Không đúng?'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lời cảm ơn sau khi bé/phụ huynh sửa kết quả nhận diện.
class _ThanksNote extends StatelessWidget {
  const _ThanksNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        key: const Key('feedback-thanks'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Palette.good,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          children: [
            Icon(Icons.favorite_rounded, size: 28, color: Palette.orange),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cảm ơn bạn! Sự góp ý của bạn là đóng góp lớn cho ứng dụng sau này.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Từ bé/phụ huynh gõ mà app chưa có.
class _UnknownWordCard extends StatelessWidget {
  const _UnknownWordCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('unknown-word'),
      children: [
        const Mascot(mood: MascotMood.cheer, size: 72),
        const SizedBox(height: 4),
        Text(
          '"$text"',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
        ),
        const Text(
          'Mình chưa biết từ này, cảm ơn bạn đã dạy Cam!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22),
        ),
      ],
    );
  }
}

class _SearchingChip extends StatelessWidget {
  const _SearchingChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Đang tìm vật…',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

/// Từ tiếng Anh to, kèm phiên âm và nghĩa; chạm để xem chi tiết.
class _WordBanner extends StatelessWidget {
  const _WordBanner({required this.word});

  final VocabWord word;

  @override
  Widget build(BuildContext context) {
    final tint =
        VocabRepository.instance.category(word.category)?.color ?? Colors.white;
    return BouncyTap(
      semanticLabel: '${word.en}, ${word.vi}. Xem chi tiết',
      color: Color.alphaBlend(Colors.white.withValues(alpha: 0.45), tint),
      borderRadius: 28,
      onTap: () =>
          Navigator.of(context).pushNamed(Routes.vocabDetail, arguments: word),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: WordVisual(word: word, size: 64),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    word.en,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    '${word.phonetic} · ${word.vi}',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              ),
            ),
            IconButton(
              iconSize: 32,
              constraints: const BoxConstraints.tightFor(width: 56, height: 56),
              tooltip: 'Nghe lại',
              icon: const Icon(Icons.volume_up_rounded),
              onPressed: () => AudioService.instance.playWord(word),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Mascot(mood: MascotMood.oops, size: 96),
        const SizedBox(height: 8),
        const Text(
          'Có lỗi rồi, thử lại nhé!',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
      ],
    );
  }
}

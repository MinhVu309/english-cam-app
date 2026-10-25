import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/router.dart';
import '../../data/vocab_repository.dart';
import '../../data/vocab_word.dart';
import '../../ml/classifier_service.dart';
import '../../ml/object_localizer.dart';
import '../../services/audio_service.dart';
import '../vocab/word_visual.dart';
import 'detection_box_painter.dart';

/// Pop `true` nếu người dùng muốn chụp lại.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late Future<ClassificationResult> _future;

  /// Nhãn do bé/phụ huynh chọn lại ở "Không đúng?".
  String? _override;
  bool _showAlternatives = false;

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
    final r = await ClassifierService.instance.classifyFile(widget.imagePath);
    if (!_disposed && r.isConfident) {
      _locate(r.best.label);
      _speak(r.best.label);
    }
    return r;
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
    if (_disposed || token != _locateToken) return;
    setState(() {
      _box = box;
      _locating = false;
    });
  }

  void _retry() {
    setState(() {
      _override = null;
      _showAlternatives = false;
      _box = null;
      _locating = false;
      _locateToken++;
      _future = _classify();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        );
      },
    );
  }

  Widget _buildResult(ClassificationResult r) {
    final repo = VocabRepository.instance;
    final label = _override ?? (r.isConfident ? r.best.label : null);
    final word = label == null ? null : repo.byLabel(label);
    return SingleChildScrollView(
      child: Column(
        children: [
          if (word != null)
            _WordBanner(word: word)
          else
            const Text(
              'Mình chưa chắc, thử chụp lại nhé!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          if (kDebugMode)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${r.inferenceMs} ms · ${r.top.map((p) => '${p.label} ${(p.probability * 100).toStringAsFixed(0)}%').join(', ')}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
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
                    onSelected: (_) {
                      setState(() => _override = p.label);
                      _locate(p.label);
                      _speak(p.label);
                    },
                  ),
              ],
            ),
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
              style: TextStyle(color: Colors.white, fontSize: 16),
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
    return Semantics(
      button: true,
      label: '${word.en}, ${word.vi}. Xem chi tiết',
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(
          context,
        ).pushNamed(Routes.vocabDetail, arguments: word),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              WordVisual(word: word, size: 64),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word.en,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
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
                constraints: const BoxConstraints.tightFor(
                  width: 56,
                  height: 56,
                ),
                tooltip: 'Nghe lại',
                icon: const Icon(Icons.volume_up_rounded),
                onPressed: () => AudioService.instance.playWord(word),
              ),
            ],
          ),
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

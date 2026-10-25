import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/router.dart';
import '../../data/vocab_repository.dart';
import '../../data/vocab_word.dart';
import '../../ml/classifier_service.dart';
import '../camera/captured_photo.dart';
import '../vocab/word_visual.dart';

/// Pop `true` nếu người dùng muốn chụp lại.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.photo});

  final CapturedPhoto photo;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late Future<ClassificationResult> _future;

  /// Nhãn do bé/phụ huynh chọn lại ở "Không đúng?".
  String? _override;
  bool _showAlternatives = false;

  @override
  void initState() {
    super.initState();
    _future = _classify();
  }

  Future<ClassificationResult> _classify() => ClassifierService.instance
      .classifyFile(widget.photo.path, crop: widget.photo.crop);

  void _retry() {
    setState(() {
      _override = null;
      _showAlternatives = false;
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
              Expanded(
                flex: 5,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: _CroppedPhoto(photo: widget.photo),
                    ),
                  ),
                ),
              ),
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
                    onSelected: (_) => setState(() => _override = p.label),
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

/// Hiện đúng vùng khung ngắm mà model đã nhìn.
class _CroppedPhoto extends StatelessWidget {
  const _CroppedPhoto({required this.photo});

  final CapturedPhoto photo;

  @override
  Widget build(BuildContext context) {
    final c = photo.crop;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: ClipRect(
        child: Align(
          alignment: Alignment(
            c.width >= 1 ? 0 : 2 * c.left / (1 - c.width) - 1,
            c.height >= 1 ? 0 : 2 * c.top / (1 - c.height) - 1,
          ),
          widthFactor: c.width,
          heightFactor: c.height,
          child: Image.file(File(photo.path)),
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
              const Icon(Icons.chevron_right_rounded, size: 32),
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

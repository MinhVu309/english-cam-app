import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ml/classifier_service.dart';

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

  @override
  void initState() {
    super.initState();
    _future = ClassifierService.instance.classifyFile(widget.imagePath);
  }

  void _retry() {
    setState(() {
      _override = null;
      _showAlternatives = false;
      _future = ClassifierService.instance.classifyFile(widget.imagePath);
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: SizedBox(
                    width: double.infinity,
                    child: Image.file(
                      File(widget.imagePath),
                      fit: BoxFit.cover,
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
    final label = _override ?? (r.isConfident ? r.best.label : null);
    return SingleChildScrollView(
      child: Column(
        children: [
          if (label != null) ...[
            Text(
              prettyLabel(label),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800),
            ),
          ] else
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
                      prettyLabel(p.label),
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
              onPressed: () => _comingSoon('Danh sách từ vựng'),
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

  void _comingSoon(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what: sắp có nhé!')));
  }
}

/// `teddy_bear` -> `teddy bear`.
String prettyLabel(String label) => label.replaceAll('_', ' ');

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

import 'package:flutter/material.dart';

import '../../data/vocab_word.dart';
import '../../services/progress_service.dart';
import 'word_visual.dart';

class VocabDetailScreen extends StatelessWidget {
  const VocabDetailScreen({super.key, required this.word});

  final VocabWord word;

  void _soon(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Âm thanh sắp có nhé!')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          iconSize: 32,
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Column(
                  children: [
                    WordVisual(word: word, size: 140),
                    const SizedBox(height: 12),
                    Text(
                      word.en,
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      word.phonetic,
                      style: const TextStyle(
                        fontSize: 22,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      word.vi,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _soon(context),
                      icon: const Icon(Icons.volume_up_rounded, size: 28),
                      label: const Text('Nghe'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word.exampleEn,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      word.exampleVi,
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListenableBuilder(
                listenable: ProgressService.instance,
                builder: (context, _) {
                  final learned = ProgressService.instance.isLearned(word.id);
                  return SizedBox(
                    width: double.infinity,
                    child: learned
                        ? OutlinedButton.icon(
                            onPressed: () => ProgressService.instance
                                .setLearned(word.id, false),
                            icon: const Text(
                              '⭐',
                              style: TextStyle(fontSize: 24),
                            ),
                            label: const Text('Đã học rồi!'),
                          )
                        : FilledButton.icon(
                            onPressed: () => ProgressService.instance
                                .setLearned(word.id, true),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Mình đã học từ này'),
                          ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

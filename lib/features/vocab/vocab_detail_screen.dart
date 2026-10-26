import 'package:flutter/material.dart';

import '../mascot/mascot_host.dart';

import '../../data/vocab_repository.dart';
import '../../data/vocab_word.dart';
import '../../services/audio_service.dart';
import '../../services/progress_service.dart';
import 'word_visual.dart';

class VocabDetailScreen extends StatelessWidget {
  const VocabDetailScreen({super.key, required this.word});

  final VocabWord word;

  @override
  Widget build(BuildContext context) {
    return MascotHost(
      contextKey: 'vocab_detail',
      child: Scaffold(
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
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        VocabRepository.instance
                                .category(word.category)
                                ?.color ??
                            Colors.white,
                        Colors.white,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5A2B).withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
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
                        onPressed: () => AudioService.instance.playWord(word),
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
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5A2B).withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              word.exampleEn,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton.filledTonal(
                            iconSize: 28,
                            constraints: const BoxConstraints.tightFor(
                              width: 56,
                              height: 56,
                            ),
                            tooltip: 'Nghe câu ví dụ',
                            icon: const Icon(Icons.volume_up_rounded),
                            onPressed: () =>
                                AudioService.instance.playExample(word),
                          ),
                        ],
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
                              onPressed: () {
                                ProgressService.instance.setLearned(
                                  word.id,
                                  true,
                                );
                                AudioService.instance.playSfx(Sfx.star);
                              },
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
      ),
    );
  }
}

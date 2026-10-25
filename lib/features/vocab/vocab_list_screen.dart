import 'package:flutter/material.dart';

import '../../core/router.dart';
import '../../data/vocab_repository.dart';
import '../../data/vocab_word.dart';
import '../../services/progress_service.dart';
import 'word_visual.dart';

class VocabListScreen extends StatefulWidget {
  const VocabListScreen({super.key});

  @override
  State<VocabListScreen> createState() => _VocabListScreenState();
}

class _VocabListScreenState extends State<VocabListScreen> {
  final _repo = VocabRepository.instance;
  final _search = TextEditingController();
  String? _category; // null = tất cả
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<VocabWord> get _filtered {
    final q = _query.trim().toLowerCase();
    return [
      for (final w in _repo.words)
        if ((_category == null || w.category == _category) &&
            (q.isEmpty ||
                w.en.toLowerCase().contains(q) ||
                w.vi.toLowerCase().contains(q)))
          w,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Từ vựng',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          iconSize: 32,
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          ListenableBuilder(
            listenable: ProgressService.instance,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '⭐ ${ProgressService.instance.learnedCount}/${_repo.words.length}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                style: const TextStyle(fontSize: 20),
                decoration: InputDecoration(
                  hintText: 'Tìm từ…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Xoá',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip('Tất cả', null),
                  for (final c in _repo.categories)
                    _chip('${c.emoji ?? ''} ${c.vi}'.trim(), c.id),
                ],
              ),
            ),
            Expanded(child: _buildGrid()),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String? id) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 18)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        selected: _category == id,
        onSelected: (_) => setState(() => _category = id),
      ),
    );
  }

  Widget _buildGrid() {
    final words = _filtered;
    if (words.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Chưa tìm thấy từ nào.\nThử gõ từ khác nhé!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: ProgressService.instance,
      builder: (context, _) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.9,
        ),
        itemCount: words.length,
        itemBuilder: (context, i) => _WordCard(
          word: words[i],
          learned: ProgressService.instance.isLearned(words[i].id),
        ),
      ),
    );
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.word, required this.learned});

  final VocabWord word;
  final bool learned;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${word.en}, ${word.vi}${learned ? ', đã học' : ''}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Navigator.of(
            context,
          ).pushNamed(Routes.vocabDetail, arguments: word),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WordVisual(word: word, size: 80),
                    const SizedBox(height: 8),
                    Text(
                      word.en,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(word.vi, style: const TextStyle(fontSize: 18)),
                  ],
                ),
              ),
              if (learned)
                const Positioned(
                  top: 8,
                  right: 12,
                  child: Text('⭐', style: TextStyle(fontSize: 24)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

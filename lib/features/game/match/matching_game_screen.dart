import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../data/game_badge.dart';
import '../../../data/vocab_repository.dart';
import '../../../data/vocab_word.dart';
import '../../../services/audio_service.dart';
import '../../../services/game_progress.dart';
import '../../mascot/mascot.dart';
import '../../vocab/word_visual.dart';
import '../badge_dialog.dart';
import 'match_questions.dart';

/// Game 1: app đọc một từ, bé chọn hình đúng. Sai thì khuyến khích và cho thử lại.
class MatchingGameScreen extends StatefulWidget {
  const MatchingGameScreen({super.key, this.random});

  /// Cho phép test cố định thứ tự câu hỏi.
  final Random? random;

  @override
  State<MatchingGameScreen> createState() => _MatchingGameScreenState();
}

class _MatchingGameScreenState extends State<MatchingGameScreen> {
  late List<MatchQuestion> _questions;
  int _index = 0;

  /// Số câu đúng ngay lần chọn đầu tiên = số sao của ván này.
  int _stars = 0;

  /// Đáp án bé đã chọn sai ở câu hiện tại.
  final Set<String> _wrong = {};
  String? _correctId;
  bool _finished = false;
  List<GameBadge> _newBadges = const [];
  Timer? _timer;

  MatchQuestion get _question => _questions[_index];

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _newRound() {
    _timer?.cancel();
    final pool = matchPool(VocabRepository.instance.words);
    setState(() {
      _questions = buildMatchQuestions(pool, widget.random ?? Random());
      _index = 0;
      _stars = 0;
      _wrong.clear();
      _correctId = null;
      _finished = false;
      _newBadges = const [];
    });
    _speak();
  }

  void _speak() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), () {
      AudioService.instance.playWord(_question.target);
    });
  }

  void _choose(VocabWord word) {
    if (_correctId != null || _wrong.contains(word.id)) return;
    if (word.id == _question.target.id) {
      if (_wrong.isEmpty) _stars++;
      AudioService.instance.playSfx(Sfx.correct);
      setState(() => _correctId = word.id);
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 1300), _next);
    } else {
      AudioService.instance.playSfx(Sfx.wrong);
      setState(() => _wrong.add(word.id));
      // Đọc lại từ để bé nghe kỹ hơn rồi thử lại.
      _speak();
    }
  }

  Future<void> _next() async {
    if (_index + 1 < _questions.length) {
      setState(() {
        _index++;
        _wrong.clear();
        _correctId = null;
      });
      _speak();
      return;
    }
    final badges = await GameProgress.instance.recordRound(
      starsEarned: _stars,
      perfect: _stars == _questions.length,
    );
    if (!mounted) return;
    setState(() {
      _finished = true;
      _newBadges = badges;
    });
    AudioService.instance.playSfx(Sfx.star);
    if (badges.isNotEmpty) showBadgeDialog(context, badges);
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
        title: _finished
            ? null
            : Text(
                '${_index + 1}/${_questions.length}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
        actions: [
          if (!_finished)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '⭐ $_stars',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(child: _finished ? _buildSummary() : _buildQuestion()),
    );
  }

  Widget _buildQuestion() {
    final q = _question;
    final solved = _correctId != null;
    final message = solved
        ? 'Giỏi quá!'
        : _wrong.isNotEmpty
        ? 'Chưa đúng, thử lại nhé!'
        : 'Nghe và chọn hình đúng';
    final mood = solved
        ? MascotMood.cheer
        : _wrong.isNotEmpty
        ? MascotMood.oops
        : MascotMood.happy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Semantics(
            button: true,
            label: 'Nghe lại',
            child: Material(
              color: Theme.of(context).colorScheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _speak,
                child: const Padding(
                  padding: EdgeInsets.all(22),
                  child: Icon(
                    Icons.volume_up_rounded,
                    size: 56,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Mascot(mood: mood, size: 72),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final w in q.options)
                  _OptionCard(
                    word: w,
                    isCorrect: _correctId == w.id,
                    isWrong: _wrong.contains(w.id),
                    revealText: solved && w.id == q.target.id,
                    onTap: () => _choose(w),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final total = _questions.length;
    final ratio = _stars / total;
    final message = ratio >= 0.85
        ? 'Siêu đỉnh luôn!'
        : ratio >= 0.5
        ? 'Giỏi lắm!'
        : 'Cố lên nhé, lần sau sẽ giỏi hơn!';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Mascot(mood: MascotMood.cheer, size: 180),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            '⭐ $_stars / $total',
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
          ),
          if (_newBadges.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Huy hiệu mới: ${_newBadges.map((b) => '${b.emoji} ${b.name}').join(', ')}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _newRound,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Chơi tiếp'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Xong'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.word,
    required this.isCorrect,
    required this.isWrong,
    required this.revealText,
    required this.onTap,
  });

  final VocabWord word;
  final bool isCorrect;
  final bool isWrong;
  final bool revealText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isCorrect
        ? const Color(0xFFBFE8C8)
        : isWrong
        ? const Color(0xFFFFE0CC)
        : Colors.white;
    return Semantics(
      button: true,
      label: isCorrect ? '${word.en}, đúng' : 'Đáp án',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isWrong ? 0.5 : 1,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: isWrong ? null : onTap,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WordVisual(word: word, size: 96),
                  if (revealText) ...[
                    const SizedBox(height: 6),
                    Text(
                      word.en,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

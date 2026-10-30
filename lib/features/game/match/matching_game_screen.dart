import 'dart:async';
import 'dart:math';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../mascot/mascot_host.dart';

import '../../../core/palette.dart';
import '../../../core/widgets/bouncy_tap.dart';
import '../../../core/widgets/confetti.dart';
import '../../../data/game_badge.dart';
import '../../../data/vocab_repository.dart';
import '../../../data/vocab_word.dart';
import '../../../services/audio_service.dart';
import '../../../services/game_progress.dart';
import '../../../services/sync_service.dart';
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
  List<MatchQuestion> _questions = const [];
  int _index = 0;

  /// Đang chờ máy chủ chọn câu hỏi (chỉ khi bé đã đăng nhập).
  bool _loading = false;

  /// Số lần bé chọn ở từng câu đã xong, để máy chủ tự tính sao và cập nhật độ thuộc từ.
  final List<MatchAnswer> _results = [];
  DateTime _startedAt = DateTime.now();

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

  List<MatchQuestion> _localQuestions() => buildMatchQuestions(
    matchPool(VocabRepository.instance.words),
    widget.random ?? Random(),
  );

  /// Câu hỏi máy chủ chọn → [MatchQuestion]. Thiếu từ nào (bản từ vựng trên máy cũ hơn) thì bỏ cả bộ, dùng câu hỏi cục bộ.
  List<MatchQuestion>? _fromServer(List<ServerQuestion>? server) {
    if (server == null || server.isEmpty) return null;
    final repo = VocabRepository.instance;
    final out = <MatchQuestion>[];
    for (final q in server) {
      final target = repo.byId(q.target);
      final options = [for (final id in q.options) repo.byId(id)];
      if (target == null ||
          options.length < 2 ||
          options.any((w) => w == null || !w.hasPicture) ||
          !options.any((w) => w!.id == target.id)) {
        return null;
      }
      out.add(MatchQuestion(target, [for (final w in options) w!]));
    }
    return out;
  }

  void _newRound() {
    _timer?.cancel();
    // Khách: tạo câu hỏi ngay trên máy như trước. Đã đăng nhập: nhờ máy chủ chọn theo độ thuộc từ của bé,
    // quá 3 giây hoặc lỗi thì tự tạo (bé không phải chờ máy chủ "ngủ" dậy).
    if (!SyncService.instance.active) {
      _startRound(_localQuestions());
      return;
    }
    setState(() {
      _loading = true;
      _finished = false;
    });
    SyncService.instance.fetchMatchQuestions(kMatchQuestions).then((server) {
      if (mounted) _startRound(_fromServer(server) ?? _localQuestions());
    });
  }

  void _startRound(List<MatchQuestion> questions) {
    setState(() {
      _questions = questions;
      _loading = false;
      _index = 0;
      _stars = 0;
      _wrong.clear();
      _results.clear();
      _startedAt = DateTime.now();
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
      _results.add(MatchAnswer(word.id, _wrong.length + 1));
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
    SyncService.instance.recordMatchRound(
      startedAt: _startedAt,
      durationSec: DateTime.now().difference(_startedAt).inSeconds,
      answers: List.of(_results),
      stars: _stars,
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
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            iconSize: 32,
            tooltip: 'Quay lại',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return MascotHost(
      contextKey: 'match',
      child: Scaffold(
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
        body: SafeArea(
          child: _finished
              ? Stack(
                  children: [
                    _buildSummary(),
                    const Positioned.fill(child: ConfettiBurst()),
                  ],
                )
              : _buildQuestion(),
        ),
      ),
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
                for (var i = 0; i < q.options.length; i++)
                  _OptionCard(
                    key: ValueKey('option-${q.options[i].id}'),
                    word: q.options[i],
                    tint: _tints[i % _tints.length],
                    isCorrect: _correctId == q.options[i].id,
                    isWrong: _wrong.contains(q.options[i].id),
                    revealText: solved && q.options[i].id == q.target.id,
                    onTap: () => _choose(q.options[i]),
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

/// Bốn màu pastel xoay vòng cho bốn đáp án.
const _tints = [
  Color(0xFFFFE3CC),
  Color(0xFFD7F0E8),
  Color(0xFFE5DEFA),
  Color(0xFFFFF0B8),
];

class _OptionCard extends StatefulWidget {
  const _OptionCard({
    super.key,
    required this.word,
    required this.tint,
    required this.isCorrect,
    required this.isWrong,
    required this.revealText,
    required this.onTap,
  });

  final VocabWord word;
  final Color tint;
  final bool isCorrect;
  final bool isWrong;
  final bool revealText;
  final VoidCallback onTap;

  @override
  State<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<_OptionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_OptionCard old) {
    super.didUpdateWidget(old);
    final reduce =
        !Mascot.animationsEnabled || MediaQuery.of(context).disableAnimations;
    // Lắc nhẹ khi vừa chọn sai (không lắc nếu bé bật "giảm chuyển động").
    if (widget.isWrong && !old.isWrong && !reduce) _shake.forward(from: 0);
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final color = widget.isCorrect
        ? Palette.good
        : widget.isWrong
        ? Palette.oops
        : widget.tint;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 5) * 12 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: AnimatedScale(
        scale: widget.isCorrect ? 1.06 : 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.isWrong ? 0.5 : 1,
          child: BouncyTap(
            semanticLabel: widget.isCorrect ? '${word.en}, đúng' : 'Đáp án',
            color: color,
            borderRadius: 30,
            shadowColor: widget.isCorrect ? Palette.leaf : null,
            onTap: widget.isWrong ? null : widget.onTap,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: WordVisual(word: word, size: 96),
                  ),
                  if (widget.revealText) ...[
                    const SizedBox(height: 6),
                    // Từ dài (kể cả từ tải từ gói cập nhật) co lại thay vì xuống dòng và tràn thẻ.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        word.en,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
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

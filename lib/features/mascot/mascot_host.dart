import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/vocab_repository.dart';
import '../../services/app_settings.dart';
import '../../services/audio_service.dart';
import '../../services/game_progress.dart';
import '../../services/progress_service.dart';
import 'mascot.dart';
import 'mascot_messages.dart';
import 'speech_bubble.dart';

/// Phủ lên một màn hình để Cam "lâu lâu" trượt ra góc màn hình và nhắn bé một
/// câu hợp ngữ cảnh ([contextKey] trong assets/mascot/messages.json), rồi tự
/// rút đi. Chạm vào Cam để nghe câu khác. Bố mẹ tắt được trong Cài đặt.
class MascotHost extends StatefulWidget {
  const MascotHost({
    super.key,
    required this.contextKey,
    required this.child,
    this.alignment = Alignment.bottomRight,
    this.margin = const EdgeInsets.all(12),
    this.firstDelay = const Duration(seconds: 9),
    this.minGap = const Duration(seconds: 24),
    this.maxGap = const Duration(seconds: 42),
    this.visibleFor = const Duration(seconds: 7),
    this.mascotSize = 76,
    this.random,
  });

  final String contextKey;
  final Widget child;

  /// Góc Cam xuất hiện (bottomRight, bottomLeft, topRight…).
  final Alignment alignment;
  final EdgeInsets margin;

  /// Lần hiện đầu tiên sau khi mở màn hình, rồi cách nhau ngẫu nhiên [minGap]–[maxGap].
  final Duration firstDelay;
  final Duration minGap;
  final Duration maxGap;
  final Duration visibleFor;
  final double mascotSize;
  final Random? random;

  /// Tắt toàn cục việc tự hiện (dùng trong test để không có timer treo).
  static bool autoEnabled = true;

  /// Cho màn hình bên dưới bắt Cam nói ngay (vd. sau một sự kiện).
  static MascotHostState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<MascotHostState>();

  @override
  State<MascotHost> createState() => MascotHostState();
}

class MascotHostState extends State<MascotHost> {
  late final Random _rng = widget.random ?? Random();
  Timer? _showTimer;
  Timer? _hideTimer;
  MascotLine? _line;
  String? _last;

  bool get _active =>
      MascotHost.autoEnabled && AppSettings.instance.mascotChatter;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onSettings);
    if (_active) _scheduleNext(widget.firstDelay);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettings);
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onSettings() {
    if (!mounted) return;
    if (_active) {
      if (_showTimer == null && _line == null) _scheduleNext(widget.firstDelay);
    } else {
      _showTimer?.cancel();
      _showTimer = null;
      _hideTimer?.cancel();
      setState(() => _line = null);
    }
  }

  MascotContext _info() => MascotContext(
    learned: ProgressService.instance.learnedCount,
    stars: GameProgress.instance.stars,
    total: _safeTotal(),
  );

  int _safeTotal() {
    try {
      return VocabRepository.instance.words.length;
    } catch (_) {
      return 24;
    }
  }

  void _scheduleNext(Duration delay) {
    _showTimer?.cancel();
    _showTimer = Timer(delay, () {
      _showTimer = null;
      if (!mounted || !_active) return;
      if (!_appear()) _scheduleNext(_randomGap());
    });
  }

  Duration _randomGap() {
    final span = widget.maxGap.inMilliseconds - widget.minGap.inMilliseconds;
    return Duration(
      milliseconds:
          widget.minGap.inMilliseconds + (span > 0 ? _rng.nextInt(span) : 0),
    );
  }

  /// Chọn và hiện một câu; trả về false nếu không có câu nào hợp.
  bool _appear() {
    final line = MascotMessages.instance.pick(
      widget.contextKey,
      _rng,
      info: _info(),
      avoid: _last,
    );
    if (line == null) return false;
    say(line);
    return true;
  }

  /// Cho Cam nói [line] ngay và tự rút sau [MascotHost.visibleFor].
  void say(MascotLine line) {
    if (!mounted) return;
    _last = line.text;
    setState(() => _line = line);
    AudioService.instance.playSfx(Sfx.tap);
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.visibleFor, _hide);
  }

  void _hide() {
    if (!mounted) return;
    setState(() => _line = null);
    if (_active) _scheduleNext(_randomGap());
  }

  void _onTapMascot() {
    final line = MascotMessages.instance.pick(
      widget.contextKey,
      _rng,
      info: _info(),
      avoid: _last,
    );
    if (line != null) say(line);
  }

  @override
  Widget build(BuildContext context) {
    final line = _line;
    final onRight = widget.alignment.x >= 0;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: SafeArea(
            child: Align(
              alignment: widget.alignment,
              child: Padding(
                padding: widget.margin,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: Offset(onRight ? 0.4 : -0.4, 0.3),
                        end: Offset.zero,
                      ).animate(animation),
                      child: ScaleTransition(
                        scale: animation,
                        alignment: widget.alignment,
                        child: child,
                      ),
                    ),
                  ),
                  child: line == null
                      ? const SizedBox.shrink(key: ValueKey('mascot-hidden'))
                      : _Appearance(
                          key: ValueKey(line.text),
                          line: line,
                          onRight: onRight,
                          size: widget.mascotSize,
                          onTap: _onTapMascot,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Appearance extends StatelessWidget {
  const _Appearance({
    super.key,
    required this.line,
    required this.onRight,
    required this.size,
    required this.onTap,
  });

  final MascotLine line;
  final bool onRight;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Cam nói: ${line.text}',
      button: true,
      onTapHint: 'Nghe câu khác',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: onRight
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: SpeechBubble(text: line.text, tailOnRight: onRight),
            ),
            Mascot(mood: line.mood, size: size),
          ],
        ),
      ),
    );
  }
}

/// Dải Cam + bong bóng nằm cố định trong trang (dùng ở Home): Cam luôn có mặt và
/// đổi câu nhắn mỗi ít giây hoặc khi bé chạm vào.
class MascotStrip extends StatefulWidget {
  const MascotStrip({
    super.key,
    this.contextKey = 'home',
    this.every = const Duration(seconds: 14),
    this.random,
  });

  final String contextKey;
  final Duration every;
  final Random? random;

  @override
  State<MascotStrip> createState() => _MascotStripState();
}

class _MascotStripState extends State<MascotStrip> {
  late final Random _rng = widget.random ?? Random();
  Timer? _timer;
  MascotLine? _line;

  MascotContext _info() => MascotContext(
    learned: ProgressService.instance.learnedCount,
    stars: GameProgress.instance.stars,
  );

  @override
  void initState() {
    super.initState();
    _next();
    if (MascotHost.autoEnabled) {
      _timer = Timer.periodic(widget.every, (_) {
        if (AppSettings.instance.mascotChatter) _next();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _next() {
    final line = MascotMessages.instance.pick(
      widget.contextKey,
      _rng,
      info: _info(),
      avoid: _line?.text,
    );
    if (line != null && mounted) {
      setState(() => _line = line);
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = _line;
    return Semantics(
      liveRegion: true,
      button: true,
      label: line == null ? 'Cam' : 'Cam nói: ${line.text}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AudioService.instance.playSfx(Sfx.tap);
          _next();
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Mascot(mood: line?.mood ?? MascotMood.happy, size: 84),
            const SizedBox(width: 4),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0.1, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: line == null
                    ? const SizedBox.shrink()
                    : Align(
                        key: ValueKey(line.text),
                        alignment: Alignment.centerLeft,
                        child: ExcludeSemantics(
                          child: SpeechBubble(
                            text: line.text,
                            tailOnRight: false,
                            maxWidth: 270,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

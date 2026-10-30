import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/router.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../data/vocab_repository.dart';
import '../../services/audio_service.dart';
import '../../services/game_progress.dart';
import '../../services/progress_service.dart';
import '../../services/auth_service.dart';
import '../account/account_widgets.dart';
import '../mascot/mascot.dart';
import '../mascot/mascot_host.dart';
import '../settings/parent_gate.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Camera -> kết quả; "Chụp lại" ở màn kết quả quay về camera.
  Future<void> _openCamera(BuildContext context) async {
    final navigator = Navigator.of(context);
    while (true) {
      final path = await navigator.pushNamed<String>(Routes.camera);
      if (path == null || !navigator.mounted) return;
      final retake = await navigator.pushNamed<bool>(
        Routes.result,
        arguments: path,
      );
      if (retake != true) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      _HomeCard(
        icon: Icons.photo_camera_rounded,
        label: 'Chụp & Học',
        subtitle: 'Chụp đồ vật, nghe tên tiếng Anh',
        colors: const [Palette.orange, Color(0xFFC94A08)],
        onTap: () => _openCamera(context),
      ),
      _HomeCard(
        icon: Icons.menu_book_rounded,
        label: 'Từ vựng',
        subtitle: '${VocabRepository.instance.words.length} từ để xem và nghe',
        colors: const [Palette.teal, Color(0xFF166A5E)],
        onTap: () => Navigator.of(context).pushNamed(Routes.vocab),
      ),
      _HomeCard(
        icon: Icons.sports_esports_rounded,
        label: 'Chơi',
        subtitle: 'Game vui, gom sao & huy hiệu',
        colors: const [Palette.purple, Color(0xFF4B3CAE)],
        onTap: () => Navigator.of(context).pushNamed(Routes.games),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              Row(
                children: [
                  const _SettingsButton(),
                  Expanded(
                    child: Center(
                      child: Text(
                        'English Cam',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const _MusicButton(),
                ],
              ),
              const _ProfileChip(),
              const SizedBox(height: 10),
              const _StatsRow(),
              const SizedBox(height: 8),
              const MascotStrip(),
              const SizedBox(height: 10),
              for (var i = 0; i < cards.length; i++) ...[
                Expanded(
                  child: _Entrance(index: i, child: cards[i]),
                ),
                if (i < cards.length - 1) const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Thẻ trượt lên và hiện dần lần lượt khi mở màn hình.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce =
        !Mascot.animationsEnabled || MediaQuery.of(context).disableAnimations;
    if (reduce) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + index * 140),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 40),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// ⭐ số sao và 📚 số từ đã học.
class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GameProgress.instance,
        ProgressService.instance,
      ]),
      builder: (context, _) {
        final total = VocabRepository.instance.words.length;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StatChip(emoji: '⭐', text: '${GameProgress.instance.stars} sao'),
            const SizedBox(width: 12),
            _StatChip(
              emoji: '📚',
              text: '${ProgressService.instance.learnedCount}/$total từ',
            ),
          ],
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.emoji, required this.text});

  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5A2B).withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyTap(
      semanticLabel: '$label. $subtitle',
      borderRadius: 32,
      shadowColor: colors.last,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
      onTap: () {
        AudioService.instance.playSfx(Sfx.tap);
        onTap();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            // Hình mờ lớn làm điểm nhấn.
            Positioned(
              right: -18,
              bottom: -22,
              child: ExcludeSemantics(
                child: Icon(
                  icon,
                  size: 150,
                  color: Colors.white.withValues(alpha: 0.13),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 40, color: colors.first),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 36,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bật/tắt nhạc nền; trạng thái được lưu lại.
class _MusicButton extends StatelessWidget {
  const _MusicButton();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioService.instance.musicOn,
      builder: (context, on, _) => IconButton.filledTonal(
        iconSize: 28,
        constraints: const BoxConstraints.tightFor(width: 56, height: 56),
        tooltip: on ? 'Tắt nhạc' : 'Bật nhạc',
        icon: Icon(on ? Icons.music_note_rounded : Icons.music_off_rounded),
        onPressed: () => AudioService.instance.setMusicOn(!on),
      ),
    );
  }
}

/// Mở Cài đặt, nhưng phải qua cổng phụ huynh.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton();

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      iconSize: 28,
      constraints: const BoxConstraints.tightFor(width: 56, height: 56),
      tooltip: 'Cài đặt (dành cho bố mẹ)',
      icon: const Icon(Icons.settings_rounded),
      onPressed: () async {
        final ok = await showParentGate(context);
        if (ok && context.mounted) {
          Navigator.of(context).pushNamed(Routes.settings);
        }
      },
    );
  }
}

/// Cho biết ai đang dùng máy khi đã đăng nhập (khách thì không hiện gì):
/// bé → hình + biệt danh; phụ huynh chưa chọn bé → nút "Chọn bé" (qua cổng phụ huynh).
class _ProfileChip extends StatelessWidget {
  const _ProfileChip();

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (auth.isGuest) return const SizedBox.shrink();
        final child = auth.activeChild;
        final Widget chip;
        if (child != null) {
          chip = _chip(avatarEmoji(child.avatarKey), child.nickname);
        } else {
          chip = InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () async {
              final navigator = Navigator.of(context);
              if (!await showParentGate(context)) return;
              await navigator.pushNamed(auth.landingRoute);
            },
            child: _chip(
              auth.isAdmin ? '🛠️' : '👨‍👩‍👧',
              auth.isAdmin ? 'Quản trị' : 'Chọn bé',
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Center(child: chip),
        );
      },
    );
  }

  Widget _chip(String emoji, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

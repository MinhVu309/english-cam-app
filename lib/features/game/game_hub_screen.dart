import 'package:flutter/material.dart';

import '../mascot/mascot_host.dart';

import '../../core/palette.dart';
import '../../core/router.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../data/game_badge.dart';
import '../../services/audio_service.dart';
import '../../services/game_progress.dart';
import 'badge_dialog.dart';

/// Màn "Chơi": chọn game, xem sao và huy hiệu.
class GameHubScreen extends StatefulWidget {
  const GameHubScreen({super.key});

  @override
  State<GameHubScreen> createState() => _GameHubScreenState();
}

class _GameHubScreenState extends State<GameHubScreen> {
  @override
  void initState() {
    super.initState();
    // Từ đã học có thể đã đủ điều kiện mở huy hiệu "Chăm học".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final unlocked = GameProgress.instance.checkBadges();
      if (unlocked.isNotEmpty) showBadgeDialog(context, unlocked);
    });
  }

  @override
  Widget build(BuildContext context) {
    final badges = BadgeRepository.instance.badges;
    return MascotHost(
      contextKey: 'hub',
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            iconSize: 32,
            tooltip: 'Quay lại',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const Text(
            'Chơi',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          actions: [
            ListenableBuilder(
              listenable: GameProgress.instance,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '⭐ ${GameProgress.instance.stars}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                _GameButton(
                  emoji: '👂',
                  title: 'Nghe & chọn hình',
                  subtitle: 'Nghe từ rồi chọn hình đúng',
                  colors: const [Palette.purple, Color(0xFF4B3CAE)],
                  onTap: () =>
                      Navigator.of(context).pushNamed(Routes.matchGame),
                ),
                const SizedBox(height: 14),
                _GameButton(
                  emoji: '🔍',
                  title: 'Tìm vật',
                  subtitle: 'Đi tìm đồ vật thật và chụp',
                  colors: const [Palette.orange, Color(0xFFC94A08)],
                  onTap: () => Navigator.of(context).pushNamed(Routes.huntGame),
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Huy hiệu của bé',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListenableBuilder(
                    listenable: GameProgress.instance,
                    builder: (context, _) => GridView.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: [
                        for (final b in badges)
                          _BadgeTile(
                            badge: b,
                            unlocked: GameProgress.instance.hasBadge(b.id),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GameButton extends StatelessWidget {
  const _GameButton({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyTap(
      semanticLabel: '$title. $subtitle',
      borderRadius: 30,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
        child: Row(
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: ExcludeSemantics(
                child: Text(emoji, style: const TextStyle(fontSize: 44)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
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
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.unlocked});

  final GameBadge badge;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return BouncyTap(
      semanticLabel:
          '${badge.name}. ${badge.description}. ${unlocked ? 'Đã có' : 'Chưa có'}',
      borderRadius: 22,
      color: unlocked ? const Color(0xFFFFF3C4) : const Color(0xFFEDE6DC),
      shadowColor: unlocked ? Palette.star : Colors.black54,
      onTap: () => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${badge.name}: ${badge.description}')),
        ),
      child: Center(
        child: ExcludeSemantics(
          child: Text(
            unlocked ? badge.emoji : '🔒',
            style: TextStyle(
              fontSize: 38,
              color: unlocked ? null : Colors.black38,
            ),
          ),
        ),
      ),
    );
  }
}

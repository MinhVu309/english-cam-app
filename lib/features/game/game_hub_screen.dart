import 'package:flutter/material.dart';

import '../../core/router.dart';
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
    return Scaffold(
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
                color: const Color(0xFF7C6FE0),
                onTap: () => Navigator.of(context).pushNamed(Routes.matchGame),
              ),
              const SizedBox(height: 14),
              _GameButton(
                emoji: '🔍',
                title: 'Tìm vật',
                color: const Color(0xFFFF8A3D),
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
    );
  }
}

class _GameButton extends StatelessWidget {
  const _GameButton({
    required this.emoji,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () {
            AudioService.instance.playSfx(Sfx.tap);
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Text(emoji, style: const TextStyle(fontSize: 52)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
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
    return Semantics(
      button: true,
      label:
          '${badge.name}. ${badge.description}. ${unlocked ? 'Đã có' : 'Chưa có'}',
      child: Material(
        color: unlocked ? Colors.white : Colors.black12,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
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
                  fontSize: 36,
                  color: unlocked ? null : Colors.black38,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

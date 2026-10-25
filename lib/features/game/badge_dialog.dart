import 'package:flutter/material.dart';

import '../../data/game_badge.dart';
import '../../services/audio_service.dart';

/// Hộp thoại chúc mừng khi mở khoá huy hiệu mới.
Future<void> showBadgeDialog(BuildContext context, List<GameBadge> badges) {
  AudioService.instance.playSfx(Sfx.star);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      title: const Text(
        'Huy hiệu mới! 🎉',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final b in badges)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(b.emoji, style: const TextStyle(fontSize: 64)),
                  Text(
                    b.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    b.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tuyệt vời!'),
        ),
      ],
    ),
  );
}

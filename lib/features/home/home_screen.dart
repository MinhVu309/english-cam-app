import 'package:flutter/material.dart';

import '../../core/router.dart';
import '../../services/audio_service.dart';

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

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Sắp có nhé!')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 56),
                  Expanded(
                    child: Text(
                      'English Cam',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const _MusicButton(),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _BigButton(
                  icon: Icons.photo_camera_rounded,
                  label: 'Chụp & Học',
                  color: const Color(0xFFFF8A3D),
                  onTap: () => _openCamera(context),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _BigButton(
                  icon: Icons.menu_book_rounded,
                  label: 'Từ vựng',
                  color: const Color(0xFF4CB8A8),
                  onTap: () => Navigator.of(context).pushNamed(Routes.vocab),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _BigButton(
                  icon: Icons.sports_esports_rounded,
                  label: 'Chơi',
                  color: const Color(0xFF7C6FE0),
                  onTap: () => _comingSoon(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(32),
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: () {
            AudioService.instance.playSfx(Sfx.tap);
            onTap();
          },
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 64, color: Colors.white),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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

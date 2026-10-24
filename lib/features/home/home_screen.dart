import 'package:flutter/material.dart';

import '../../core/router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openCamera(BuildContext context) async {
    final path = await Navigator.of(context).pushNamed<String>(Routes.camera);
    if (path != null && context.mounted) {
      // Phase B sẽ đưa ảnh này vào bộ nhận diện.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã chụp xong! Phần nhận diện sắp có.')),
      );
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
              Text(
                'English Cam',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
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
                  onTap: () => _comingSoon(context),
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
          onTap: onTap,
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

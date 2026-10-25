import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/router.dart';
import '../../services/app_settings.dart';
import '../mascot/mascot.dart';

class _Page {
  const _Page(this.mood, this.title, this.body, this.icon);

  final MascotMood mood;
  final String title;
  final String body;
  final IconData? icon;
}

const _pages = [
  _Page(
    MascotMood.happy,
    'Chào bé! Mình là Cam',
    'Cùng khám phá đồ vật xung quanh bằng tiếng Anh nhé!',
    null,
  ),
  _Page(
    MascotMood.thinking,
    'Chụp ảnh đồ vật',
    'Bé chụp một đồ vật, Cam sẽ cho bé biết nó là gì và đọc tên bằng tiếng Anh.',
    Icons.photo_camera_rounded,
  ),
  _Page(
    MascotMood.cheer,
    'Chơi và gom sao',
    'Chơi game để gom sao và nhận huy hiệu. Sai cũng không sao, cứ thử lại nhé!',
    Icons.star_rounded,
  ),
];

/// Hướng dẫn 3 bước, hiện ở lần mở app đầu tiên (hoặc xem lại từ Cài đặt).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.replay = false});

  /// true: mở lại từ Cài đặt, xong thì quay về thay vì sang Home.
  final bool replay;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await AppSettings.instance.setOnboardingDone(true);
    if (!mounted) return;
    if (widget.replay) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacementNamed(Routes.home);
    }
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Bỏ qua'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _PageView(page: _pages[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: i == _page ? 28 : 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: i == _page ? Palette.orange : Colors.black26,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_isLast ? 'Bắt đầu!' : 'Tiếp'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Mascot(mood: page.mood, size: 220),
              if (page.icon != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Palette.orange,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(page.icon, size: 36, color: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              height: 1.35,
              color: Palette.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

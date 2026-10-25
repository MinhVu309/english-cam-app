import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/theme.dart';
import '../mascot/mascot.dart';

/// Hiện khi app không nạp được dữ liệu lúc khởi động (thay vì màn hình trắng).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Cam',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Mascot(mood: MascotMood.oops, size: 180),
                  const SizedBox(height: 16),
                  const Text(
                    'Ôi, Cam bị trục trặc rồi!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Thử mở lại nhé. Nếu vẫn lỗi, nhờ bố mẹ cài lại ứng dụng.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, color: Palette.inkSoft),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

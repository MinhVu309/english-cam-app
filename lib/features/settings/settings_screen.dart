import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/router.dart';
import '../../services/audio_service.dart';
import '../../services/game_progress.dart';
import '../../services/progress_service.dart';
import '../mascot/mascot.dart';

/// Cài đặt cho bố mẹ (nằm sau cổng phụ huynh).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá tiến độ?'),
        content: const Text(
          'Toàn bộ từ đã học, sao và huy hiệu của bé sẽ bị xoá và không khôi phục được.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá hết'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ProgressService.instance.clear();
    await GameProgress.instance.reset();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Đã xoá tiến độ của bé.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          iconSize: 32,
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Cài đặt',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: AudioService.instance.musicOn,
              builder: (context, on, _) => _Tile(
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text(
                    'Nhạc nền',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  secondary: const Icon(Icons.music_note_rounded, size: 32),
                  value: on,
                  onChanged: AudioService.instance.setMusicOn,
                ),
              ),
            ),
            _Tile(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.slideshow_rounded, size: 32),
                title: const Text(
                  'Xem lại hướng dẫn',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.of(
                  context,
                ).pushNamed(Routes.onboarding, arguments: true),
              ),
            ),
            _Tile(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.delete_outline_rounded, size: 32),
                title: const Text(
                  'Xoá tiến độ của bé',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Từ đã học, sao và huy hiệu'),
                onTap: () => _confirmReset(context),
              ),
            ),
            _Tile(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.description_outlined, size: 32),
                title: const Text(
                  'Giấy phép mã nguồn mở',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'English Cam',
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _AboutCard(),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Mascot(size: 64, animate: false),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'English Cam',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            '• Chạy hoàn toàn trên máy, không cần mạng.\n'
            '• Không quảng cáo, không thu thập hay gửi dữ liệu đi đâu. '
            'Ảnh bé chụp chỉ được nhận diện trên máy.\n'
            '• Nhận diện 24 đồ vật bằng mô hình MobileNetV2; có thể nhận nhầm, '
            'bé luôn có thể chọn lại.',
            style: TextStyle(fontSize: 18, height: 1.4, color: Palette.inkSoft),
          ),
          SizedBox(height: 12),
          Text(
            'Giọng đọc tạo bằng TTS của macOS; nhạc nền và hiệu ứng tự tổng hợp; '
            'phông chữ Nunito (SIL OFL 1.1); hình minh hoạ là emoji của hệ thống; '
            'nhân vật Cam do nhóm tự vẽ.',
            style: TextStyle(fontSize: 18, height: 1.4, color: Palette.inkSoft),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:english_cam/features/mascot/mascot.dart';
import 'package:english_cam/services/audio_service.dart';

/// Chạy trước mọi file test: tắt hoạt hình lặp (để pumpAndSettle kết thúc được)
/// và âm thanh (test không có plugin âm thanh).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Mascot.animationsEnabled = false;
  AudioService.instance.disabled = true;
  await testMain();
}

import 'dart:async';

import 'package:english_cam/features/account/auth_gate.dart';
import 'package:english_cam/features/mascot/mascot.dart';
import 'package:english_cam/features/mascot/mascot_host.dart';
import 'package:english_cam/services/audio_service.dart';

/// Chạy trước mọi file test: tắt hoạt hình lặp (để pumpAndSettle kết thúc được),
/// âm thanh (test không có plugin âm thanh) và cổng bắt buộc đăng nhập (chỉ `auth_gate_test.dart` bật lại).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Mascot.animationsEnabled = false;
  MascotHost.autoEnabled = false;
  AudioService.instance.disabled = true;
  AuthGate.required = false;
  await testMain();
}

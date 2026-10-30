import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_messenger.dart';
import 'core/back_interceptor.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/widgets/fun_background.dart';
import 'data/game_badge.dart';
import 'data/pack/pack_manifest.dart';
import 'data/pack/pack_store.dart';
import 'data/vocab_repository.dart';
import 'features/account/auth_gate.dart';
import 'features/limit/play_limit_gate.dart';
import 'features/mascot/mascot_messages.dart';
import 'features/settings/parent_gate.dart';
import 'features/startup/startup_error_screen.dart';
import 'ml/classifier_service.dart';
import 'services/app_settings.dart';
import 'services/audio_service.dart';
import 'services/auth_service.dart';
import 'services/feedback_service.dart';
import 'services/game_progress.dart';
import 'services/pack_watcher.dart';
import 'services/progress_service.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BackInterceptor.ensureRegistered(); // trước khi dựng MaterialApp, xem ghi chú trong back_interceptor.dart
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await _start();
}

/// Nạp dữ liệu rồi mở app; nếu lỗi thì hiện màn hình báo lỗi có nút thử lại.
Future<void> _start() async {
  try {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'Nunito',
      ], await rootBundle.loadString('assets/fonts/OFL.txt'));
    });
    await PackStore.open(); // gói từ vựng đã tải (nếu có); lỗi thì dùng bản đóng gói sẵn
    await VocabRepository.load();
    await BadgeRepository.load();
    await MascotMessages.load();
    await AppSettings.instance.init();
    await ProgressService.instance.init();
    await AuthService.instance.init();
    await SyncService.instance
        .attach(); // nạp ngăn lưu đúng hồ sơ bé và bắt đầu đồng bộ nếu đang ở chế độ bé
    AuthService.instance.notice
      ..removeListener(_showAuthNotice)
      ..addListener(_showAuthNotice);
    unawaited(
      FeedbackService.instance.start(),
    ); // gửi bù các góp ý nhận diện còn trong hàng đợi
    SyncService.instance.onLimitWarning = _showLimitWarning;
    PackWatcher.instance
      ..onNewVersion = showPackNotice
      ..start(); // tự hỏi backend có từ vựng mới không (chỉ tải manifest nhỏ)
    await GameProgress.instance.init();
    unawaited(AudioService.instance.init());
    // Nạp model sẵn để lần chụp đầu tiên không bị chậm; lỗi sẽ hiện ở màn kết quả.
    unawaited(ClassifierService.instance.init().catchError((Object _) {}));
    runApp(const EnglishCamApp());
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(StartupErrorApp(onRetry: _start));
  }
}

/// Phiên đăng nhập kết thúc ngoài ý muốn (hết hạn, máy bị bố mẹ gỡ): báo bằng SnackBar ở bất kỳ màn nào.
void _showAuthNotice() {
  final text = AuthService.instance.notice.value;
  if (text == null) return;
  appMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  AuthService.instance.notice.value = null;
}

/// Cam nhắc bé còn ít phút chơi (một lần mỗi ngày).
void _showLimitWarning() {
  appMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text(
          'Cam nhắc: còn 5 phút nữa là hết giờ chơi hôm nay nhé!',
          style: TextStyle(fontSize: 20),
        ),
        duration: Duration(seconds: 8),
      ),
    );
}

/// Backend vừa phát bản từ vựng mới: báo ngay trong app. Bấm "Cập nhật" thì qua cổng phụ huynh rồi mở màn cập nhật
/// (chỉ còn một nút bấm); bé không tự cập nhật được.
@visibleForTesting
void showPackNotice(PackManifest m) {
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 12),
      // SnackBar có nút bấm mặc định không tự ẩn (persist = true từ Flutter 3.29): bắt buộc tắt, kẻo che nút mãi.
      persist: false,
      // Nổi lên khỏi vùng đáy (nút chụp ảnh, các nút của game nằm ở đó): không che thao tác chính của bé.
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 190),
      content: const Text(
        'Có từ vựng mới! Bố mẹ vào Cài đặt → Cập nhật từ vựng nhé.',
        style: TextStyle(fontSize: 20),
      ),
      action: SnackBarAction(
        label: 'Cập nhật',
        onPressed: () async {
          final ctx = appNavigatorKey.currentContext;
          if (ctx == null || !await showParentGate(ctx)) return;
          appNavigatorKey.currentState?.pushNamed(Routes.packUpdate);
        },
      ),
    ),
  );
}

class EnglishCamApp extends StatelessWidget {
  const EnglishCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Cam',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appMessengerKey,
      navigatorKey: appNavigatorKey,
      theme: buildAppTheme(),
      builder: (context, child) => FunBackground(
        child: PlayLimitGate(child: AuthGate(child: child!)),
      ),
      // Lần đầu mở app: hướng dẫn 3 bước, sau đó vào thẳng Home.
      initialRoute: AppSettings.instance.onboardingDone
          ? Routes.home
          : Routes.onboarding,
      onGenerateRoute: onGenerateRoute,
    );
  }
}

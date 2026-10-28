import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'core/widgets/fun_background.dart';
import 'data/game_badge.dart';
import 'data/pack/pack_store.dart';
import 'data/vocab_repository.dart';
import 'features/mascot/mascot_messages.dart';
import 'features/startup/startup_error_screen.dart';
import 'ml/classifier_service.dart';
import 'services/app_settings.dart';
import 'services/audio_service.dart';
import 'services/game_progress.dart';
import 'services/progress_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class EnglishCamApp extends StatelessWidget {
  const EnglishCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Cam',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) => FunBackground(child: child!),
      // Lần đầu mở app: hướng dẫn 3 bước, sau đó vào thẳng Home.
      initialRoute: AppSettings.instance.onboardingDone
          ? Routes.home
          : Routes.onboarding,
      onGenerateRoute: onGenerateRoute,
    );
  }
}

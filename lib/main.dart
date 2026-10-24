import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'ml/classifier_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Nạp model sẵn để lần chụp đầu tiên không bị chậm; lỗi sẽ hiện ở màn kết quả.
  unawaited(ClassifierService.instance.init().catchError((Object _) {}));
  runApp(const EnglishCamApp());
}

class EnglishCamApp extends StatelessWidget {
  const EnglishCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Cam',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      initialRoute: Routes.home,
      onGenerateRoute: onGenerateRoute,
    );
  }
}

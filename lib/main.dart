import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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

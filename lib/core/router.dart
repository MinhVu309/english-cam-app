import 'package:flutter/material.dart';

import '../features/camera/camera_screen.dart';
import '../features/home/home_screen.dart';
import '../features/result/result_screen.dart';

abstract final class Routes {
  static const home = '/';
  static const camera = '/camera';
  static const result = '/result';
}

Route<dynamic> onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case Routes.camera:
      return MaterialPageRoute<String>(
        settings: settings,
        builder: (_) => const CameraScreen(),
      );
    case Routes.result:
      return MaterialPageRoute<bool>(
        settings: settings,
        builder: (_) => ResultScreen(imagePath: settings.arguments! as String),
      );
    case Routes.home:
    default:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const HomeScreen(),
      );
  }
}

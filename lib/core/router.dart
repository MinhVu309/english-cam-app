import 'package:flutter/material.dart';

import '../features/camera/camera_screen.dart';
import '../features/home/home_screen.dart';

abstract final class Routes {
  static const home = '/';
  static const camera = '/camera';
}

Route<dynamic> onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case Routes.camera:
      return MaterialPageRoute<String>(
        settings: settings,
        builder: (_) => const CameraScreen(),
      );
    case Routes.home:
    default:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const HomeScreen(),
      );
  }
}

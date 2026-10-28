import 'package:flutter/material.dart';

import '../data/vocab_word.dart';
import '../features/camera/camera_screen.dart';
import '../features/game/game_hub_screen.dart';
import '../features/game/hunt/hunt_game_screen.dart';
import '../features/game/match/matching_game_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/settings/pack_update_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/result/result_screen.dart';
import '../features/vocab/vocab_detail_screen.dart';
import '../features/vocab/vocab_list_screen.dart';

abstract final class Routes {
  static const home = '/';
  static const onboarding = '/onboarding';
  static const settings = '/settings';
  static const packUpdate = '/settings/pack';
  static const camera = '/camera';
  static const result = '/result';
  static const vocab = '/vocab';
  static const vocabDetail = '/vocab/detail';
  static const games = '/games';
  static const matchGame = '/games/match';
  static const huntGame = '/games/hunt';
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
    case Routes.vocab:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const VocabListScreen(),
      );
    case Routes.vocabDetail:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            VocabDetailScreen(word: settings.arguments! as VocabWord),
      );
    case Routes.games:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const GameHubScreen(),
      );
    case Routes.matchGame:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const MatchingGameScreen(),
      );
    case Routes.huntGame:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const HuntGameScreen(),
      );
    case Routes.onboarding:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            OnboardingScreen(replay: settings.arguments as bool? ?? false),
      );
    case Routes.settings:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const SettingsScreen(),
      );
    case Routes.packUpdate:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const PackUpdateScreen(),
      );
    case Routes.home:
    default:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const HomeScreen(),
      );
  }
}

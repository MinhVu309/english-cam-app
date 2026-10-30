import 'package:flutter/material.dart';

import '../data/account/account_models.dart';
import '../data/vocab_word.dart';
import '../data/admin/admin_models.dart';
import '../features/account/admin_home_screen.dart';
import '../features/admin/admin_categories_screen.dart';
import '../features/admin/admin_feedback_screen.dart';
import '../features/admin/admin_publish_screen.dart';
import '../features/admin/admin_users_screen.dart';
import '../features/admin/admin_word_form_screen.dart';
import '../features/admin/admin_words_screen.dart';
import '../features/account/child_dashboard_screen.dart';
import '../features/account/child_detail_screen.dart';
import '../features/account/child_link_screen.dart';
import '../features/account/children_screen.dart';
import '../features/account/forgot_password_screen.dart';
import '../features/account/login_screen.dart';
import '../features/account/otp_screen.dart';
import '../features/account/register_screen.dart';
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
  static const login = '/login';
  static const register = '/register';
  static const otp = '/otp';
  static const forgot = '/forgot';
  static const children = '/children';
  static const childDetail = '/children/detail';
  static const childDashboard = '/children/dashboard';
  static const childLink = '/child-link';
  static const adminHome = '/admin';
  static const adminUsers = '/admin/users';
  static const adminWords = '/admin/words';
  static const adminWordEdit = '/admin/words/edit';
  static const adminCategories = '/admin/categories';
  static const adminPublish = '/admin/publish';
  static const adminFeedback = '/admin/feedback';
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
    case Routes.login:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const LoginScreen(),
      );
    case Routes.register:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const RegisterScreen(),
      );
    case Routes.otp:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => OtpScreen(args: settings.arguments! as OtpArgs),
      );
    case Routes.forgot:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const ForgotPasswordScreen(),
      );
    case Routes.children:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const ChildrenScreen(),
      );
    case Routes.childDetail:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            ChildDetailScreen(initial: settings.arguments! as ChildProfile),
      );
    case Routes.childDashboard:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            ChildDashboardScreen(child: settings.arguments! as ChildProfile),
      );
    case Routes.childLink:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const ChildLinkScreen(),
      );
    case Routes.adminHome:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const AdminHomeScreen(),
      );
    case Routes.adminUsers:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const AdminUsersScreen(),
      );
    case Routes.adminWords:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const AdminWordsScreen(),
      );
    case Routes.adminWordEdit:
      // Đối số: từ cần sửa; null = thêm từ mới. Trả true nếu có thay đổi.
      return MaterialPageRoute<bool>(
        settings: settings,
        builder: (_) =>
            AdminWordFormScreen(word: settings.arguments as AdminWord?),
      );
    case Routes.adminCategories:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const AdminCategoriesScreen(),
      );
    case Routes.adminFeedback:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const AdminFeedbackScreen(),
      );
    case Routes.adminPublish:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const AdminPublishScreen(),
      );
    case Routes.home:
    default:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const HomeScreen(),
      );
  }
}

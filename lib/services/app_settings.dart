import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kOnboardingKey = 'onboarding_done';

/// Cài đặt chung của app (hiện chỉ nhớ bé đã xem hướng dẫn chưa).
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  SharedPreferences? _prefs;
  bool onboardingDone = false;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      onboardingDone = _prefs?.getBool(_kOnboardingKey) ?? false;
    } catch (e) {
      debugPrint('AppSettings init failed: $e');
    }
    notifyListeners();
  }

  Future<void> setOnboardingDone(bool value) async {
    onboardingDone = value;
    notifyListeners();
    try {
      await _prefs?.setBool(_kOnboardingKey, value);
    } catch (e) {
      debugPrint('AppSettings save failed: $e');
    }
  }
}

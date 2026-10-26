import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kOnboardingKey = 'onboarding_done';
const String _kChatterKey = 'mascot_chatter';

/// Cài đặt chung của app (hiện chỉ nhớ bé đã xem hướng dẫn chưa).
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  SharedPreferences? _prefs;
  bool onboardingDone = false;

  /// Cam có tự nhắn tin cho bé không (bố mẹ tắt được trong Cài đặt).
  bool mascotChatter = true;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      onboardingDone = _prefs?.getBool(_kOnboardingKey) ?? false;
      mascotChatter = _prefs?.getBool(_kChatterKey) ?? true;
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

  Future<void> setMascotChatter(bool value) async {
    mascotChatter = value;
    notifyListeners();
    try {
      await _prefs?.setBool(_kChatterKey, value);
    } catch (e) {
      debugPrint('AppSettings save failed: $e');
    }
  }
}

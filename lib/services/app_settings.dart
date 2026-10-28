import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kOnboardingKey = 'onboarding_done';
const String _kChatterKey = 'mascot_chatter';
const String _kPackUrlKey = 'pack_url';

/// Địa chỉ gói từ vựng mặc định, đặt khi build: `--dart-define=PACK_URL=https://...`.
/// Phụ huynh vẫn đổi được trong Cài đặt.
const String kDefaultPackUrl = String.fromEnvironment('PACK_URL');

/// Cài đặt chung của app (hiện chỉ nhớ bé đã xem hướng dẫn chưa).
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  SharedPreferences? _prefs;
  bool onboardingDone = false;

  /// Cam có tự nhắn tin cho bé không (bố mẹ tắt được trong Cài đặt).
  bool mascotChatter = true;

  /// Địa chỉ thư mục chứa manifest.json của gói từ vựng (rỗng: chưa cấu hình).
  String packUrl = kDefaultPackUrl;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      onboardingDone = _prefs?.getBool(_kOnboardingKey) ?? false;
      mascotChatter = _prefs?.getBool(_kChatterKey) ?? true;
      packUrl = _prefs?.getString(_kPackUrlKey) ?? kDefaultPackUrl;
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

  Future<void> setPackUrl(String value) async {
    packUrl = value.trim();
    notifyListeners();
    try {
      await _prefs?.setString(_kPackUrlKey, packUrl);
    } catch (e) {
      debugPrint('AppSettings save failed: $e');
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_config.dart';

const String _kOnboardingKey = 'onboarding_done';
const String _kChatterKey = 'mascot_chatter';
const String _kPackUrlKey = 'pack_url';

/// Địa chỉ gói từ vựng mặc định: `--dart-define=PACK_URL=https://...` nếu có, không thì gói do backend phát
/// ([ApiConfig.packUrl], cùng máy chủ với API). Người dùng không cần nhập; đổi sang địa chỉ khác (hosting tĩnh)
/// chỉ ở mục "Nâng cao" của màn cập nhật.
const String _kPackUrlDefine = String.fromEnvironment('PACK_URL');
const String kDefaultPackUrl = _kPackUrlDefine != ''
    ? _kPackUrlDefine
    : ApiConfig.packUrl;

/// Cài đặt chung của app (hiện chỉ nhớ bé đã xem hướng dẫn chưa).
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  SharedPreferences? _prefs;
  bool onboardingDone = false;

  /// Cam có tự nhắn tin cho bé không (bố mẹ tắt được trong Cài đặt).
  bool mascotChatter = true;

  /// Địa chỉ thư mục chứa manifest.json của gói từ vựng. Mặc định là [kDefaultPackUrl].
  String packUrl = kDefaultPackUrl;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      onboardingDone = _prefs?.getBool(_kOnboardingKey) ?? false;
      mascotChatter = _prefs?.getBool(_kChatterKey) ?? true;
      final saved = _prefs?.getString(_kPackUrlKey);
      packUrl = saved == null || saved.isEmpty ? kDefaultPackUrl : saved;
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

  /// Đặt địa chỉ gói tuỳ chỉnh. Trùng địa chỉ mặc định thì xoá bản đã lưu, để sau này đổi máy chủ API
  /// (build mới) thì gói cũng đi theo, không bị kẹt ở địa chỉ cũ.
  Future<void> setPackUrl(String value) async {
    packUrl = value.trim().isEmpty ? kDefaultPackUrl : value.trim();
    notifyListeners();
    try {
      if (packUrl == kDefaultPackUrl) {
        await _prefs?.remove(_kPackUrlKey);
      } else {
        await _prefs?.setString(_kPackUrlKey, packUrl);
      }
    } catch (e) {
      debugPrint('AppSettings save failed: $e');
    }
  }
}

import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import '../core/api_config.dart';

class GoogleNotConfigured implements Exception {
  GoogleNotConfigured([
    this.message = 'Đăng nhập Google chưa được cấu hình (thiếu Google client ID).',
  ]);

  final String message;
}

class GoogleCancelled implements Exception {}

class GoogleSignInFailed implements Exception {
  GoogleSignInFailed(this.detail);

  final String detail;
}

/// Lấy Google ID token để gửi lên `POST /api/auth/google-login`.
abstract interface class GoogleAuth {
  Future<String> getIdToken();
  Future<void> signOut();
}

class GoogleAuthService implements GoogleAuth {
  bool _initialized = false;

  /// null nếu dùng được, ngược lại là lý do để hiện cho người dùng.
  static String? unavailableReason({
    String serverClientId = ApiConfig.googleServerClientId,
    bool? isAndroid,
  }) {
    if (serverClientId.isEmpty) {
      return 'Đăng nhập Google chưa được cấu hình (thiếu Google client ID).';
    }
    if (!(isAndroid ?? Platform.isAndroid)) {
      return 'Đăng nhập Google hiện chỉ dùng được trên Android.';
    }
    return null;
  }

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: ApiConfig.googleServerClientId,
    );
    _initialized = true;
  }

  @override
  Future<String> getIdToken() async {
    final reason = unavailableReason();
    if (reason != null) throw GoogleNotConfigured(reason);
    try {
      await _init();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw GoogleSignInFailed('Không nhận được ID token');
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw GoogleCancelled();
      throw GoogleSignInFailed(e.code.name);
    }
  }

  @override
  Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // đăng xuất Google lỗi không được chặn việc đăng xuất khỏi app
    }
  }
}

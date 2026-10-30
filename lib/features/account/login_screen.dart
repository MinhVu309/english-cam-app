import 'package:flutter/material.dart';

import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/google_auth.dart';
import '../mascot/mascot.dart';
import 'account_widgets.dart';
import 'auth_gate.dart';
import 'otp_screen.dart';

/// Đưa người dùng tới màn đầu tiên theo vai trò sau khi đăng nhập: Admin → quản trị, Parent → chọn bé.
void goToLanding(BuildContext context) {
  // Trong cổng đăng nhập: AuthGate tự đưa tới trang đúng khi phiên có hiệu lực.
  if (AuthGateScope.isInside(context)) return;
  Navigator.of(context).pushNamedAndRemoveUntil(
    AuthService.instance.landingRoute,
    ModalRoute.withName(Routes.home),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!isValidEmail(_email.text) || _password.text.isEmpty) {
      setState(() => _error = 'Nhập email hợp lệ và mật khẩu.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.requestLoginOtp(_email.text, _password.text);
      if (!mounted) return;
      await Navigator.of(context).pushNamed(
        Routes.otp,
        arguments: OtpArgs(_email.text.trim(), OtpMode.login),
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
      if (mounted) goToLanding(context);
    } on GoogleCancelled {
      // người dùng tự đóng hộp thoại Google: không báo lỗi
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountScaffold(
      title: 'Đăng nhập',
      children: [
        const Center(child: Mascot(size: 96, animate: false)),
        const SizedBox(height: 8),
        const Text(
          'Dành cho bố mẹ. Đăng nhập để lưu tiến độ và xem báo cáo của bé.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 16),
        if (_error != null) ErrorNote(_error!),
        FieldBox(
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          enabled: !_busy,
        ),
        FieldBox(
          controller: _password,
          label: 'Mật khẩu',
          obscure: !_show,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
          autofillHints: const [AutofillHints.password],
          enabled: !_busy,
          suffix: IconButton(
            tooltip: _show ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
            icon: Icon(
              _show ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            ),
            onPressed: () => setState(() => _show = !_show),
          ),
        ),
        BusyButton(label: 'Đăng nhập', busy: _busy, onPressed: _login),
        const SizedBox(height: 12),
        BusyButton(
          label: 'Đăng nhập bằng Google',
          icon: Icons.account_circle_outlined,
          outlined: true,
          busy: false,
          onPressed: _busy ? null : _google,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).pushNamed(Routes.forgot),
          child: const Text('Quên mật khẩu?'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).pushNamed(Routes.register),
          child: const Text('Chưa có tài khoản? Đăng ký'),
        ),
      ],
    );
  }
}

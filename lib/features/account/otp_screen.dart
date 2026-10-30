import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_config.dart';
import '../../services/auth_service.dart';
import 'account_widgets.dart';
import 'login_screen.dart';

enum OtpMode { login, register }

class OtpArgs {
  const OtpArgs(this.email, this.mode);

  final String email;
  final OtpMode mode;
}

/// Nhập mã 6 số máy chủ gửi tới email (xác minh đăng ký hoặc xác nhận đăng nhập).
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.args});

  final OtpArgs args;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  Timer? _timer;
  int _left = ApiConfig.otpResendCooldown.inSeconds;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    _left = ApiConfig.otpResendCooldown.inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Nhập đủ mã 6 số.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.verifyOtp(widget.args.email, code);
      if (mounted) goToLanding(context);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await AuthService.instance.resendOtp(widget.args.email);
      if (!mounted) return;
      setState(() => _info = 'Đã gửi lại mã. Kiểm tra cả mục Thư rác nhé.');
      _startCountdown();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final register = widget.args.mode == OtpMode.register;
    return AccountScaffold(
      title: register ? 'Xác minh email' : 'Nhập mã OTP',
      children: [
        Text(
          'Mã 6 số đã được gửi tới ${widget.args.email}. Mã có hiệu lực 5 phút.',
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 16),
        if (_error != null) ErrorNote(_error!),
        if (_info != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_info!, style: const TextStyle(fontSize: 18)),
          ),
        FieldBox(
          controller: _code,
          label: 'Mã OTP',
          centered: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _verify(),
          autofillHints: const [AutofillHints.oneTimeCode],
          enabled: !_busy,
        ),
        BusyButton(
          label: register ? 'Xác minh' : 'Đăng nhập',
          busy: _busy,
          onPressed: _verify,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _left > 0 || _busy ? null : _resend,
          child: Text(_left > 0 ? 'Gửi lại mã sau ${_left}s' : 'Gửi lại mã'),
        ),
      ],
    );
  }
}

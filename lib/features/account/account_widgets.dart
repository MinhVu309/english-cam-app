import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/palette.dart';
import '../../services/google_auth.dart';

/// Hình đại diện của bé: lưu khoá chữ trong hồ sơ, hiện bằng emoji của hệ thống (không cần ảnh, không bản quyền).
const Map<String, String> kAvatars = {
  'cat': '🐱',
  'dog': '🐶',
  'rabbit': '🐰',
  'bear': '🐻',
  'panda': '🐼',
  'fox': '🦊',
  'lion': '🦁',
  'frog': '🐸',
  'chick': '🐥',
  'unicorn': '🦄',
};

/// Tên tiếng Việt của avatar (đọc cho người dùng trình đọc màn hình và hiện khi nhấn giữ).
const Map<String, String> kAvatarNames = {
  'cat': 'Mèo',
  'dog': 'Chó',
  'rabbit': 'Thỏ',
  'bear': 'Gấu',
  'panda': 'Gấu trúc',
  'fox': 'Cáo',
  'lion': 'Sư tử',
  'frog': 'Ếch',
  'chick': 'Gà con',
  'unicorn': 'Kỳ lân',
};

String avatarEmoji(String? key) => kAvatars[key] ?? '🙂';

/// Thông báo lỗi thân thiện từ một exception bất kỳ.
String friendlyError(Object e) {
  if (e is ApiException) return e.message;
  if (e is GoogleNotConfigured) return e.message;
  if (e is GoogleSignInFailed) {
    return 'Đăng nhập Google không thành công (${e.detail}). Hãy thử đăng nhập bằng email.';
  }
  return 'Có lỗi xảy ra, hãy thử lại nhé.';
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Huỷ',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// "vừa xong", "5 phút trước", "2 giờ trước", "3 ngày trước".
String relativeTime(DateTime? t, DateTime now) {
  if (t == null) return 'chưa dùng';
  final d = now.toUtc().difference(t.toUtc());
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inHours < 1) return '${d.inMinutes} phút trước';
  if (d.inDays < 1) return '${d.inHours} giờ trước';
  return '${d.inDays} ngày trước';
}

/// Khung màn hình tài khoản: thanh tiêu đề cùng kiểu Cài đặt + danh sách cuộn.
class AccountScaffold extends StatelessWidget {
  const AccountScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.floatingActionButton,
    this.onRefresh,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      children: children,
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          iconSize: 32,
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: onRefresh == null
            ? list
            : RefreshIndicator(onRefresh: onRefresh!, child: list),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Ô nhập chữ lớn, bo tròn, nền trắng (chữ ≥ 18sp).
class FieldBox extends StatelessWidget {
  const FieldBox({
    super.key,
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscure = false,
    this.maxLength,
    this.inputFormatters,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
    this.enabled = true,
    this.centered = false,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscure;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final bool enabled;
  final bool centered;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscure,
        maxLength: maxLength,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        autofillHints: autofillHints,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: centered ? 32 : 22,
          fontWeight: centered ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: centered ? 6 : 0,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 20),
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          suffixIcon: suffix,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Palette.oops,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nút lớn có vòng xoay khi đang gửi (và không bấm lại được).
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 3),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 26),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );
    final handler = busy ? null : onPressed;
    return outlined
        ? OutlinedButton(onPressed: handler, child: child)
        : FilledButton(onPressed: handler, child: child);
  }
}

class AvatarBubble extends StatelessWidget {
  const AvatarBubble({
    super.key,
    required this.avatarKey,
    this.size = 56,
    this.selected = false,
  });

  final String? avatarKey;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Palette.peel.withValues(alpha: 0.35) : Palette.cream,
        border: Border.all(
          color: selected ? Palette.orange : Colors.transparent,
          width: 3,
        ),
      ),
      child: Text(
        avatarEmoji(avatarKey),
        style: TextStyle(fontSize: size * 0.55),
      ),
    );
  }
}

/// Bộ chọn avatar cho bé.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({super.key, required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final key in kAvatars.keys)
          Tooltip(
            message: kAvatarNames[key] ?? key,
            child: Semantics(
              button: true,
              selected: value == key,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onChanged(key),
                child: AvatarBubble(
                  avatarKey: key,
                  size: 60,
                  selected: value == key,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Nút −/+ lớn để chỉnh một số (dễ bấm hơn thanh trượt).
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.unit = '',
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton.filledTonal(
          iconSize: 32,
          tooltip: 'Giảm',
          onPressed: value - step >= min ? () => onChanged(value - step) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Text(
          '$value $unit'.trim(),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        IconButton.filledTonal(
          iconSize: 32,
          tooltip: 'Tăng',
          onPressed: value + step <= max ? () => onChanged(value + step) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
bool isValidEmail(String s) => _emailRe.hasMatch(s.trim());

/// Cùng luật với máy chủ: ≥ 8 ký tự, có chữ thường và chữ số. Trả lý do nếu chưa đạt.
String? passwordProblem(String p) {
  if (p.length < 8) return 'Mật khẩu tối thiểu 8 ký tự.';
  if (!p.contains(RegExp(r'[a-z]'))) {
    return 'Mật khẩu cần ít nhất một chữ thường.';
  }
  if (!p.contains(RegExp(r'[0-9]'))) return 'Mật khẩu cần ít nhất một chữ số.';
  return null;
}

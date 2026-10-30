import 'package:flutter/widgets.dart';

/// Cho các lớp phủ nằm TRÊN Navigator gốc (cổng đăng nhập, màn hết giờ chơi) nhận nút Back của hệ thống trước Navigator gốc.
/// `NavigatorPopHandler`/`PopScope` không dùng được ở đó vì chúng cần một route bao quanh.
///
/// Phải đăng ký ([ensureRegistered]) TRƯỚC khi dựng `MaterialApp`: `WidgetsBinding` hỏi các observer theo thứ tự đăng ký
/// và observer của `WidgetsApp` (pop route gốc) sẽ chặn mọi thứ đăng ký sau nó.
class BackInterceptor with WidgetsBindingObserver {
  BackInterceptor._();

  static final BackInterceptor instance = BackInterceptor._();
  static bool _registered = false;

  final List<Future<bool> Function()> _handlers = [];

  static void ensureRegistered() {
    if (_registered) return;
    _registered = true;
    WidgetsBinding.instance.addObserver(instance);
  }

  /// Thêm bộ xử lý (cái thêm sau được hỏi trước). [handler] trả true nếu đã xử lý Back. Trả về hàm gỡ.
  VoidCallback add(Future<bool> Function() handler) {
    _handlers.add(handler);
    return () => _handlers.remove(handler);
  }

  @override
  Future<bool> didPopRoute() async {
    for (final h in _handlers.reversed.toList()) {
      if (await h()) return true;
    }
    return false;
  }
}

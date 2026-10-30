import 'package:flutter/material.dart';

/// Cho phép hiện SnackBar từ ngoài cây widget (ví dụ khi phiên đăng nhập bị kết thúc ở nền).
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Navigator chính của app, để chuyển trang từ bên ngoài cây Navigator (ví dụ cổng đăng nhập đưa phụ huynh tới trang của họ).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

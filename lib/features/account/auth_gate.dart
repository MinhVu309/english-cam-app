import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_messenger.dart';
import '../../core/back_interceptor.dart';
import '../../core/palette.dart';
import '../../core/router.dart';
import '../../core/widgets/fun_background.dart';
import '../../services/auth_service.dart';
import '../mascot/mascot.dart';
import 'account_widgets.dart';

/// Đánh dấu "đang ở trong cổng đăng nhập" để các màn đăng nhập dùng lại được mà không tự chuyển trang
/// (khi đăng nhập xong, [AuthGate] tự biến mất và đưa phụ huynh tới trang của họ).
class AuthGateScope extends InheritedWidget {
  const AuthGateScope({super.key, required super.child});

  static bool isInside(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AuthGateScope>() != null;

  @override
  bool updateShouldNotify(AuthGateScope oldWidget) => false;
}

/// Bắt buộc đăng nhập mới dùng được app: khi máy chưa có phiên nào (phụ huynh/admin hoặc bé), phủ màn chào lên toàn app.
/// Phụ huynh đăng nhập (email + OTP hoặc Google); máy của bé nhập mã liên kết do bố mẹ tạo.
///
/// Đã có phiên thì không bao giờ hiện, kể cả khi không có mạng (phiên lưu trên máy). Phiên hết hạn hoặc bị gỡ
/// (401) hay đăng xuất thì cổng hiện lại.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child, this.auth});

  final Widget child;

  /// Mặc định là [AuthService.instance].
  final AuthService? auth;

  /// Tắt cổng toàn cục (chỉ test các màn khác mà không phải đăng nhập). Bản chạy thật luôn bật.
  static bool required = true;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthService get _auth => widget.auth ?? AuthService.instance;
  bool _wasGuest = true;
  final _gateNav = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Đọc ngay lúc dựng, không phải lúc phiên đổi (nếu khởi tạo `late` sẽ đọc muộn và không bao giờ thấy lần chuyển).
    _wasGuest = _auth.isGuest;
    _auth.addListener(_onAuth);
    BackInterceptor.ensureRegistered();
    _removeBack = BackInterceptor.instance.add(_onBack);
  }

  late final VoidCallback _removeBack;

  /// Nút Back khi cổng đang hiện: lùi một màn trong cổng (đăng nhập → màn chào); ở màn chào thì thoát app.
  /// Đừng để nó lọt xuống Navigator gốc (đang bị cổng che).
  Future<bool> _onBack() async {
    if (!(AuthGate.required && _auth.isGuest)) return false;
    if (!await (_gateNav.currentState?.maybePop() ?? Future.value(false))) {
      SystemNavigator.pop();
    }
    return true;
  }

  @override
  void dispose() {
    _removeBack();
    _auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    final guest = _auth.isGuest;
    final justSignedIn = _wasGuest && !guest;
    _wasGuest = guest;
    // Phụ huynh/admin vừa đăng nhập: đưa tới trang của họ (bé thì ở lại Home).
    if (justSignedIn && !_auth.inChildMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
          _auth.landingRoute,
          (r) => r.isFirst,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _auth,
      builder: (context, _) => Stack(
        children: [
          widget.child,
          if (AuthGate.required && _auth.isGuest)
            Positioned.fill(
              // Navigator riêng để các màn đăng nhập/OTP/mã liên kết đẩy trang ngay trong cổng. Route gốc tên '/'
              // để `popUntil(withName(home))` của các màn đó quay về màn chào.
              child: HeroControllerScope.none(
                // Nền đặc: các màn đăng nhập có Scaffold trong suốt (nền do FunBackground của app cấp), nếu không có nó
                // thì màn Home nằm bên dưới sẽ lộ xuyên qua form.
                child: AuthGateScope(
                  child: FunBackground(
                    child: Navigator(
                      key: _gateNav,
                      onGenerateRoute: (s) =>
                          s.name == Routes.home || s.name == null
                          ? MaterialPageRoute<void>(
                              settings: const RouteSettings(name: Routes.home),
                              builder: (_) => const WelcomeScreen(),
                            )
                          : onGenerateRoute(s),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Mascot(size: 150),
                const SizedBox(height: 12),
                const Text(
                  'Chào mừng đến English Cam!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Palette.ink,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hãy đăng nhập để bắt đầu học từ vựng cùng Cam.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, color: Palette.inkSoft),
                ),
                const SizedBox(height: 28),
                BusyButton(
                  label: 'Bố mẹ: đăng nhập / đăng ký',
                  icon: Icons.family_restroom_rounded,
                  onPressed: () =>
                      Navigator.of(context).pushNamed(Routes.login),
                ),
                const SizedBox(height: 12),
                BusyButton(
                  label: 'Máy của bé: nhập mã liên kết',
                  icon: Icons.link_rounded,
                  outlined: true,
                  onPressed: () =>
                      Navigator.of(context).pushNamed(Routes.childLink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

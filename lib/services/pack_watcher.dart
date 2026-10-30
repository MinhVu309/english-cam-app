import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/pack/pack_manifest.dart';
import '../data/pack/pack_store.dart';
import '../data/pack/pack_updater.dart';
import 'app_settings.dart';
import 'auth_service.dart';

/// Phiên bản gói từ vựng đóng gói sẵn trong app. Bản đầu tiên backend phát (phiên bản 1) chính là bộ từ vựng này,
/// nên máy chưa tải gói nào coi như đang ở bản 1 (không báo "có bản mới" oan ngay lần mở đầu tiên).
/// **Tăng số này khi cập nhật `assets/vocab/vocab.json` đóng gói sẵn.**
const int kBundledPackVersion = 1;

const String _kNotifiedKey = 'pack_notified_version';

/// Tự biết khi backend có bản từ vựng mới và báo cho người dùng.
///
/// Cứ vài chục phút, và mỗi lần mở lại app, nó chỉ tải `manifest.json` (vài trăm byte) rồi so số phiên bản với bản đang
/// dùng. Có bản mới thì [available] được đặt (Cài đặt hiện dấu "có bản mới", màn cập nhật hiện nút "Cập nhật ngay")
/// và [onNewVersion] được gọi **một lần cho mỗi phiên bản** (nhớ qua các lần mở app) để app hiện thông báo.
/// Việc tải gói về vẫn do người dùng bấm nút. Lỗi mạng bị bỏ qua, không làm phiền ai.
///
/// Lưu ý: đây là thông báo trong app (khi app đang mở hoặc vừa mở lại). Báo cho máy khi app đã đóng hẳn cần push
/// của hệ điều hành (FCM/APNs), chưa làm.
class PackWatcher extends ChangeNotifier with WidgetsBindingObserver {
  PackWatcher({
    PackStore? Function()? store,
    Future<PackManifest> Function(String url)? fetch,
    String Function()? url,
    bool Function()? enabled,
    Listenable? auth,
    DateTime Function()? clock,
    this.interval = const Duration(minutes: 30),
    this.minGap = const Duration(minutes: 5),
    this.firstDelay = const Duration(seconds: 6),
  }) : _store = store ?? (() => PackStore.instance),
       _fetchOverride = fetch,
       _url = url ?? (() => AppSettings.instance.packUrl),
       _enabled = enabled ?? (() => !AuthService.instance.isGuest),
       _authOverride = auth,
       _clock = clock ?? DateTime.now;

  static PackWatcher instance = PackWatcher();

  final PackStore? Function() _store;
  final Future<PackManifest> Function(String url)? _fetchOverride;
  final String Function() _url;
  final bool Function() _enabled;
  final Listenable? _authOverride;
  final DateTime Function() _clock;
  bool _wasEnabled = false;

  /// Phiên đăng nhập đổi: vừa đăng nhập xong thì kiểm tra ngay (lúc mở app chưa đăng nhập thì lần kiểm tra đầu bị bỏ qua).
  void _onAuthChanged() {
    final now = _enabled();
    final justEnabled = now && !_wasEnabled;
    _wasEnabled = now;
    if (justEnabled) unawaited(check());
  }

  Listenable get _auth => _authOverride ?? AuthService.instance;

  /// Chu kỳ kiểm tra khi app đang mở, khoảng cách tối thiểu giữa hai lần kiểm tra tự động, và độ trễ lần đầu
  /// (để không tranh mạng với lúc khởi động).
  final Duration interval;
  final Duration minGap;
  final Duration firstDelay;

  /// Được gọi một lần cho mỗi phiên bản mới (kèm manifest để hiện ghi chú).
  void Function(PackManifest manifest)? onNewVersion;

  PackManifest? _available;
  DateTime? _lastCheck;
  Timer? _timer;
  Timer? _first;
  bool _checking = false;
  bool _attached = false;

  /// Bản mới hơn bản đang dùng (null nếu đang là bản mới nhất hoặc chưa kiểm tra được).
  PackManifest? get available => _available;

  /// Lần kiểm tra gần nhất thất bại (mất mạng, máy chủ lỗi...)? null nếu thành công hoặc chưa kiểm tra lần nào.
  String? get lastError => _lastError;
  String? _lastError;

  /// Phiên bản đang dùng: gói đã tải, hoặc bản đóng gói sẵn.
  int get currentVersion =>
      _store()?.readInstalled()?.version ?? kBundledPackVersion;

  /// Bắt đầu theo dõi: kiểm tra sau [firstDelay], rồi mỗi [interval], và mỗi khi app quay lại.
  void start() {
    if (_attached) return;
    _attached = true;
    _wasEnabled = _enabled();
    _auth.addListener(_onAuthChanged);
    WidgetsBinding.instance.addObserver(this);
    _first = Timer(firstDelay, () => unawaited(check()));
    _timer = Timer.periodic(interval, (_) => unawaited(check()));
  }

  void stop() {
    _first?.cancel();
    _timer?.cancel();
    if (_attached) {
      WidgetsBinding.instance.removeObserver(this);
      _auth.removeListener(_onAuthChanged);
    }
    _attached = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  /// Hỏi máy chủ phiên bản mới nhất. [force] = bỏ qua giới hạn tần suất (người dùng chủ động mở màn cập nhật).
  /// Trả true nếu có bản mới hơn bản đang dùng.
  Future<bool> check({bool force = false}) async {
    if (_checking || !_enabled() || _store() == null) return _available != null;
    final now = _clock();
    final last = _lastCheck;
    if (!force && last != null && now.difference(last) < minGap) {
      return _available != null;
    }
    _checking = true;
    _lastCheck = now;
    try {
      final url = _url();
      final latest =
          await (_fetchOverride?.call(url) ??
              PackUpdater(_store()!).fetchLatest(url));
      _lastError = null;
      if (latest.version > currentVersion) {
        _available = latest;
        notifyListeners();
        await _notifyOnce(latest);
      } else if (_available != null) {
        _available = null;
        notifyListeners();
      }
    } catch (e) {
      _lastError = e is PackUpdateException ? e.message : '$e';
      debugPrint('PackWatcher: chưa kiểm tra được bản từ vựng mới ($e)');
    } finally {
      _checking = false;
    }
    return _available != null;
  }

  /// Sau khi người dùng đã cập nhật xong: hết "có bản mới".
  void markUpdated() {
    if (_available == null) return;
    _available = null;
    notifyListeners();
  }

  Future<void> _notifyOnce(PackManifest latest) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt(_kNotifiedKey) ?? 0) >= latest.version) return;
      await prefs.setInt(_kNotifiedKey, latest.version);
    } catch (e) {
      debugPrint('PackWatcher: không nhớ được phiên bản đã báo ($e)');
    }
    onNewVersion?.call(latest);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

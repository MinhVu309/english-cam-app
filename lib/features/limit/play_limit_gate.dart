import 'package:flutter/material.dart';

import '../../core/back_interceptor.dart';
import '../../core/palette.dart';
import '../../services/play_limit.dart';
import '../../services/sync_service.dart';
import '../mascot/mascot.dart';
import '../settings/parent_gate.dart';

/// Phủ lên toàn app một màn "Hết giờ chơi" khi bé dùng hết thời gian bố mẹ cho phép hôm nay.
/// Bố mẹ qua cổng phép nhân để cho bé chơi thêm. Khi chưa vào chế độ bé hoặc không đặt giới hạn thì không làm gì.
class PlayLimitGate extends StatefulWidget {
  const PlayLimitGate({super.key, required this.child, this.limit});

  final Widget child;

  /// Mặc định là giới hạn của [SyncService.instance]; test truyền đối tượng riêng.
  final PlayLimit? limit;

  @override
  State<PlayLimitGate> createState() => _PlayLimitGateState();
}

class _PlayLimitGateState extends State<PlayLimitGate> {
  final _nav = GlobalKey<NavigatorState>();
  late final VoidCallback _removeBack;

  @override
  void initState() {
    super.initState();
    BackInterceptor.ensureRegistered();
    _removeBack = BackInterceptor.instance.add(_onBack);
  }

  @override
  void dispose() {
    _removeBack();
    super.dispose();
  }

  /// Nút Back khi màn khoá đang hiện: chỉ đóng hộp thoại đang mở trên nó; không để lọt xuống màn của bé bên dưới.
  Future<bool> _onBack() async {
    final l = widget.limit ?? SyncService.instance.limit;
    if (!l.locked) return false;
    await _nav.currentState?.maybePop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.limit ?? SyncService.instance.limit;
    return ListenableBuilder(
      listenable: l,
      builder: (context, _) => Stack(
        children: [
          widget.child,
          // Navigator riêng: hộp thoại cổng phụ huynh phải hiện TRÊN màn khoá; nếu dùng Navigator của app thì màn khoá
          // (nằm phủ lên Navigator đó) sẽ che mất hộp thoại và bố mẹ không mở khoá được.
          if (l.locked)
            Positioned.fill(
              child: HeroControllerScope.none(
                child: Navigator(
                  key: _nav,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => TimeUpScreen(limit: l),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Số phút cho thêm mà bố mẹ chọn được.
const List<int> kExtraMinuteChoices = [10, 20, 30];

class TimeUpScreen extends StatelessWidget {
  const TimeUpScreen({super.key, required this.limit});

  final PlayLimit limit;

  Future<void> _parentUnlock(BuildContext ctx) async {
    if (!await showParentGate(ctx) || !ctx.mounted) return;
    final minutes = await showDialog<int>(
      context: ctx,
      builder: (context) => SimpleDialog(
        title: const Text('Cho bé chơi thêm'),
        children: [
          for (final m in kExtraMinuteChoices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(m),
              child: Text('$m phút', style: const TextStyle(fontSize: 22)),
            ),
        ],
      ),
    );
    if (minutes != null) limit.grantMore(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final played = ((limit.limitMinutes ?? 0) + limit.bonusSeconds / 60)
        .round();
    return Material(
      color: Palette.cream,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Mascot(size: 160),
                const SizedBox(height: 16),
                const Text(
                  'Hết giờ chơi hôm nay rồi!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Palette.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Bé đã chơi $played phút. Cam hẹn bé ngày mai nhé, mai chơi tiếp nhé!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, color: Palette.inkSoft),
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () => _parentUnlock(context),
                  icon: const Icon(Icons.lock_open_rounded, size: 28),
                  label: const Text(
                    'Dành cho bố mẹ',
                    style: TextStyle(fontSize: 20),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(260, 60),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

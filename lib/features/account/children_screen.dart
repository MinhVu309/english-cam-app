import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/router.dart';
import '../../data/account/account_models.dart';
import '../../data/account/dashboard_models.dart';
import '../../services/auth_service.dart';
import '../mascot/mascot.dart';
import 'account_widgets.dart';
import 'child_form.dart';

/// Khu phụ huynh sau khi đăng nhập: danh sách bé, cho bé chơi trên máy này, quản lý từng bé.
class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key});

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  List<ChildProfile>? _children;

  /// Số liệu tóm tắt từng bé (sao, chuỗi ngày, phút hôm nay); tải thêm, lỗi thì thôi, không chặn danh sách.
  Map<String, ChildOverview> _overview = const {};
  String? _error;
  bool _loading = true;
  String? _startingId;

  AuthService get _auth => AuthService.instance;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    _load();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// Phiên phụ huynh hết hạn giữa chừng: quay về trang chủ (AuthService đã báo qua thông báo).
  void _onAuthChanged() {
    if (!_auth.isParentSignedIn && mounted) {
      Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = _children == null;
      _error = null;
    });
    try {
      final list = await _auth.loadChildren();
      if (mounted) setState(() => _children = list);
      _loadOverview();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOverview() async {
    try {
      final o = await _auth.loadOverview();
      if (mounted) setState(() => _overview = o);
    } catch (_) {
      // không có số liệu tóm tắt thì thẻ bé vẫn dùng được
    }
  }

  Future<void> _play(ChildProfile c) async {
    setState(() => _startingId = c.id);
    try {
      await _auth.startChildSession(c);
      if (!mounted) return;
      toast(context, 'Chào ${c.nickname}! Chơi vui nhé.');
      Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _startingId = null);
    }
  }

  Future<void> _add() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(sheet).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Thêm bé',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ChildForm(
                submitLabel: 'Thêm bé',
                onSubmit: (nickname, avatar, year) async {
                  await _auth.createChild(nickname, avatar, year);
                  if (sheet.mounted) Navigator.of(sheet).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _signOut() async {
    final ok = await confirmDialog(
      context,
      title: 'Đăng xuất?',
      message:
          'Máy này sẽ ngừng dùng được cho tới khi có người đăng nhập lại (bố mẹ) hoặc nhập mã liên kết (máy của bé). Tiến độ đã lưu trên máy chủ.',
      confirmLabel: 'Đăng xuất',
    );
    if (!ok) return;
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final me = _auth.parent;
    final children = _children;
    return AccountScaffold(
      title: 'Hồ sơ của bé',
      onRefresh: _load,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded, size: 28),
        label: const Text(
          'Thêm bé',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ),
      children: [
        SectionCard(
          child: Row(
            children: [
              const Icon(Icons.account_circle_rounded, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      me?.fullName ?? '',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      me?.email ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Palette.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: _signOut, child: const Text('Đăng xuất')),
            ],
          ),
        ),
        if (_auth.inChildMode)
          SectionCard(
            child: Row(
              children: [
                AvatarBubble(avatarKey: _auth.activeChild?.avatarKey, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Máy này đang ở chế độ của ${_auth.activeChild?.nickname ?? 'bé'}',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                TextButton(
                  onPressed: () => _auth.leaveChildMode(),
                  child: const Text('Thoát'),
                ),
              ],
            ),
          ),
        if (_error != null) ...[
          ErrorNote(_error!),
          BusyButton(label: 'Thử lại', onPressed: _load),
        ] else if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (children != null && children.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Mascot(size: 110, animate: false),
                SizedBox(height: 12),
                Text(
                  'Chưa có hồ sơ bé nào.\nBấm "Thêm bé" để bắt đầu nhé!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20),
                ),
              ],
            ),
          )
        else
          for (final c in children ?? const <ChildProfile>[])
            _ChildCard(
              child: c,
              overview: _overview[c.id],
              starting: _startingId == c.id,
              onPlay: () => _play(c),
              onProgress: () => Navigator.of(
                context,
              ).pushNamed(Routes.childDashboard, arguments: c),
              onManage: () async {
                await Navigator.of(
                  context,
                ).pushNamed(Routes.childDetail, arguments: c);
                if (mounted) await _load();
              },
            ),
      ],
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({
    required this.child,
    required this.overview,
    required this.starting,
    required this.onPlay,
    required this.onProgress,
    required this.onManage,
  });

  final ChildProfile child;
  final ChildOverview? overview;
  final VoidCallback onProgress;
  final bool starting;
  final VoidCallback onPlay;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarBubble(avatarKey: child.avatarKey, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.nickname,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      child.isActive
                          ? '${child.activeDevices} thiết bị · mục tiêu ${child.dailyWordGoal} từ/ngày'
                          : 'Đang tắt',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Palette.inkSoft,
                      ),
                    ),
                    if (overview case final o?)
                      Text(
                        '⭐ ${o.stars} · 🔥 ${o.currentStreak} ngày · ${o.learnedWords}/${o.totalWords} từ · hôm nay ${formatDuration(o.minutesToday * 60)}',
                        style: const TextStyle(fontSize: 18),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: BusyButton(
                  label: 'Cho bé chơi',
                  icon: Icons.play_arrow_rounded,
                  busy: starting,
                  onPressed: child.isActive ? onPlay : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BusyButton(
                  label: 'Tiến độ',
                  icon: Icons.insights_rounded,
                  outlined: true,
                  onPressed: onProgress,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: onManage, child: const Text('Quản lý')),
        ],
      ),
    );
  }
}

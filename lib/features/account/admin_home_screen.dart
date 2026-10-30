import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/router.dart';
import '../../data/admin/admin_models.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import 'account_widgets.dart';

/// Trang của Admin: số liệu toàn hệ thống, trạng thái bản từ vựng đang phát và lối vào các màn quản trị.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key, this.service});

  final AdminService? service;

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  VocabStatus? _status;
  AdminStats? _stats;
  String? _statusError;
  String? _statsError;

  AuthService get _auth => AuthService.instance;
  late final AdminService _admin = widget.service ?? AdminService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Hai khối tải độc lập: một khối lỗi thì khối kia vẫn hiện.
  Future<void> _load() async {
    setState(() {
      _statusError = null;
      _statsError = null;
    });
    await Future.wait([
      _admin
          .vocabStatus()
          .then((v) {
            if (mounted) setState(() => _status = v);
          })
          .catchError((Object e) {
            if (mounted) setState(() => _statusError = friendlyError(e));
          }),
      _admin
          .stats()
          .then((v) {
            if (mounted) setState(() => _stats = v);
          })
          .catchError((Object e) {
            if (mounted) setState(() => _statsError = friendlyError(e));
          }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final me = _auth.parent;
    final s = _status;
    final st = _stats;
    return AccountScaffold(
      title: 'Quản trị',
      onRefresh: _load,
      children: [
        SectionCard(
          child: Row(
            children: [
              const Icon(Icons.admin_panel_settings_rounded, size: 44),
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
                      '${me?.email ?? ''} · Admin',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Palette.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Từ vựng đang phát cho app',
          child: _statusError != null
              ? ErrorNote(_statusError!)
              : s == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phiên bản ${s.publishedVersion ?? '—'} · ${s.activeWords} từ · ${s.activeCategories} chủ đề',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.hasUnpublishedChanges
                          ? 'Có thay đổi chưa xuất bản: app của bé chưa thấy.'
                          : 'Bản nháp trùng với bản đang phát.',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Palette.inkSoft,
                      ),
                    ),
                  ],
                ),
        ),
        SectionCard(
          title: 'Số liệu hệ thống',
          child: _statsError != null
              ? ErrorNote(_statsError!)
              : st == null
              ? const Center(child: CircularProgressIndicator())
              : _StatsBody(st),
        ),
        _NavButton(
          Icons.people_rounded,
          'Người dùng',
          () => Navigator.of(context).pushNamed(Routes.adminUsers),
        ),
        _NavButton(
          Icons.translate_rounded,
          'Từ vựng',
          () => Navigator.of(context).pushNamed(Routes.adminWords),
        ),
        _NavButton(
          Icons.category_rounded,
          'Chủ đề',
          () => Navigator.of(context).pushNamed(Routes.adminCategories),
        ),
        _NavButton(
          Icons.rate_review_rounded,
          'Góp ý nhận diện',
          () => Navigator.of(context).pushNamed(Routes.adminFeedback),
        ),
        _NavButton(Icons.publish_rounded, 'Xuất bản cho app', () async {
          await Navigator.of(context).pushNamed(Routes.adminPublish);
          if (mounted) _load();
        }),
        const SizedBox(height: 10),
        BusyButton(
          label: 'Về trang chủ',
          outlined: true,
          onPressed: () =>
              Navigator.of(context).popUntil(ModalRoute.withName(Routes.home)),
        ),
        const SizedBox(height: 10),
        BusyButton(
          label: 'Đăng xuất',
          onPressed: () async {
            await _auth.signOut();
            if (context.mounted) {
              Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
            }
          },
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: BusyButton(
      label: label,
      icon: icon,
      outlined: true,
      onPressed: onTap,
    ),
  );
}

class _StatsBody extends StatelessWidget {
  const _StatsBody(this.s);

  final AdminStats s;

  @override
  Widget build(BuildContext context) {
    Widget line(String a, String b) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(a, style: const TextStyle(fontSize: 18))),
          Text(
            b,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line('Phụ huynh', '${s.parents}'),
        line('Admin', '${s.admins}'),
        line('Tài khoản bị khoá', '${s.lockedAccounts}'),
        line('Phụ huynh mới (7 ngày)', '${s.newParents7d}'),
        const Divider(height: 22),
        line('Hồ sơ bé', '${s.children}'),
        line('Bé chơi hôm nay', '${s.activeToday}'),
        line('Bé chơi trong 7 ngày', '${s.active7d}'),
        line('Máy của bé đang liên kết', '${s.devices}'),
        const Divider(height: 22),
        line(
          'Ván đã chơi (7 ngày / tổng)',
          '${s.sessions7d} / ${s.sessionsTotal}',
        ),
        line('Phút chơi (7 ngày)', '${s.minutes7d}'),
        line('Tổng số sao của các bé', '${s.starsTotal}'),
        const Divider(height: 22),
        const Text(
          'Từ bé hay nhầm nhất',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        if (s.hardestWords.isEmpty)
          const Text(
            'Chưa đủ dữ liệu (mỗi từ cần ít nhất 5 lượt trả lời).',
            style: TextStyle(fontSize: 18, color: Palette.inkSoft),
          )
        else
          for (final w in s.hardestWords)
            line(
              '${w.en} · ${w.vi}',
              '${(w.wrongRate * 100).round()}% sai (${w.wrong}/${w.answers})',
            ),
      ],
    );
  }
}

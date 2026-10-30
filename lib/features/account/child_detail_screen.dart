import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/router.dart';
import '../../data/account/account_models.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import 'account_widgets.dart';
import 'child_form.dart';
import 'link_code_dialog.dart';

/// Quản lý một bé: thông tin, mục tiêu/giới hạn, các thiết bị đang đăng nhập, xoá hồ sơ.
class ChildDetailScreen extends StatefulWidget {
  const ChildDetailScreen({super.key, required this.initial});

  final ChildProfile initial;

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  late ChildProfile _child = widget.initial;
  late bool _active = widget.initial.isActive;
  late int _goal = widget.initial.dailyWordGoal;
  late bool _limitOn = widget.initial.dailyLimitMinutes != null;
  late int _limit = widget.initial.dailyLimitMinutes ?? 30;
  List<DeviceSession>? _devices;
  String? _devicesError;
  bool _savingGoal = false;

  AuthService get _auth => AuthService.instance;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _devicesError = null);
    try {
      final d = await _auth.childDevices(_child.id);
      if (mounted) setState(() => _devices = d);
    } catch (e) {
      if (mounted) setState(() => _devicesError = friendlyError(e));
    }
  }

  Future<void> _saveInfo(String nickname, String? avatar, int? year) async {
    final updated = await _auth.updateChild(
      _child.id,
      nickname: nickname,
      avatarKey: avatar,
      birthYear: year,
      isActive: _active,
    );
    if (!mounted) return;
    setState(() => _child = updated);
    toast(context, 'Đã lưu thông tin.');
  }

  Future<void> _saveGoal() async {
    setState(() => _savingGoal = true);
    try {
      final updated = await _auth.updateChildSettings(
        _child.id,
        dailyLimitMinutes: _limitOn ? _limit : null,
        dailyWordGoal: _goal,
      );
      if (!mounted) return;
      setState(() => _child = updated);
      toast(context, 'Đã lưu mục tiêu và giới hạn.');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _savingGoal = false);
    }
  }

  Future<void> _revoke(DeviceSession s) async {
    final ok = await confirmDialog(
      context,
      title: 'Gỡ "${s.deviceName}"?',
      message:
          'Máy đó sẽ bị đăng xuất khỏi hồ sơ của ${_child.nickname}. Muốn dùng lại cần nhập mã liên kết mới.',
      confirmLabel: 'Gỡ máy',
    );
    if (!ok) return;
    try {
      await _auth.revokeDevice(_child.id, s.id);
      await _loadDevices();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _revokeAll() async {
    final ok = await confirmDialog(
      context,
      title: 'Gỡ tất cả thiết bị?',
      message: 'Mọi máy của ${_child.nickname} sẽ bị đăng xuất.',
      confirmLabel: 'Gỡ hết',
    );
    if (!ok) return;
    try {
      await _auth.revokeAllDevices(_child.id);
      await _loadDevices();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _resetProgress() async {
    final ok = await confirmDialog(
      context,
      title: 'Xoá tiến độ của ${_child.nickname}?',
      message:
          'Sao, huy hiệu, từ đã học và lịch sử chơi của bé trên mọi máy sẽ bị xoá. Hồ sơ và các máy của bé vẫn giữ.',
      confirmLabel: 'Xoá tiến độ',
      cancelLabel: 'Giữ lại',
    );
    if (!ok) return;
    try {
      await _auth.resetChildProgress(_child.id);
      if (_auth.activeChild?.id == _child.id) {
        await SyncService.instance.discardPendingAndHydrate();
      }
      if (mounted) toast(context, 'Đã xoá tiến độ của bé.');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Xoá hồ sơ ${_child.nickname}?',
      message:
          'Toàn bộ dữ liệu học của bé trên máy chủ sẽ bị xoá và không khôi phục được.',
      confirmLabel: 'Xoá hồ sơ',
      cancelLabel: 'Giữ lại',
    );
    if (!ok) return;
    try {
      await _auth.deleteChild(_child.id);
      if (!mounted) return;
      toast(context, 'Đã xoá hồ sơ.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AccountScaffold(
      title: _child.nickname,
      children: [
        SectionCard(
          title: 'Thông tin',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Hồ sơ đang bật',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Tắt thì bé không đăng nhập được'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 8),
              ChildForm(
                key: ValueKey(
                  '${_child.id}-${_child.nickname}-${_child.avatarKey}',
                ),
                submitLabel: 'Lưu thông tin',
                initialNickname: _child.nickname,
                initialAvatar: _child.avatarKey,
                initialBirthYear: _child.birthYear,
                onSubmit: _saveInfo,
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Mục tiêu & giới hạn',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mục tiêu mỗi ngày', style: TextStyle(fontSize: 18)),
              NumberStepper(
                value: _goal,
                min: 1,
                max: 50,
                unit: 'từ',
                onChanged: (v) => setState(() => _goal = v),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Giới hạn thời gian chơi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                value: _limitOn,
                onChanged: (v) => setState(() => _limitOn = v),
              ),
              if (_limitOn)
                NumberStepper(
                  value: _limit,
                  min: 5,
                  max: 600,
                  step: 5,
                  unit: 'phút/ngày',
                  onChanged: (v) => setState(() => _limit = v),
                ),
              const SizedBox(height: 12),
              BusyButton(
                label: 'Lưu mục tiêu',
                busy: _savingGoal,
                onPressed: _saveGoal,
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Thiết bị của bé',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_devicesError != null) ErrorNote(_devicesError!),
              if (_devices == null && _devicesError == null)
                const Center(child: CircularProgressIndicator())
              else if (_devices != null && _devices!.isEmpty)
                const Text(
                  'Chưa có thiết bị nào đăng nhập.',
                  style: TextStyle(fontSize: 18, color: Palette.inkSoft),
                ),
              for (final s in _devices ?? const <DeviceSession>[])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.smartphone_rounded, size: 32),
                  title: Text(
                    s.deviceName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Dùng ${relativeTime(s.lastUsedAt ?? s.createdAt, now)}',
                    style: const TextStyle(fontSize: 18),
                  ),
                  trailing: IconButton(
                    iconSize: 30,
                    tooltip: 'Gỡ máy này',
                    icon: const Icon(Icons.link_off_rounded),
                    onPressed: () => _revoke(s),
                  ),
                ),
              const SizedBox(height: 8),
              BusyButton(
                label: 'Thêm máy cho bé (nhập mã)',
                icon: Icons.add_link_rounded,
                onPressed: () async {
                  await showLinkCodeDialog(
                    context,
                    childName: _child.nickname,
                    create: () => _auth.createLinkCode(_child.id),
                  );
                  if (mounted) await _loadDevices();
                },
              ),
              if ((_devices?.length ?? 0) > 1)
                TextButton(
                  onPressed: _revokeAll,
                  child: const Text('Gỡ tất cả thiết bị'),
                ),
            ],
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: _resetProgress,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Xoá tiến độ học của bé'),
          ),
        ),
        Center(
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade800),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Xoá hồ sơ này'),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(
              context,
            ).popUntil(ModalRoute.withName(Routes.children)),
            child: const Text('Về danh sách bé'),
          ),
        ),
      ],
    );
  }
}

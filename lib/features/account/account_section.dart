import 'package:flutter/material.dart';

import '../../core/router.dart';
import '../../services/auth_service.dart';
import 'account_widgets.dart';

/// Các mục tài khoản ở đầu màn Cài đặt (nằm sau cổng phụ huynh):
/// khách → đăng nhập hoặc nhập mã liên kết; đã đăng nhập → vào khu hồ sơ bé; máy của bé → gỡ liên kết.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final tiles = <Widget>[];
        final parent = auth.parent;
        if (parent != null) {
          tiles.add(
            _tile(
              icon: auth.isAdmin
                  ? Icons.admin_panel_settings_rounded
                  : Icons.family_restroom_rounded,
              title: parent.fullName.isEmpty ? parent.email : parent.fullName,
              subtitle: auth.isAdmin
                  ? 'Quản trị viên · ${parent.email}'
                  : 'Hồ sơ của bé · ${parent.email}',
              onTap: () => Navigator.of(
                context,
              ).pushNamed(auth.isAdmin ? Routes.adminHome : Routes.children),
            ),
          );
        } else {
          tiles.add(
            _tile(
              icon: Icons.account_circle_outlined,
              title: 'Đăng nhập / Đăng ký',
              subtitle: 'Để lưu tiến độ và xem báo cáo của bé',
              onTap: () => Navigator.of(context).pushNamed(Routes.login),
            ),
          );
        }
        if (auth.inChildMode) {
          tiles.add(
            _tile(
              icon: Icons.child_care_rounded,
              title:
                  'Bé đang dùng máy này: ${auth.activeChild?.nickname ?? ''}',
              subtitle: parent == null
                  ? 'Chạm để gỡ máy này khỏi hồ sơ bé'
                  : 'Chạm để thoát chế độ bé',
              onTap: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Thoát chế độ bé?',
                  message: 'Máy này sẽ không còn gắn với hồ sơ của bé nữa.',
                  confirmLabel: 'Thoát',
                );
                if (ok) await auth.leaveChildMode();
              },
            ),
          );
        } else if (parent == null) {
          tiles.add(
            _tile(
              icon: Icons.link_rounded,
              title: 'Máy của bé? Nhập mã liên kết',
              subtitle: 'Bố mẹ tạo mã trên máy của họ',
              onTap: () => Navigator.of(context).pushNamed(Routes.childLink),
            ),
          );
        }
        return Column(children: tiles);
      },
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Icon(icon, size: 32),
          title: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 18)),
          onTap: onTap,
        ),
      ),
    );
  }
}

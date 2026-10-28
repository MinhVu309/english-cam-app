import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'pack_manifest.dart';

/// Nơi lưu gói từ vựng đã tải về: `<root>/current/` là bản đang dùng.
/// Cập nhật ghi vào `staging/` rồi đổi tên sang `current/`, nên mất mạng hay tắt
/// app giữa chừng cũng không làm hỏng bản đang dùng.
class PackStore {
  PackStore(this.root);

  /// Có giá trị sau khi [open] thành công; null nghĩa là chỉ dùng dữ liệu đóng gói sẵn.
  static PackStore? instance;

  final Directory root;

  Directory get current => Directory('${root.path}/current');
  Directory get staging => Directory('${root.path}/staging');
  Directory get _old => Directory('${root.path}/old');

  /// Đường dẫn bắt đầu bằng `assets/` là asset đóng gói; còn lại thuộc gói đã tải.
  static bool isBundled(String path) => path.startsWith('assets/');

  /// Mở kho trong thư mục riêng của app. Lỗi plugin/ổ đĩa thì trả null (app vẫn chạy).
  static Future<PackStore?> open() async {
    try {
      final base = await getApplicationSupportDirectory();
      final store = PackStore(Directory('${base.path}/vocab_pack'));
      await store.recover();
      return instance = store;
    } catch (e) {
      debugPrint('PackStore.open failed: $e');
      return instance = null;
    }
  }

  /// Dọn dấu vết của lần cập nhật bị ngắt giữa chừng.
  Future<void> recover() async {
    if (!await current.exists() && await _old.exists()) {
      await _old.rename(current.path);
    }
    for (final d in [staging, _old]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  }

  /// File trong gói đang dùng, hoặc null nếu không có / đường dẫn không an toàn.
  File? fileFor(String relative) {
    if (!isSafePackPath(relative)) return null;
    final f = File('${current.path}/$relative');
    return f.existsSync() ? f : null;
  }

  /// Manifest của gói đang cài; null nếu chưa cài hoặc file hỏng.
  PackManifest? readInstalled() {
    try {
      final f = File('${current.path}/$kPackManifestFile');
      if (!f.existsSync()) return null;
      return PackManifest.fromJson(jsonDecode(f.readAsStringSync()));
    } catch (e) {
      debugPrint('Installed pack manifest unreadable: $e');
      return null;
    }
  }

  Future<Directory> beginStaging() async {
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    return staging;
  }

  Future<void> discardStaging() async {
    if (await staging.exists()) await staging.delete(recursive: true);
  }

  /// Đổi `staging/` thành `current/`; lỗi thì khôi phục bản cũ.
  Future<void> commit() async {
    if (await _old.exists()) await _old.delete(recursive: true);
    final hadCurrent = await current.exists();
    if (hadCurrent) await current.rename(_old.path);
    try {
      await staging.rename(current.path);
    } catch (e) {
      if (hadCurrent) await _old.rename(current.path);
      rethrow;
    }
    if (await _old.exists()) await _old.delete(recursive: true);
  }

  /// Xoá gói đã tải, quay về dữ liệu đóng gói sẵn.
  Future<void> clear() async {
    if (await current.exists()) await current.delete(recursive: true);
  }
}

import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'key_value_store.dart';

/// Mã và tên của máy này, gửi kèm khi bé đăng nhập để phụ huynh thấy "Máy của bé (Samsung SM-A515F)" và thu hồi riêng từng máy.
class DeviceInfo {
  const DeviceInfo(this.id, this.name);

  final String id;
  final String name;
}

abstract interface class DeviceIdentity {
  Future<DeviceInfo> get();
}

/// Android không cho app đọc mã phần cứng cố định, nên sinh một mã ngẫu nhiên lưu trong Keystore (sống đến khi gỡ app).
/// Tên máy lấy từ `device_info_plus` cho dễ đọc; lỗi thì dùng tên chung.
class StoredDeviceIdentity implements DeviceIdentity {
  StoredDeviceIdentity(this._store);

  static const _key = 'device.id';
  final KeyValueStore _store;
  DeviceInfo? _cached;

  @override
  Future<DeviceInfo> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    var id = await _store.read(_key);
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      id = List.generate(
        16,
        (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await _store.write(_key, id);
    }
    return _cached = DeviceInfo(id, await _name());
  }

  Future<String> _name() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final name = '${info.manufacturer} ${info.model}'.trim();
      return name.isEmpty ? 'Điện thoại Android' : name;
    } catch (e) {
      debugPrint('DeviceInfo failed: $e');
      return 'Điện thoại Android';
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../vocab_repository.dart';
import 'pack_manifest.dart';
import 'pack_store.dart';
import 'sha256.dart';

/// Lỗi cập nhật có thông điệp tiếng Việt để hiện cho phụ huynh.
class PackUpdateException implements Exception {
  const PackUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PackUpdateResult {
  const PackUpdateResult({required this.changed, required this.manifest});

  /// false nghĩa là máy đã có bản mới nhất.
  final bool changed;
  final PackManifest manifest;
}

const Duration _kConnectTimeout = Duration(seconds: 15);
const Duration _kIdleTimeout = Duration(seconds: 30);
const int _kMaxManifestBytes = 1024 * 1024;

/// Tải gói từ vựng từ một địa chỉ hosting tĩnh, kiểm tra từng file bằng SHA-256,
/// chỉ thay bản đang dùng khi mọi thứ đều đúng. Chỉ gửi yêu cầu GET, không gửi dữ liệu nào đi.
class PackUpdater {
  PackUpdater(this.store, {bool? allowInsecure, HttpClient Function()? client})
    : allowInsecure = allowInsecure ?? kDebugMode,
      _clientFactory = client ?? HttpClient.new;

  final PackStore store;

  /// Cho phép `http://` (chỉ để thử nghiệm nội bộ); bản release luôn bắt buộc https.
  final bool allowInsecure;
  final HttpClient Function() _clientFactory;

  /// Chuẩn hoá địa chỉ người dùng nhập thành thư mục gốc của gói (kết thúc bằng `/`).
  Uri parseBase(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      throw const PackUpdateException('Chưa nhập địa chỉ gói từ vựng.');
    }
    if (text.endsWith(kPackManifestFile)) {
      text = text.substring(0, text.length - kPackManifestFile.length);
    }
    final uri = Uri.tryParse(text);
    final okScheme =
        uri != null &&
        (uri.scheme == 'https' || (allowInsecure && uri.scheme == 'http'));
    if (uri == null || !okScheme || uri.host.isEmpty) {
      throw PackUpdateException(
        allowInsecure
            ? 'Địa chỉ phải bắt đầu bằng https:// (hoặc http:// khi thử nghiệm).'
            : 'Địa chỉ phải bắt đầu bằng https://',
      );
    }
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    );
  }

  /// Chỉ hỏi máy chủ bản mới nhất (tải đúng một `manifest.json` nhỏ, không tải gì khác).
  /// Dùng để biết có bản từ vựng mới hay chưa mà không phải tải cả gói.
  Future<PackManifest> fetchLatest(String baseUrl) {
    final base = parseBase(baseUrl);
    return _withClient((client) => _fetchManifest(client, base));
  }

  /// Kiểm tra và cập nhật. [onProgress] nhận (số file xong, tổng số file).
  Future<PackUpdateResult> update(
    String baseUrl, {
    void Function(int done, int total)? onProgress,
  }) async {
    final base = parseBase(baseUrl);
    return _withClient((client) async {
      final manifest = await _fetchManifest(client, base);
      final installed = store.readInstalled();
      if (installed != null && installed.version >= manifest.version) {
        return PackUpdateResult(changed: false, manifest: installed);
      }

      final staging = await store.beginStaging();
      try {
        var done = 0;
        onProgress?.call(0, manifest.files.length);
        for (final f in manifest.files) {
          final dest = File('${staging.path}/${f.path}');
          await dest.parent.create(recursive: true);
          final reusable = installed?.file(f.path)?.sha256 == f.sha256
              ? store.fileFor(f.path)
              : null;
          if (reusable != null) {
            await reusable.copy(dest.path); // file không đổi: khỏi tải lại
          } else {
            await _download(client, base.resolve(f.path), dest, f);
          }
          onProgress?.call(++done, manifest.files.length);
        }
        await _validate(staging, manifest);
        await File(
          '${staging.path}/$kPackManifestFile',
        ).writeAsString(jsonEncode(manifest.toJson()));
        await store.commit();
      } catch (_) {
        await store.discardStaging();
        rethrow;
      }
      return PackUpdateResult(changed: true, manifest: manifest);
    });
  }

  /// Tạo HttpClient, chạy [body], đổi lỗi mạng/định dạng sang [PackUpdateException] tiếng Việt, rồi đóng client.
  Future<T> _withClient<T>(Future<T> Function(HttpClient client) body) async {
    final client = _clientFactory()..connectionTimeout = _kConnectTimeout;
    try {
      return await body(client);
    } on PackUpdateException {
      rethrow;
    } on FormatException catch (e) {
      throw PackUpdateException('Gói từ vựng không hợp lệ: ${e.message}');
    } on TimeoutException {
      throw const PackUpdateException('Kết nối quá chậm, thử lại sau nhé.');
    } on SocketException {
      throw const PackUpdateException(
        'Không kết nối được. Kiểm tra mạng và địa chỉ gói.',
      );
    } on HandshakeException {
      throw const PackUpdateException(
        'Không thiết lập được kết nối an toàn (https).',
      );
    } on FileSystemException catch (e) {
      throw PackUpdateException('Không ghi được file vào máy: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<PackManifest> _fetchManifest(HttpClient client, Uri base) async {
    final req = await client.getUrl(base.resolve(kPackManifestFile));
    final res = await req.close().timeout(_kIdleTimeout);
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw PackUpdateException(
        'Không tìm thấy $kPackManifestFile (máy chủ trả mã ${res.statusCode}).',
      );
    }
    final bytes = <int>[];
    await for (final chunk in res.timeout(_kIdleTimeout)) {
      bytes.addAll(chunk);
      if (bytes.length > _kMaxManifestBytes) {
        throw const PackUpdateException('manifest.json quá lớn.');
      }
    }
    return PackManifest.fromJson(jsonDecode(utf8.decode(bytes)));
  }

  Future<void> _download(
    HttpClient client,
    Uri uri,
    File dest,
    PackFile expected,
  ) async {
    final req = await client.getUrl(uri);
    final res = await req.close().timeout(_kIdleTimeout);
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw PackUpdateException(
        'Không tải được ${expected.path} (mã ${res.statusCode}).',
      );
    }
    final hash = Sha256();
    var received = 0;
    final sink = dest.openWrite();
    try {
      await for (final chunk in res.timeout(_kIdleTimeout)) {
        received += chunk.length;
        if (received > expected.size) {
          throw PackUpdateException('${expected.path} lớn hơn khai báo.');
        }
        hash.add(chunk);
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    if (received != expected.size || hash.close() != expected.sha256) {
      throw PackUpdateException(
        '${expected.path} bị lỗi khi tải (sai kích thước hoặc mã băm).',
      );
    }
  }

  /// Kiểm tra nội dung trước khi thay bản đang dùng.
  Future<void> _validate(Directory dir, PackManifest manifest) async {
    try {
      VocabRepository.fromJsonString(
        await File('${dir.path}/$kPackVocabFile').readAsString(),
      );
    } catch (e) {
      throw PackUpdateException('$kPackVocabFile không hợp lệ: $e');
    }
    if (manifest.hasModel) {
      final labels = (await File(
        '${dir.path}/$kPackLabelsFile',
      ).readAsLines()).where((l) => l.trim().isNotEmpty);
      if (labels.length < 2) {
        throw const PackUpdateException('labels.txt cần ít nhất 2 nhãn.');
      }
      final head = await File(
        '${dir.path}/$kPackModelFile',
      ).openRead(0, 8).expand((c) => c).toList();
      final magic = head.length == 8
          ? String.fromCharCodes(head.sublist(4))
          : '';
      if (magic != 'TFL3') {
        throw const PackUpdateException('model.tflite không phải file TFLite.');
      }
    }
  }
}

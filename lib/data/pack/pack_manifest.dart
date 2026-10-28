/// Mô tả một "gói từ vựng" đặt trên hosting (xem docs/VOCAB_PACK.md).
///
/// Gói là một thư mục file tĩnh: `manifest.json`, `vocab.json` (bắt buộc), tuỳ chọn
/// `model.tflite` + `labels.txt` (đi cùng nhau), và các file âm thanh/ảnh mà
/// `vocab.json` tham chiếu bằng đường dẫn tương đối (vd. `audio/words/dog.mp3`).
library;

const String kPackManifestFile = 'manifest.json';
const String kPackVocabFile = 'vocab.json';
const String kPackModelFile = 'model.tflite';
const String kPackLabelsFile = 'labels.txt';

/// Giới hạn để một manifest sai/độc hại không làm đầy bộ nhớ máy.
const int kPackMaxFiles = 2000;
const int kPackMaxFileBytes = 30 * 1024 * 1024;

final RegExp _segment = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.\-]*$');
final RegExp _sha = RegExp(r'^[0-9a-f]{64}$');

/// Đường dẫn tương đối an toàn: không `..`, không bắt đầu bằng `/`, không ký tự lạ.
bool isSafePackPath(String path) {
  if (path.isEmpty || path.length > 200) return false;
  final parts = path.split('/');
  return parts.every(_segment.hasMatch);
}

class PackFile {
  const PackFile({
    required this.path,
    required this.sha256,
    required this.size,
  });

  final String path;
  final String sha256;
  final int size;

  Map<String, dynamic> toJson() => {
    'path': path,
    'sha256': sha256,
    'size': size,
  };
}

class PackManifest {
  const PackManifest({required this.version, required this.files, this.notes});

  /// Số nguyên tăng dần; app chỉ cập nhật khi lớn hơn bản đang cài.
  final int version;

  /// Ghi chú thay đổi (hiện cho phụ huynh), tuỳ chọn.
  final String? notes;
  final List<PackFile> files;

  PackFile? file(String path) {
    for (final f in files) {
      if (f.path == path) return f;
    }
    return null;
  }

  bool get hasModel => file(kPackModelFile) != null;

  /// Ném [FormatException] nếu manifest sai cấu trúc hoặc không an toàn.
  factory PackManifest.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('manifest không phải một đối tượng JSON');
    }
    final version = json['version'];
    if (version is! int || version < 1) {
      throw const FormatException('"version" phải là số nguyên >= 1');
    }
    final rawFiles = json['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      throw const FormatException('"files" phải là danh sách không rỗng');
    }
    if (rawFiles.length > kPackMaxFiles) {
      throw FormatException('quá $kPackMaxFiles file trong gói');
    }
    final files = <PackFile>[];
    final seen = <String>{};
    for (final raw in rawFiles) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('mục trong "files" sai định dạng');
      }
      final path = raw['path'];
      final sha = raw['sha256'];
      final size = raw['size'];
      if (path is! String || !isSafePackPath(path)) {
        throw FormatException('đường dẫn không hợp lệ: $path');
      }
      if (path == kPackManifestFile) {
        throw const FormatException('manifest không được tự liệt kê chính nó');
      }
      if (!seen.add(path)) throw FormatException('trùng đường dẫn: $path');
      if (sha is! String || !_sha.hasMatch(sha)) {
        throw FormatException('sha256 của $path phải là 64 ký tự hex thường');
      }
      if (size is! int || size < 0 || size > kPackMaxFileBytes) {
        throw FormatException('size của $path không hợp lệ');
      }
      files.add(PackFile(path: path, sha256: sha, size: size));
    }
    if (!seen.contains(kPackVocabFile)) {
      throw const FormatException('gói thiếu $kPackVocabFile');
    }
    if (seen.contains(kPackModelFile) != seen.contains(kPackLabelsFile)) {
      throw const FormatException(
        '$kPackModelFile và $kPackLabelsFile phải đi cùng nhau',
      );
    }
    final notes = json['notes'];
    return PackManifest(
      version: version,
      files: files,
      notes: notes is String && notes.trim().isNotEmpty ? notes.trim() : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    if (notes != null) 'notes': notes,
    'files': [for (final f in files) f.toJson()],
  };
}

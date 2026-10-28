// Tạo / kiểm tra "gói từ vựng" để đặt lên hosting (xem docs/VOCAB_PACK.md).
//
//   dart run tool/build_pack.dart init <thư-mục>                       # tạo thư mục gói từ vocab.json hiện tại
//   dart run tool/build_pack.dart build <thư-mục> --version N [--notes "..."]
//                                                                      # kiểm tra rồi ghi manifest.json
//
// Chạy từ thư mục gốc của project. Thoát với mã 1 nếu có lỗi.
import 'dart:convert';
import 'dart:io';

import 'package:english_cam/data/pack/pack_manifest.dart';
import 'package:english_cam/data/pack/sha256.dart';

void main(List<String> args) {
  if (args.length >= 2 && args[0] == 'init') {
    _init(Directory(args[1]));
  } else if (args.length >= 2 && args[0] == 'build') {
    _build(Directory(args[1]), args.sublist(2));
  } else {
    stderr.writeln(
      'Cách dùng:\n'
      '  dart run tool/build_pack.dart init <thư-mục>\n'
      '  dart run tool/build_pack.dart build <thư-mục> --version N [--notes "..."]',
    );
    exit(64);
  }
}

void _init(Directory dir) {
  final vocab = File('assets/vocab/vocab.json');
  if (!vocab.existsSync()) {
    stderr.writeln('Chạy từ thư mục gốc project (không thấy ${vocab.path}).');
    exit(1);
  }
  if (File('${dir.path}/$kPackVocabFile').existsSync()) {
    stderr.writeln('${dir.path} đã có $kPackVocabFile, không ghi đè.');
    exit(1);
  }
  dir.createSync(recursive: true);
  vocab.copySync('${dir.path}/$kPackVocabFile');
  stdout.writeln(
    'Đã tạo ${dir.path}/$kPackVocabFile từ bản đóng gói sẵn.\n'
    'Thêm từ mới vào đó (đường dẫn file của từ mới là tương đối, vd. '
    '"audio/words/dog.mp3"), đặt file vào thư mục, rồi chạy lệnh build.',
  );
}

void _build(Directory dir, List<String> opts) {
  int? version;
  String? notes;
  for (var i = 0; i < opts.length; i++) {
    if (opts[i] == '--version' && i + 1 < opts.length) {
      version = int.tryParse(opts[++i]);
    } else if (opts[i] == '--notes' && i + 1 < opts.length) {
      notes = opts[++i];
    }
  }
  if (version == null || version < 1) {
    stderr.writeln('Thiếu hoặc sai --version (số nguyên >= 1).');
    exit(64);
  }
  final errors = <String>[];
  final warnings = <String>[];

  // 1) Liệt kê file (bỏ manifest.json và file ẩn như .DS_Store).
  final files = <PackFile>[];
  final paths = <String>{};
  final root = dir.absolute.path;
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = e.absolute.path.substring(root.length + 1);
    if (rel.split('/').any((p) => p.startsWith('.')) ||
        rel == kPackManifestFile) {
      continue;
    }
    if (!isSafePackPath(rel)) {
      errors.add('tên file không hợp lệ (chỉ chữ, số, _ - .): $rel');
      continue;
    }
    final size = e.lengthSync();
    if (size > kPackMaxFileBytes) {
      errors.add('$rel lớn hơn ${kPackMaxFileBytes ~/ (1024 * 1024)} MB');
    }
    final hash = Sha256();
    final raf = e.openSync();
    try {
      while (true) {
        final chunk = raf.readSync(1 << 20);
        if (chunk.isEmpty) break;
        hash.add(chunk);
      }
    } finally {
      raf.closeSync();
    }
    paths.add(rel);
    files.add(PackFile(path: rel, sha256: hash.close(), size: size));
  }
  files.sort((a, b) => a.path.compareTo(b.path));

  // 2) Kiểm tra vocab.json.
  final vocabFile = File('${dir.path}/$kPackVocabFile');
  if (!vocabFile.existsSync()) {
    stderr.writeln('Thiếu ${vocabFile.path}.');
    exit(1);
  }
  final labels = <String>{};
  try {
    final json =
        jsonDecode(vocabFile.readAsStringSync()) as Map<String, dynamic>;
    final categories = {
      for (final c in json['categories'] as List<dynamic>)
        (c as Map<String, dynamic>)['id'] as String,
    };
    final words = (json['words'] as List<dynamic>).cast<Map<String, dynamic>>();
    final ids = <String>{};
    var pictured = 0;
    for (final w in words) {
      final id = w['id'] as String? ?? '?';
      for (final f in [
        'id',
        'en',
        'vi',
        'phonetic',
        'exampleEn',
        'exampleVi',
        'audio',
        'category',
      ]) {
        final v = w[f];
        if (v is! String || v.trim().isEmpty) errors.add('[$id] thiếu "$f"');
      }
      if (!ids.add(id)) errors.add('[$id] id bị trùng');
      if (!categories.contains(w['category'])) {
        errors.add('[$id] chủ đề "${w['category']}" không tồn tại');
      }
      final label = w['label'];
      if (label is String && !labels.add(label)) {
        errors.add('[$id] label "$label" bị trùng');
      }
      if (w['image'] != null || w['emoji'] != null) pictured++;
      for (final k in ['audio', 'exampleAudio', 'image']) {
        final path = w[k] as String?;
        if (path == null) continue;
        if (path.startsWith('assets/')) {
          if (!File(path).existsSync()) {
            warnings.add(
              '[$id] $k "$path" không có trong app (chạy từ thư mục gốc project?)',
            );
          }
        } else if (!paths.contains(path)) {
          errors.add('[$id] $k "$path" không có trong thư mục gói');
        }
      }
    }
    if (pictured < 4) errors.add('cần ít nhất 4 từ có ảnh hoặc emoji');
    stdout.writeln(
      '${words.length} từ · ${words.where((w) => w['label'] == null).length} chỉ để học',
    );
  } catch (e) {
    errors.add('$kPackVocabFile không hợp lệ: $e');
  }

  // 3) Model đi kèm labels.
  final hasModel = paths.contains(kPackModelFile);
  if (hasModel != paths.contains(kPackLabelsFile)) {
    errors.add('$kPackModelFile và $kPackLabelsFile phải đi cùng nhau');
  }
  if (hasModel && paths.contains(kPackLabelsFile)) {
    final modelLabels = File(
      '${dir.path}/$kPackLabelsFile',
    ).readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty).toSet();
    for (final l in modelLabels.difference(labels)) {
      warnings.add(
        'model nhận ra "$l" nhưng vocab.json chưa có từ nào dùng label này',
      );
    }
    for (final l in labels.difference(modelLabels)) {
      warnings.add(
        'vocab.json có label "$l" mà model mới không nhận ra (game Tìm vật sẽ bỏ qua)',
      );
    }
  }

  // 4) Ghi manifest (kiểm tra lại bằng chính bộ phân tích mà app dùng).
  if (errors.isEmpty) {
    try {
      final manifest = PackManifest(
        version: version,
        notes: notes,
        files: files,
      );
      PackManifest.fromJson(manifest.toJson());
      File('${dir.path}/$kPackManifestFile').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
      );
      final total = files.fold<int>(0, (a, f) => a + f.size);
      stdout.writeln(
        'Đã ghi ${dir.path}/$kPackManifestFile: bản $version, ${files.length} file, '
        '${(total / 1024).toStringAsFixed(0)} KB${hasModel ? ', có model' : ''}',
      );
    } on FormatException catch (e) {
      errors.add('manifest: ${e.message}');
    }
  }
  for (final w in warnings) {
    stdout.writeln('  cảnh báo: $w');
  }
  for (final e in errors) {
    stderr.writeln('  LỖI: $e');
  }
  exit(errors.isEmpty ? 0 : 1);
}

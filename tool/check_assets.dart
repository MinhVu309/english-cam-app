// Kiểm tra nhãn model ↔ vocab.json ↔ ảnh ↔ âm thanh.
//
//   dart run tool/check_assets.dart                  # thiếu âm thanh là lỗi
//   dart run tool/check_assets.dart --lenient-audio  # thiếu âm thanh chỉ cảnh báo
//
// Thoát với mã 1 nếu có lỗi.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final requireAudio = !args.contains('--lenient-audio');
  final errors = <String>[];
  final warnings = <String>[];

  final labelsFile = File('assets/ml/labels.txt');
  final vocabFile = File('assets/vocab/vocab.json');
  if (!labelsFile.existsSync() || !vocabFile.existsSync()) {
    stderr.writeln(
      'Thiếu assets/ml/labels.txt hoặc assets/vocab/vocab.json '
      '(chạy từ thư mục gốc của project).',
    );
    exit(1);
  }

  final labels = labelsFile
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final json = jsonDecode(vocabFile.readAsStringSync()) as Map<String, dynamic>;
  final categories = {
    for (final c in json['categories'] as List<dynamic>)
      (c as Map<String, dynamic>)['id'] as String,
  };
  final words = (json['words'] as List<dynamic>).cast<Map<String, dynamic>>();

  const requiredFields = [
    'id',
    'label',
    'en',
    'vi',
    'phonetic',
    'exampleEn',
    'exampleVi',
    'audio',
    'category',
  ];

  final seenIds = <String>{};
  final seenLabels = <String>{};
  for (final w in words) {
    final id = w['id'] as String? ?? '?';
    for (final f in requiredFields) {
      final v = w[f];
      if (v is! String || v.trim().isEmpty) {
        errors.add('[$id] thiếu trường "$f"');
      }
    }
    if (!seenIds.add(id)) errors.add('[$id] id bị trùng');
    final label = w['label'] as String? ?? '';
    if (!seenLabels.add(label)) errors.add('[$id] label "$label" bị trùng');
    if (!categories.contains(w['category'])) {
      errors.add('[$id] category "${w['category']}" không có trong categories');
    }

    // Hình minh hoạ: ảnh asset (phải tồn tại nếu khai báo) hoặc emoji.
    final image = w['image'] as String?;
    final emoji = w['emoji'] as String?;
    if (image != null && !File(image).existsSync()) {
      errors.add('[$id] thiếu file ảnh $image');
    }
    if (image == null && (emoji == null || emoji.isEmpty)) {
      warnings.add('[$id] không có ảnh lẫn emoji, sẽ hiện chữ cái đầu');
    }

    // Âm thanh: tên file = id.
    for (final key in ['audio', 'exampleAudio']) {
      final path = w[key] as String?;
      if (path == null) continue;
      if (!path.endsWith('/$id.mp3')) {
        errors.add('[$id] $key "$path" phải kết thúc bằng /$id.mp3');
      }
      if (!File(path).existsSync()) {
        (requireAudio ? errors : warnings).add('[$id] thiếu file $key $path');
      }
    }
  }

  // Hiệu ứng và nhạc nền dùng chung (AudioService).
  const sharedAudio = [
    'assets/audio/sfx/tap.mp3',
    'assets/audio/sfx/correct.mp3',
    'assets/audio/sfx/wrong.mp3',
    'assets/audio/sfx/star.mp3',
    'assets/audio/music/bg.mp3',
  ];
  for (final path in sharedAudio) {
    if (!File(path).existsSync()) {
      (requireAudio ? errors : warnings).add('thiếu file âm thanh $path');
    }
  }

  // Mọi nhãn của model phải có từ vựng, và ngược lại.
  for (final l in labels) {
    if (!seenLabels.contains(l)) {
      errors.add('Nhãn model "$l" chưa có trong vocab.json');
    }
  }
  for (final l in seenLabels) {
    if (!labels.contains(l)) {
      errors.add('vocab.json có label "$l" không nằm trong labels.txt');
    }
  }

  stdout.writeln(
    '${labels.length} nhãn · ${words.length} từ · '
    '${errors.length} lỗi · ${warnings.length} cảnh báo',
  );
  final missingAudio = warnings.where((w) => w.contains('thiếu file')).length;
  for (final w in warnings.where((w) => !w.contains('thiếu file'))) {
    stdout.writeln('  cảnh báo: $w');
  }
  if (missingAudio > 0) {
    stdout.writeln(
      '  cảnh báo: thiếu $missingAudio file âm thanh '
      '(bỏ --lenient-audio để coi là lỗi)',
    );
  }
  for (final e in errors) {
    stderr.writeln('  LỖI: $e');
  }
  exit(errors.isEmpty ? 0 : 1);
}

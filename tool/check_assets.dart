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
    // `label` là tuỳ chọn: từ không có label chỉ để học, model chưa nhận diện được.
    final label = w['label'];
    if (label != null) {
      if (label is! String || label.trim().isEmpty) {
        errors.add('[$id] "label" phải là chuỗi không rỗng hoặc bỏ hẳn');
      } else if (!seenLabels.add(label)) {
        errors.add('[$id] label "$label" bị trùng');
      }
    }
    if (!categories.contains(w['category'])) {
      errors.add('[$id] category "${w['category']}" không có trong categories');
    }

    if (w.containsKey('hunt') && w['hunt'] is! bool) {
      errors.add('[$id] "hunt" phải là true/false');
    }

    // Hình minh hoạ: ảnh asset (phải tồn tại nếu khai báo) hoặc emoji.
    // Không khai báo `image` thì app tự dùng assets/images/words/<id>.webp nếu có (xem lib/data/bundled_images.dart).
    final conventional = File('assets/images/words/$id.webp').existsSync();
    final image =
        (w['image'] as String?) ?? (conventional ? 'có ảnh theo mã' : null);
    final emoji = w['emoji'] as String?;
    if (w['image'] != null && !File(w['image'] as String).existsSync()) {
      errors.add('[$id] thiếu file ảnh ${w['image']}');
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

  // Ảnh đóng gói theo mã: mỗi file phải ứng với một từ / chủ đề thật (bắt lỗi chính tả tên file).
  final wordIds = {for (final w in words) w['id'] as String};
  final categoryIds = categories;
  for (final entry in {
    'assets/images/words': wordIds,
    'assets/images/categories': categoryIds,
  }.entries) {
    final dir = Directory(entry.key);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.webp')) {
        errors.add('[${entry.key}] $name: ảnh phải là .webp');
        continue;
      }
      final id = name.substring(0, name.length - '.webp'.length);
      if (!entry.value.contains(id)) {
        errors.add(
          '[${entry.key}] $name không khớp mã từ/chủ đề nào trong vocab.json',
        );
      }
    }
  }

  // Game: đủ từ cho "Tìm vật" và "Nghe & chọn hình", huy hiệu hợp lệ.
  final huntCount = words
      .where((w) => w['label'] != null && w['hunt'] != false)
      .length;
  if (huntCount < 5) {
    errors.add(
      'Game "Tìm vật" cần ít nhất 5 từ có hunt=true (đang có $huntCount)',
    );
  }
  final pictureCount = words
      .where(
        (w) =>
            w['image'] != null ||
            w['emoji'] != null ||
            File('assets/images/words/${w['id']}.webp').existsSync(),
      )
      .length;
  if (pictureCount < 4) {
    errors.add(
      'Game "Nghe & chọn hình" cần ít nhất 4 từ có hình (đang có $pictureCount)',
    );
  }
  final badgesFile = File('assets/game/badges.json');
  if (!badgesFile.existsSync()) {
    errors.add('Thiếu assets/game/badges.json');
  } else {
    const metrics = {'stars', 'rounds', 'perfect', 'found', 'learned'};
    final badgeIds = <String>{};
    final badges =
        (jsonDecode(badgesFile.readAsStringSync())
                as Map<String, dynamic>)['badges']
            as List<dynamic>;
    for (final b in badges.cast<Map<String, dynamic>>()) {
      final id = b['id'] as String? ?? '?';
      if (!badgeIds.add(id)) errors.add('[huy hiệu $id] id bị trùng');
      if (!metrics.contains(b['metric'])) {
        errors.add('[huy hiệu $id] metric "${b['metric']}" không hợp lệ');
      }
      if (b['threshold'] is! int || (b['threshold'] as int) < 1) {
        errors.add('[huy hiệu $id] threshold phải là số nguyên >= 1');
      }
    }
  }

  // Lời nhắn của Cam: đủ context cho các màn hình, điều kiện hợp lệ.
  final messagesFile = File('assets/mascot/messages.json');
  if (!messagesFile.existsSync()) {
    errors.add('Thiếu assets/mascot/messages.json');
  } else {
    const screens = [
      'home',
      'camera',
      'result',
      'vocab',
      'vocab_detail',
      'hub',
      'match',
      'hunt',
    ];
    const conditions = {'any', 'no_learned', 'has_learned', 'has_stars'};
    final messages =
        jsonDecode(messagesFile.readAsStringSync()) as Map<String, dynamic>;
    for (final screen in screens) {
      final lines = (messages[screen] as List<dynamic>?) ?? const [];
      if (lines.length < 3) {
        errors.add(
          '[lời nhắn $screen] cần ít nhất 3 câu (đang có ${lines.length})',
        );
      }
      for (final l in lines.cast<Map<String, dynamic>>()) {
        final when = l['when'] as String? ?? 'any';
        if (!conditions.contains(when)) {
          errors.add('[lời nhắn $screen] điều kiện "$when" không hợp lệ');
        }
        final text = l['text'] as String? ?? '';
        if (text.isEmpty || text.length > 60) {
          errors.add(
            '[lời nhắn $screen] câu rỗng hoặc dài quá 60 ký tự: "$text"',
          );
        }
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

  // Mọi nhãn của model phải có từ vựng; từ có label thì label phải nằm trong model.
  // (Từ vựng được nhiều hơn model: từ không có label chỉ để học.)
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

  final learnOnly = words.where((w) => w['label'] == null).length;
  stdout.writeln(
    '${labels.length} nhãn · ${words.length} từ ($learnOnly chỉ để học) · '
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

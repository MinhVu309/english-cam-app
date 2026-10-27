// Chạy trên máy/emulator thật. Cần đẩy ảnh mẫu (tên `<nhãn>__<n>.jpg`) vào
// /data/user/0/com.englishcam.english_cam/files/samples bằng `adb run-as`.
// Test thứ hai vẽ khung tìm được ra PNG trong files/out để xem bằng mắt.
import 'dart:io';
import 'dart:ui' as ui;

import 'dart:typed_data';

import 'package:english_cam/ml/classifier_service.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:english_cam/ml/image_preprocess.dart';
import 'package:english_cam/ml/object_localizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _base = '/data/user/0/com.englishcam.english_cam/files';

Future<List<File>> _samples() async {
  final dir = Directory('$_base/samples');
  // `flutter test` cài lại app (xoá dữ liệu), nên chờ ảnh được đẩy vào sau đó.
  for (
    var i = 0;
    i < 120 && !(dir.existsSync() && dir.listSync().length >= 48);
    i++
  ) {
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phân loại ảnh mẫu từ dataset/processed/test', (tester) async {
    final files = await _samples();
    expect(files, isNotEmpty);

    final svc = ClassifierService.instance;
    await svc.init();
    await svc.classifyFile(files.first.path); // khởi động nóng

    var correct = 0, confident = 0, confidentCorrect = 0;
    final times = <int>[];
    for (final f in files) {
      final truth = f.uri.pathSegments.last.split('__').first;
      final r = await svc.classifyFile(f.path);
      times.add(r.inferenceMs);
      final hit = r.best.label == truth;
      if (hit) correct++;
      if (r.isConfident) {
        confident++;
        if (hit) confidentCorrect++;
      }
    }
    times.sort();
    // ignore: avoid_print
    print(
      'SUMMARY n=${files.length} top1=$correct '
      '(${(100 * correct / files.length).toStringAsFixed(1)}%) '
      'confident=$confident confidentCorrect=$confidentCorrect '
      'ms median=${times[times.length ~/ 2]} max=${times.last}',
    );
  });

  testWidgets('tìm khung quanh vật và vẽ ra PNG', (tester) async {
    final files = await _samples();
    final out = Directory('$_base/out')..createSync(recursive: true);
    final loc = ObjectLocalizer.instance;
    final times = <int>[];
    var found = 0;

    for (final f in files) {
      final name = f.uri.pathSegments.last.replaceAll('.jpg', '');
      final truth = name.split('__').first;
      final sw = Stopwatch()..start();
      final box = await loc.localize(f.path, truth);
      times.add(sw.elapsedMilliseconds);
      if (box != null) found++;

      final img = await decodeImageFile(f.path);
      const maxW = 360.0;
      final scale = maxW / img.width;
      final w = maxW, h = img.height * scale;
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      c.drawImageRect(
        img,
        ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, w, h),
        ui.Paint(),
      );
      if (box != null) {
        final r = ui.Rect.fromLTRB(
          box.rect.left * w,
          box.rect.top * h,
          box.rect.right * w,
          box.rect.bottom * h,
        );
        c.drawRect(
          r,
          ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = const ui.Color(0xFFFFFFFF),
        );
        c.drawRect(
          r,
          ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const ui.Color(0xFFFF5500),
        );
      }
      final pic = rec.endRecording();
      final png = await (await pic.toImage(
        w.round(),
        h.round(),
      )).toByteData(format: ui.ImageByteFormat.png);
      File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      img.dispose();
      // ignore: avoid_print
      print(
        'BOX $name ${box == null ? 'none' : '${box.rect.width.toStringAsFixed(2)} p=${box.probability.toStringAsFixed(2)}'} ms=${sw.elapsedMilliseconds}',
      );
    }
    times.sort();
    // ignore: avoid_print
    print(
      'LOCALIZE n=${files.length} found=$found '
      'ms median=${times[times.length ~/ 2]} max=${times.last}',
    );
    // Chờ để kéo ảnh ra bằng adb trước khi flutter gỡ app.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 90)),
    );
  });

  testWidgets('xuất điểm từng ô để thử thuật toán chọn khung', (tester) async {
    final files = await _samples();
    final svc = ClassifierService.instance;
    await svc.init();
    final dump = StringBuffer();
    for (final f in files) {
      final name = f.uri.pathSegments.last.replaceAll('.jpg', '');
      final truth = name.split('__').first;
      final idx = svc.labels.indexOf(truth);
      final img = await decodeImageFile(f.path);
      final wins = ObjectLocalizer.generateWindows(
        img.width,
        img.height,
        scales: const [1.0, 0.7, 0.5, 0.35],
        stride: 0.5,
      );
      final rows = <String>[];
      for (final w in wins) {
        final all = await svc.probabilities(
          await imageRegionToFloat32(img, src: w),
        );
        rows.add(
          '${w.left.round()},${w.top.round()},${w.width.round()},'
          '${all[idx].toStringAsFixed(3)}',
        );
      }
      dump.writeln('$name ${img.width} ${img.height} ${rows.join(';')}');
      img.dispose();
    }
    File('$_base/out/windows.txt').writeAsStringSync(dump.toString());
    // ignore: avoid_print
    print('DUMPED ${files.length}');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 60)),
    );
  });

  testWidgets('đo từng bước của một ô', (tester) async {
    final files = await _samples();
    final svc = ClassifierService.instance;
    await svc.init();
    final img = await decodeImageFile(files.first.path);
    final wins = ObjectLocalizer.generateWindows(img.width, img.height);
    // khởi động nóng
    await svc.probabilities(await imageRegionToFloat32(img, src: wins.first));

    final pre = Stopwatch(), inf = Stopwatch();
    for (final w in wins) {
      pre.start();
      final input = await imageRegionToFloat32(img, src: w);
      pre.stop();
      inf.start();
      await svc.probabilities(input);
      inf.stop();
    }
    final n = wins.length;
    // ignore: avoid_print
    print(
      'STEP windows=$n image=${img.width}x${img.height} '
      'preprocess/window=${(pre.elapsedMicroseconds / n / 1000).toStringAsFixed(1)}ms '
      'inference/window=${(inf.elapsedMicroseconds / n / 1000).toStringAsFixed(1)}ms',
    );
  });

  testWidgets('đo suy luận thuần theo số luồng', (tester) async {
    final files = await _samples();
    final img = await decodeImageFile(files.first.path);
    final input = await imageRegionToFloat32(img);
    final lines = <String>[];
    for (final threads in [1, 2, 4]) {
      final it = await Interpreter.fromAsset(
        'assets/ml/model.tflite',
        options: InterpreterOptions()..threads = threads,
      );
      final out = Float32List(24);
      for (var i = 0; i < 3; i++) {
        it.run(input.buffer, out.buffer);
      }
      final sw = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        it.run(input.buffer, out.buffer);
      }
      lines.add(
        'threads=$threads ${(sw.elapsedMicroseconds / 20 / 1000).toStringAsFixed(1)}ms',
      );
      it.close();
    }
    // ignore: avoid_print
    print('RAW ${lines.join(' | ')}');
  });
}

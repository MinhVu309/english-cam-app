// Chạy trên máy/emulator thật. Cần đẩy ảnh mẫu (tên `<nhãn>__<n>.jpg`) vào
// /data/user/0/com.englishcam.english_cam/files/samples bằng `adb run-as`.
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:english_cam/ml/classifier_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phân loại ảnh mẫu từ dataset/processed/test', (tester) async {
    final dir = Directory(
      '/data/user/0/com.englishcam.english_cam/files/samples',
    );
    // `flutter test` cài lại app (xoá dữ liệu), nên chờ ảnh được đẩy vào sau đó.
    for (
      var i = 0;
      i < 120 && !(dir.existsSync() && dir.listSync().length >= 48);
      i++
    ) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);

    final svc = ClassifierService.instance;
    await svc.init();
    // khởi động nóng (lần chạy đầu thường chậm hơn)
    await svc.classifyFile(files.first.path);

    // So sánh: cả ảnh vs cắt theo khung ngắm (cạnh 72%, ở giữa).
    final modes = <String, Rect?>{
      'full': null,
      'crop72': const Rect.fromLTWH(0.14, 0.14, 0.72, 0.72),
    };
    for (final mode in modes.entries) {
      var correct = 0, confident = 0, confidentCorrect = 0;
      final times = <int>[];
      for (final f in files) {
        final truth = f.uri.pathSegments.last.split('__').first;
        final r = await svc.classifyFile(f.path, crop: mode.value);
        times.add(r.inferenceMs);
        final hit = r.best.label == truth;
        if (hit) correct++;
        if (r.isConfident) {
          confident++;
          if (hit) confidentCorrect++;
        }
        if (!hit) {
          // ignore: avoid_print
          print(
            'MISS[${mode.key}] truth=$truth pred=${r.best.label} '
            'p=${r.best.probability.toStringAsFixed(2)} '
            'top3=${r.top.map((p) => p.label).join('/')}',
          );
        }
      }
      times.sort();
      // ignore: avoid_print
      print(
        'SUMMARY[${mode.key}] n=${files.length} top1=$correct '
        '(${(100 * correct / files.length).toStringAsFixed(1)}%) '
        'confident=$confident confidentCorrect=$confidentCorrect '
        'ms median=${times[times.length ~/ 2]} max=${times.last}',
      );
    }
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'image_preprocess.dart';

const String kModelAsset = 'assets/ml/model.tflite';
const String kLabelsAsset = 'assets/ml/labels.txt';

/// Chỉ hiện kết quả khi xác suất cao nhất >= ngưỡng này (model không có lớp `none`).
const double kConfidenceThreshold = 0.7;

class Prediction {
  const Prediction(this.label, this.probability);

  /// Nhãn đúng như trong labels.txt (vd. `teddy_bear`).
  final String label;
  final double probability;
}

class ClassificationResult {
  const ClassificationResult({
    required this.top,
    required this.inferenceMs,
    this.threshold = kConfidenceThreshold,
  });

  /// Top-k, xác suất giảm dần.
  final List<Prediction> top;

  /// Thời gian tiền xử lý + suy luận.
  final int inferenceMs;
  final double threshold;

  Prediction get best => top.first;
  bool get isConfident => best.probability >= threshold;
}

/// Lấy top-[k] từ vector xác suất; chỉ số i ↔ labels[i].
List<Prediction> topK(List<double> probs, List<String> labels, {int k = 3}) {
  assert(probs.length == labels.length);
  final idx = List<int>.generate(probs.length, (i) => i)
    ..sort((a, b) => probs[b].compareTo(probs[a]));
  return [for (final i in idx.take(k)) Prediction(labels[i], probs[i])];
}

/// Singleton: nạp model một lần, suy luận chạy trong isolate riêng.
class ClassifierService {
  ClassifierService._();
  static final ClassifierService instance = ClassifierService._();

  Interpreter? _interpreter;
  IsolateInterpreter? _isolate;
  List<String> _labels = const [];
  Future<void>? _initFuture;

  // IsolateInterpreter bỏ qua lệnh gọi chồng nhau, nên xếp hàng tuần tự.
  Future<void> _queue = Future.value();

  List<String> get labels => _labels;

  Future<void> init() => _initFuture ??= _load().catchError((Object e) {
    _initFuture = null; // cho phép thử lại
    throw e;
  });

  Future<void> _load() async {
    final raw = await rootBundle.loadString(kLabelsAsset);
    final labels = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final interpreter = await Interpreter.fromAsset(kModelAsset);
    final inShape = interpreter.getInputTensor(0).shape;
    final outShape = interpreter.getOutputTensor(0).shape;
    final ok =
        inShape.length == 4 &&
        inShape[1] == kModelInputSize &&
        inShape[2] == kModelInputSize &&
        inShape[3] == 3 &&
        outShape.length == 2 &&
        outShape[1] == labels.length;
    if (!ok) {
      interpreter.close();
      throw StateError(
        'Model không khớp hợp đồng: input $inShape, output $outShape, '
        '${labels.length} nhãn',
      );
    }
    _labels = labels;
    _interpreter = interpreter;
    _isolate = await IsolateInterpreter.create(address: interpreter.address);
  }

  Future<ClassificationResult> classifyFile(String path) async {
    final sw = Stopwatch()..start();
    final input = await preprocessImageFile(path);
    return classifyPixels(input, stopwatch: sw);
  }

  /// [input]: float32 RGB 224×224×3, giá trị 0–255.
  Future<ClassificationResult> classifyPixels(
    Float32List input, {
    Stopwatch? stopwatch,
  }) async {
    await init();
    final sw = stopwatch ?? (Stopwatch()..start());
    final output = Float32List(_labels.length);

    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    await previous;
    try {
      await _isolate!.run(input.buffer, output.buffer);
    } finally {
      done.complete();
    }

    sw.stop();
    return ClassificationResult(
      top: topK(output, _labels),
      inferenceMs: sw.elapsedMilliseconds,
    );
  }

  Future<void> dispose() async {
    await _isolate?.close();
    _interpreter?.close();
    _isolate = null;
    _interpreter = null;
    _initFuture = null;
  }
}

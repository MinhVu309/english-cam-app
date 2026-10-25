import 'package:english_cam/data/game_badge.dart';
import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/main.dart';
import 'package:english_cam/services/audio_service.dart';
import 'package:english_cam/services/game_progress.dart';
import 'package:english_cam/services/progress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AudioService.instance.disabled = true;
    await VocabRepository.load();
    await BadgeRepository.load();
    GameProgress.instance.resetForTest();
    await ProgressService.instance.init();
  });

  testWidgets('Home hiện 3 nút lớn', (tester) async {
    await tester.pumpWidget(const EnglishCamApp());

    expect(find.text('Chụp & Học'), findsOneWidget);
    expect(find.text('Từ vựng'), findsOneWidget);
    expect(find.text('Chơi'), findsOneWidget);
  });

  testWidgets('Nút Chơi mở màn chọn game', (tester) async {
    await tester.pumpWidget(const EnglishCamApp());

    await tester.tap(find.text('Chơi'));
    await tester.pumpAndSettle();

    expect(find.text('Nghe & chọn hình'), findsOneWidget);
    expect(find.text('Tìm vật'), findsOneWidget);
  });

  testWidgets('Nút Từ vựng mở danh sách', (tester) async {
    await tester.pumpWidget(const EnglishCamApp());

    await tester.tap(find.text('Từ vựng'));
    await tester.pumpAndSettle();

    expect(find.text('Tìm từ…'), findsOneWidget);
  });
}

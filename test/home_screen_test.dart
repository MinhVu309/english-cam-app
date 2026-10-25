import 'package:english_cam/data/vocab_repository.dart';
import 'package:english_cam/main.dart';
import 'package:english_cam/services/audio_service.dart';
import 'package:english_cam/services/progress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AudioService.instance.disabled = true;
    await VocabRepository.load();
    await ProgressService.instance.init();
  });

  testWidgets('Home hiện 3 nút lớn', (tester) async {
    await tester.pumpWidget(const EnglishCamApp());

    expect(find.text('Chụp & Học'), findsOneWidget);
    expect(find.text('Từ vựng'), findsOneWidget);
    expect(find.text('Chơi'), findsOneWidget);
  });

  testWidgets('Nút chưa làm hiện thông báo "Sắp có"', (tester) async {
    await tester.pumpWidget(const EnglishCamApp());

    await tester.tap(find.text('Chơi'));
    await tester.pump();

    expect(find.text('Sắp có nhé!'), findsOneWidget);
  });

  testWidgets('Nút Từ vựng mở danh sách', (tester) async {
    await tester.pumpWidget(const EnglishCamApp());

    await tester.tap(find.text('Từ vựng'));
    await tester.pumpAndSettle();

    expect(find.text('Tìm từ…'), findsOneWidget);
  });
}

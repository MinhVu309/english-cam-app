import 'package:english_cam/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home hiện 3 nút lớn', (tester) async {
    await tester.pumpWidget(const EnglishCamApp());

    expect(find.text('Chụp & Học'), findsOneWidget);
    expect(find.text('Từ vựng'), findsOneWidget);
    expect(find.text('Chơi'), findsOneWidget);
  });

  testWidgets('Nút chưa làm hiện thông báo "Sắp có"', (tester) async {
    await tester.pumpWidget(const EnglishCamApp());

    await tester.tap(find.text('Từ vựng'));
    await tester.pump();

    expect(find.text('Sắp có nhé!'), findsOneWidget);
  });
}

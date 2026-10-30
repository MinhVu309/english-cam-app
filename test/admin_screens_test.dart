import 'dart:convert';

import 'package:english_cam/core/api_client.dart';
import 'package:english_cam/core/router.dart';
import 'package:english_cam/features/account/admin_home_screen.dart';
import 'package:english_cam/features/admin/admin_categories_screen.dart';
import 'package:english_cam/features/admin/admin_feedback_screen.dart';
import 'package:english_cam/features/admin/admin_publish_screen.dart';
import 'package:english_cam/features/admin/admin_users_screen.dart';
import 'package:english_cam/features/admin/admin_words_screen.dart';
import 'package:english_cam/services/auth_service.dart';
import 'package:english_cam/services/key_value_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

void testUi(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await body(tester);
  });
}

Map<String, dynamic> userJson(
  String id,
  String name, {
  String role = 'Parent',
  bool active = true,
  int kids = 1,
}) => {
  'id': id,
  'fullName': name,
  'email': '$id@test.com',
  'role': role,
  'isActive': active,
  'emailConfirmed': true,
  'createdAt': '2026-10-01T00:00:00Z',
  'childCount': kids,
};

Map<String, dynamic> wordJson(
  String id,
  String en,
  String vi, {
  String? label,
  bool deleted = false,
  String category = 'school',
}) => {
  'id': id,
  'label': label,
  'en': en,
  'vi': vi,
  'phonetic': '/x/',
  'exampleEn': 'This is a $en.',
  'exampleVi': 'Đây là $vi.',
  'category': category,
  'audio': 'assets/audio/words/$id.mp3',
  'exampleAudio': null,
  'image': null,
  'emoji': '📘',
  'hunt': label != null,
  'sortOrder': 1,
  'isDeleted': deleted,
  'updatedAt': '2026-10-01T00:00:00Z',
};

Map<String, dynamic> categoryJson(
  String id,
  String vi, {
  bool deleted = false,
  int words = 2,
}) => {
  'id': id,
  'vi': vi,
  'en': id,
  'emoji': '📁',
  'color': '#FF9800',
  'sortOrder': 1,
  'isDeleted': deleted,
  'wordCount': words,
};

Map<String, dynamic> paged(
  List<Object> items, {
  int total = -1,
  int page = 1,
  int size = 20,
}) => {
  'total': total < 0 ? items.length : total,
  'page': page,
  'pageSize': size,
  'items': items,
};

Map<String, dynamic> statsJson({List<Map<String, dynamic>>? hardest}) => {
  'users': {
    'admins': 1,
    'parents': 7,
    'children': 9,
    'locked': 2,
    'newParentsLast7Days': 3,
  },
  'children': {
    'total': 9,
    'active': 8,
    'activeToday': 4,
    'activeLast7Days': 6,
    'linkedDevices': 11,
  },
  'vocab': {'publishedVersion': 3, 'words': 61, 'categories': 11},
  'activity': {
    'sessionsTotal': 120,
    'sessionsLast7Days': 35,
    'minutesLast7Days': 240,
    'starsTotal': 999,
  },
  'hardestWords':
      hardest ??
      [
        {
          'wordId': 'cup',
          'en': 'cup',
          'vi': 'cái cốc',
          'answers': 10,
          'wrong': 6,
          'wrongRate': 0.6,
          'children': 3,
        },
      ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  late AuthService auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = FakeServer()
      ..on(
        'POST /api/auth/google-login',
        200,
        authJson(
          role: 'Admin',
          userId: 'admin-1',
          name: 'Quản trị',
          email: 'admin@test.com',
        ),
      );
    auth = AuthService(
      api: ApiClient(baseUrl: 'https://api.test', transport: server.call),
      store: MemoryKeyValueStore(),
      google: FakeGoogle(),
      device: FakeDevice(),
    );
    await auth.signInWithGoogle();
    AuthService.instance = auth;
  });

  tearDown(() => AuthService.instance = AuthService());

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MaterialApp(home: home, onGenerateRoute: onGenerateRoute),
    );
    await tester.pumpAndSettle();
  }

  Map<String, String> query(HttpRequestData r) => r.url.queryParameters;

  group('Trang quản trị', () {
    testUi(
      'hiện số liệu hệ thống, từ bé hay nhầm và lối vào các màn quản trị',
      (tester) async {
        server
          ..on('GET /api/admin/vocab/status', 200, {
            'publishedVersion': 3,
            'hasUnpublishedChanges': true,
            'activeWords': 61,
            'activeCategories': 11,
          })
          ..on('GET /api/admin/stats', 200, statsJson());
        await pump(tester, const AdminHomeScreen());
        expect(find.text('Phiên bản 3 · 61 từ · 11 chủ đề'), findsOneWidget);
        expect(find.textContaining('chưa xuất bản'), findsOneWidget);
        expect(find.text('Tài khoản bị khoá'), findsOneWidget);
        expect(find.text('35 / 120'), findsOneWidget);
        expect(find.text('999'), findsOneWidget);
        expect(find.text('cup · cái cốc'), findsOneWidget);
        expect(find.text('60% sai (6/10)'), findsOneWidget);
        for (final label in [
          'Người dùng',
          'Từ vựng',
          'Chủ đề',
          'Xuất bản cho app',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
      },
    );

    testUi(
      'số liệu lỗi thì khối từ vựng vẫn hiện; chưa có dữ liệu bé nhầm thì nói rõ',
      (tester) async {
        server
          ..on('GET /api/admin/vocab/status', 200, {
            'publishedVersion': 1,
            'hasUnpublishedChanges': false,
            'activeWords': 60,
            'activeCategories': 11,
          })
          ..on('GET /api/admin/stats', 500, null);
        await pump(tester, const AdminHomeScreen());
        expect(find.text('Phiên bản 1 · 60 từ · 11 chủ đề'), findsOneWidget);
        expect(find.textContaining('Máy chủ đang gặp sự cố'), findsOneWidget);

        server.on('GET /api/admin/stats', 200, statsJson(hardest: const []));
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh(); // kéo xuống để tải lại
        await tester.pumpAndSettle();
        expect(find.textContaining('Chưa đủ dữ liệu'), findsOneWidget);
      },
    );
  });

  group('Người dùng', () {
    void listing() => server.handle('GET /api/admin/users', (r) {
      final q = query(r);
      var all = [
        userJson('admin-1', 'Quản trị', role: 'Admin', kids: 0),
        userJson('p1', 'Mẹ Lan'),
        userJson('p2', 'Bố Nam', active: false, kids: 3),
      ];
      if (q['role'] != null) {
        all = all.where((u) => u['role'] == q['role']).toList();
      }
      if ((q['search'] ?? '').isNotEmpty) {
        all = all.where((u) => '${u['fullName']}'.contains(q['search']!)).toList();
      }
      return FakeServer.json(200, paged(all));
    });

    testUi('liệt kê, tìm theo tên, lọc theo vai trò (gửi đúng tham số)', (
      tester,
    ) async {
      listing();
      await pump(tester, const AdminUsersScreen());
      expect(find.text('Mẹ Lan'), findsOneWidget);
      expect(find.text('Bố Nam'), findsOneWidget);
      expect(find.textContaining('ĐÃ KHOÁ'), findsOneWidget);
      expect(find.text('Đang hiện 3 / 3'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Lan');
      await tester.tap(find.byTooltip('Tìm'));
      await tester.pumpAndSettle();
      expect(query(server.to('GET /api/admin/users').last)['search'], 'Lan');
      expect(find.text('Bố Nam'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Admin'));
      await tester.pumpAndSettle();
      expect(query(server.to('GET /api/admin/users').last)['role'], 'Admin');
      expect(find.text('Quản trị'), findsOneWidget);
      expect(find.text('Mẹ Lan'), findsNothing);
    });

    testUi('khoá một phụ huynh: gửi đúng thân PUT rồi tải lại danh sách', (
      tester,
    ) async {
      listing();
      server.handle(
        'PUT /api/admin/users/p1',
        (r) => FakeServer.json(200, userJson('p1', 'Mẹ Lan', active: false)),
      );
      await pump(tester, const AdminUsersScreen());
      await tester.tap(find.text('Mẹ Lan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await tester.pumpAndSettle();
      final put = server.to('PUT /api/admin/users/p1').single;
      expect(server.bodyOf(put), {
        'fullName': 'Mẹ Lan',
        'role': 'Parent',
        'isActive': false,
      });
      expect(
        server.to('GET /api/admin/users').length,
        2,
        reason: 'tải lại sau khi lưu',
      );
    });

    testUi(
      'tài khoản của chính mình: không đổi vai trò, không khoá, không xoá',
      (tester) async {
        listing();
        await pump(tester, const AdminUsersScreen());
        await tester.tap(find.text('Quản trị'));
        await tester.pumpAndSettle();
        expect(find.textContaining('không tự đổi vai trò'), findsOneWidget);
        expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
        expect(find.widgetWithText(TextButton, 'Xoá'), findsNothing);
      },
    );

    testUi(
      'xoá phụ huynh có bé: cảnh báo sẽ xoá cả bé, xác nhận mới gọi DELETE',
      (tester) async {
        listing();
        server.on('DELETE /api/admin/users/p2', 204);
        await pump(tester, const AdminUsersScreen());
        await tester.tap(find.text('Bố Nam'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Xoá'));
        await tester.pumpAndSettle();
        expect(find.textContaining('xoá luôn 3 hồ sơ bé'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Huỷ').last);
        await tester.pumpAndSettle();
        expect(
          server.to('DELETE /api/admin/users/p2'),
          isEmpty,
          reason: 'huỷ thì không xoá',
        );

        await tester.tap(find.widgetWithText(TextButton, 'Xoá'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
        await tester.pumpAndSettle();
        expect(server.to('DELETE /api/admin/users/p2'), hasLength(1));
      },
    );

    testUi(
      'thêm tài khoản; lỗi từ máy chủ hiện ngay trong hộp thoại và không đóng nó',
      (tester) async {
        listing();
        var fail = true;
        server.handle(
          'POST /api/admin/users',
          (r) => fail
              ? FakeServer.json(400, {
                  'errors': [
                    'Passwords must have at least one digit (\'0\'-\'9\').',
                  ],
                })
              : FakeServer.json(201, userJson('new', 'Cô Hoa')),
        );
        await pump(tester, const AdminUsersScreen());
        await tester.tap(find.text('Thêm'));
        await tester.pumpAndSettle();
        final fields = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(fields.at(0), 'hoa@test.com');
        await tester.enterText(fields.at(1), 'Cô Hoa');
        await tester.enterText(fields.at(2), 'matkhauyeu');
        await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
        await tester.pumpAndSettle();
        expect(find.text('Mật khẩu cần ít nhất một chữ số.'), findsOneWidget);
        expect(
          find.text('Thêm tài khoản'),
          findsOneWidget,
          reason: 'hộp thoại vẫn mở',
        );

        fail = false;
        await tester.enterText(fields.at(2), 'Matkhau123');
        await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
        await tester.pumpAndSettle();
        expect(find.text('Thêm tài khoản'), findsNothing);
        expect(server.bodyOf(server.to('POST /api/admin/users').last), {
          'email': 'hoa@test.com',
          'password': 'Matkhau123',
          'fullName': 'Cô Hoa',
          'role': 'Parent',
        });
      },
    );
  });

  group('Từ vựng', () {
    void catalog() {
      server
        ..on('GET /api/admin/categories', 200, [
          categoryJson('school', 'Trường học'),
          categoryJson('food', 'Đồ ăn'),
        ])
        ..on('GET /api/admin/vocab/model-labels', 200, [
          {'label': 'book', 'usedBy': 'book'},
          {'label': 'cup', 'usedBy': null},
        ])
        ..handle('GET /api/admin/words', (r) {
          final q = query(r);
          var all = [
            wordJson('book', 'book', 'quyển sách', label: 'book'),
            wordJson('apple_pie', 'apple pie', 'bánh táo', category: 'food'),
            wordJson('old', 'old', 'cũ', deleted: true),
          ];
          if (q['includeDeleted'] != 'true') {
            all = all.where((w) => w['isDeleted'] == false).toList();
          }
          if (q['category'] != null) {
            all = all.where((w) => w['category'] == q['category']).toList();
          }
          return FakeServer.json(200, paged(all));
        });
    }

    testUi('liệt kê kèm chủ đề và nhãn; lọc theo chủ đề; hiện cả từ đã xoá', (
      tester,
    ) async {
      catalog();
      await pump(tester, const AdminWordsScreen());
      expect(find.text('book · quyển sách'), findsOneWidget);
      expect(
        find.textContaining('Trường học · nhận diện: book'),
        findsOneWidget,
      );
      expect(find.text('old · cũ'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        query(server.to('GET /api/admin/words').last)['includeDeleted'],
        'true',
      );
      expect(find.text('old · cũ'), findsOneWidget);
      expect(find.textContaining('ĐÃ XOÁ'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Đồ ăn').last);
      await tester.pumpAndSettle();
      expect(query(server.to('GET /api/admin/words').last)['category'], 'food');
      expect(find.text('book · quyển sách'), findsNothing);
      expect(find.text('apple pie · bánh táo'), findsOneWidget);
    });

    testUi(
      'sửa một từ: nạp sẵn dữ liệu, sửa nghĩa, gửi PUT không kèm mã, quay lại danh sách và tải lại',
      (tester) async {
        catalog();
        server.handle(
          'PUT /api/admin/words/book',
          (r) => FakeServer.json(
            200,
            wordJson('book', 'book', 'sách vở', label: 'book'),
          ),
        );
        await pump(tester, const AdminWordsScreen());
        await tester.tap(find.text('book · quyển sách'));
        await tester.pumpAndSettle();
        expect(find.text('Sửa từ'), findsOneWidget);
        expect(find.text('Mã: book'), findsOneWidget);
        expect(find.text('quyển sách'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'quyển sách'),
          'sách vở',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Lưu thay đổi'));
        await tester.pumpAndSettle();

        final body = server.bodyOf(
          server.to('PUT /api/admin/words/book').single,
        );
        expect(body['vi'], 'sách vở');
        expect(body['label'], 'book');
        expect(body['category'], 'school');
        expect(body['audio'], 'assets/audio/words/book.mp3');
        expect(body.containsKey('id'), isFalse);
        expect(body['hunt'], isTrue);
        expect(find.text('Từ vựng'), findsOneWidget, reason: 'đã về danh sách');
        expect(server.to('GET /api/admin/words').length, 2);
      },
    );

    testUi(
      'thêm từ mới: gửi mã + chủ đề; thiếu tệp âm thanh thì lỗi của máy chủ hiện ra, form vẫn giữ nội dung',
      (tester) async {
        catalog();
        var fail = true;
        server.handle(
          'POST /api/admin/words',
          (r) => fail
              ? FakeServer.json(400, {
                  'errors': [
                    'audio "audio/words/giraffe.mp3" chưa được tải lên (POST /api/admin/media)',
                  ],
                })
              : FakeServer.json(
                  201,
                  wordJson('giraffe', 'giraffe', 'hươu cao cổ'),
                ),
        );
        await pump(tester, const AdminWordsScreen());
        await tester.tap(find.text('Thêm từ'));
        await tester.pumpAndSettle();
        expect(find.text('Thêm từ'), findsWidgets);

        Future<void> type(String label, String text) =>
            tester.enterText(find.widgetWithText(TextField, label), text);
        await type(
          'Mã (chữ thường, số, _; vd. giraffe) — không đổi được sau này',
          'giraffe',
        );
        await type('Tiếng Anh', 'giraffe');
        await type('Tiếng Việt', 'hươu cao cổ');
        await type('Phiên âm (vd. /kʌp/)', '/dʒɪˈrɑːf/');
        await type('Câu ví dụ (Anh)', 'The giraffe is tall.');
        await type('Câu ví dụ (Việt)', 'Hươu cao cổ rất cao.');
        await type(
          'Âm thanh từ (vd. audio/words/giraffe.mp3)',
          'audio/words/giraffe.mp3',
        );
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Thêm từ'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Thêm từ'));
        await tester.pumpAndSettle();
        expect(find.textContaining('chưa được tải lên'), findsOneWidget);
        expect(
          find.text('hươu cao cổ'),
          findsOneWidget,
          reason: 'không mất nội dung đã gõ',
        );

        fail = false;
        await tester.tap(find.widgetWithText(FilledButton, 'Thêm từ'));
        await tester.pumpAndSettle();
        final body = server.bodyOf(server.to('POST /api/admin/words').last);
        expect(body['id'], 'giraffe');
        expect(body['category'], 'school', reason: 'mặc định chủ đề đầu tiên');
        expect(body['label'], isNull);
        expect(
          body['hunt'],
          isFalse,
          reason: 'không có nhãn thì không dùng cho Tìm vật',
        );
        expect(find.text('Từ vựng'), findsOneWidget);
      },
    );

    testUi('nhãn model đã có từ khác dùng thì không chọn được', (tester) async {
      catalog();
      await pump(tester, const AdminWordsScreen());
      await tester.tap(find.text('apple pie · bánh táo'));
      await tester.pumpAndSettle();
      final labelBox = find.byType(DropdownButtonFormField<String?>);
      await tester.ensureVisible(labelBox);
      await tester.tap(labelBox);
      await tester.pumpAndSettle();
      final book = tester.widget<DropdownMenuItem<String?>>(
        find
            .widgetWithText(DropdownMenuItem<String?>, 'book (đã dùng: book)')
            .last,
      );
      expect(book.enabled, isFalse);
      final cup = tester.widget<DropdownMenuItem<String?>>(
        find.widgetWithText(DropdownMenuItem<String?>, 'cup').last,
      );
      expect(cup.enabled, isTrue);
    });

    testUi(
      'chọn tệp âm thanh đã tải lên: hỏi đúng tiền tố, bỏ asset đóng gói, điền vào ô; chưa có tệp thì chỉ cách tải',
      (tester) async {
        catalog();
        var uploaded = true;
        server.handle(
          'GET /api/admin/media',
          (r) => FakeServer.json(
            200,
            paged(
              uploaded
                  ? [
                      {
                        'path': 'audio/words/giraffe.mp3',
                        'size': 20480,
                        'bundled': false,
                      },
                    ]
                  : [],
            ),
          ),
        );
        await pump(tester, const AdminWordsScreen());
        await tester.tap(find.text('Thêm từ'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Chọn tệp đã tải lên').first);
        await tester.pumpAndSettle();
        final q = query(server.to('GET /api/admin/media').single);
        expect(q['prefix'], 'audio/words/');
        expect(
          q.containsKey('includeBundled'),
          isFalse,
          reason: 'asset đóng gói sẵn không phải lựa chọn cho từ mới',
        );
        expect(find.text('20 KB'), findsOneWidget);
        await tester.tap(find.text('audio/words/giraffe.mp3'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextField, 'audio/words/giraffe.mp3'),
          findsOneWidget,
        );

        uploaded = false;
        await tester.tap(find.byTooltip('Chọn tệp đã tải lên').at(1));
        await tester.pumpAndSettle();
        expect(
          query(server.to('GET /api/admin/media').last)['prefix'],
          'audio/examples/',
        );
        expect(find.textContaining('POST /api/admin/media'), findsOneWidget);
      },
    );

    testUi('xoá từ cần xác nhận; từ đã xoá có nút khôi phục', (tester) async {
      catalog();
      server
        ..on('DELETE /api/admin/words/book', 204)
        ..handle(
          'POST /api/admin/words/old/restore',
          (r) => FakeServer.json(200, wordJson('old', 'old', 'cũ')),
        );
      await pump(tester, const AdminWordsScreen());
      await tester.tap(find.text('book · quyển sách'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Xoá từ'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Xoá từ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('khôi phục được'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
      await tester.pumpAndSettle();
      expect(server.to('DELETE /api/admin/words/book'), hasLength(1));

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('old · cũ'));
      await tester.pumpAndSettle();
      expect(find.text('Từ này đã bị xoá'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Khôi phục'));
      await tester.pumpAndSettle();
      expect(server.to('POST /api/admin/words/old/restore'), hasLength(1));
    });
  });

  group('Chủ đề', () {
    testUi(
      'liệt kê, thêm (gửi đúng thân), xoá bị từ chối vì còn từ thì hiện lý do',
      (tester) async {
        server
          ..on('GET /api/admin/categories', 200, [
            categoryJson('school', 'Trường học'),
            categoryJson('toys', 'Đồ chơi', deleted: true, words: 0),
          ])
          ..on(
            'POST /api/admin/categories',
            201,
            categoryJson('animals', 'Con vật'),
          )
          ..on('DELETE /api/admin/categories/school', 409, {
            'message': 'Chủ đề còn 2 từ, hãy chuyển hoặc xoá các từ đó trước',
          })
          ..on(
            'POST /api/admin/categories/toys/restore',
            200,
            categoryJson('toys', 'Đồ chơi'),
          );
        await pump(tester, const AdminCategoriesScreen());
        expect(find.text('Trường học · school'), findsOneWidget);
        expect(find.textContaining('ĐÃ XOÁ'), findsOneWidget);

        await tester.tap(find.text('Thêm chủ đề'));
        await tester.pumpAndSettle();
        final f = find.byType(TextField);
        await tester.enterText(f.at(0), 'animals');
        await tester.enterText(f.at(1), 'Con vật');
        await tester.enterText(f.at(2), 'Animals');
        await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
        await tester.pumpAndSettle();
        expect(server.bodyOf(server.to('POST /api/admin/categories').single), {
          'id': 'animals',
          'vi': 'Con vật',
          'en': 'Animals',
          'emoji': null,
          'color': null,
        });

        await tester.tap(find.text('Trường học · school'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Xoá'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Chủ đề còn 2 từ'), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'Huỷ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Đồ chơi · toys'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Khôi phục'));
        await tester.pumpAndSettle();
        expect(
          server.to('POST /api/admin/categories/toys/restore'),
          hasLength(1),
        );
      },
    );
  });

  group('Xuất bản', () {
    void status({bool dirty = true}) => server
      ..on('GET /api/admin/vocab/status', 200, {
        'publishedVersion': 3,
        'hasUnpublishedChanges': dirty,
        'activeWords': 62,
        'activeCategories': 11,
      })
      ..on('GET /api/admin/vocab/releases', 200, [
        {
          'version': 3,
          'notes': 'Thêm 2 từ',
          'wordCount': 61,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ]);

    testUi('nháp sai: liệt kê lỗi và không có nút xuất bản', (tester) async {
      status();
      server.on('GET /api/admin/vocab/validate', 200, {
        'valid': false,
        'errors': [
          'Từ "giraffe": audio "audio/words/giraffe.mp3" chưa được tải lên',
          'Nhãn "xyz" không thuộc model',
        ],
      });
      await pump(tester, const AdminPublishScreen());
      expect(find.text('Bản nháp chưa hợp lệ (2 lỗi)'), findsOneWidget);
      expect(find.textContaining('giraffe.mp3'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Xuất bản'), findsNothing);
      expect(find.textContaining('v3 · 61 từ'), findsOneWidget);
    });

    testUi('nháp đúng: xác nhận rồi xuất bản kèm ghi chú, báo phiên bản mới', (
      tester,
    ) async {
      status();
      server
        ..on('GET /api/admin/vocab/validate', 200, {
          'valid': true,
          'errors': <String>[],
        })
        ..on('POST /api/admin/vocab/publish', 201, {
          'version': 4,
          'notes': 'Thêm hươu',
          'wordCount': 62,
          'createdAt': '2026-10-30T00:00:00Z',
        });
      await pump(tester, const AdminPublishScreen());
      await tester.enterText(find.byType(TextField), 'Thêm hươu');
      await tester.tap(find.widgetWithText(FilledButton, 'Xuất bản'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'App của mọi bé sẽ nhận bản từ vựng này khi bấm "Cập nhật từ vựng".',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Xuất bản').last);
      await tester.pumpAndSettle();
      expect(server.bodyOf(server.to('POST /api/admin/vocab/publish').single), {
        'notes': 'Thêm hươu',
      });
      expect(find.text('Đã xuất bản phiên bản 4 (62 từ).'), findsOneWidget);
    });

    testUi('bấm Huỷ ở hộp xác nhận thì không xuất bản', (tester) async {
      status();
      server
        ..on('GET /api/admin/vocab/validate', 200, {
          'valid': true,
          'errors': <String>[],
        })
        ..on('POST /api/admin/vocab/publish', 201, {
          'version': 4,
          'notes': null,
          'wordCount': 62,
          'createdAt': '2026-10-30T00:00:00Z',
        });
      await pump(tester, const AdminPublishScreen());
      await tester.tap(find.widgetWithText(FilledButton, 'Xuất bản'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Huỷ'));
      await tester.pumpAndSettle();
      expect(server.to('POST /api/admin/vocab/publish'), isEmpty);
      expect(find.textContaining('Đã xuất bản'), findsNothing);
    });

    testUi('không có thay đổi (409) thì hiện lý do của máy chủ', (
      tester,
    ) async {
      status(dirty: false);
      server
        ..on('GET /api/admin/vocab/validate', 200, {
          'valid': true,
          'errors': <String>[],
        })
        ..on('POST /api/admin/vocab/publish', 409, {
          'message': 'Không có thay đổi nào so với bản đang phát',
        });
      await pump(tester, const AdminPublishScreen());
      expect(find.text('Bản nháp trùng với bản đang phát.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Xuất bản'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Xuất bản').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Không có thay đổi nào so với bản đang phát'),
        findsOneWidget,
      );
      expect(
        jsonDecode(
          server.to('POST /api/admin/vocab/publish').single.body!,
        )['notes'],
        isNull,
      );
    });
  });

  group('Góp ý nhận diện', () {
    Map<String, dynamic> fbJson(
      String id,
      String predicted,
      String? wordId,
      String text, {
      String source = 'top3',
      double p = 0.8,
    }) => {
      'id': id,
      'createdAt': '2026-10-30T10:00:00Z',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'predictedLabel': predicted,
      'predictedProbability': p,
      'top3': <Object>[],
      'correctWordId': wordId,
      'correctText': text,
      'source': source,
      'modelSource': 'bundled',
      'vocabVersion': 1,
    };

    void data() {
      server
        ..on('GET /api/admin/feedback/summary', 200, {
          'total': 7,
          'last7Days': 5,
          'sameAsPrediction': 1,
          'topConfusions': [
            {'predictedLabel': 'hat', 'correct': 'cup', 'count': 3},
            {'predictedLabel': 'apple', 'correct': 'quả táo', 'count': 2},
          ],
          'unknownWords': [
            {'text': 'quả táo', 'count': 2},
          ],
        })
        ..handle('GET /api/admin/feedback', (r) {
          final unknown = r.url.queryParameters['unknownOnly'] == 'true';
          final all = [
            fbJson('f1', 'hat', 'cup', 'cup'),
            fbJson('f2', 'apple', null, 'quả táo', source: 'typed', p: 0.55),
            fbJson('f3', 'cup', 'cup', 'cup', p: 0.9),
          ];
          return FakeServer.json(
            200,
            paged(
              unknown
                  ? all.where((f) => f['correctWordId'] == null).toList()
                  : all,
            ),
          );
        });
    }

    testUi('Admin home có lối vào "Góp ý nhận diện"', (tester) async {
      server
        ..on('GET /api/admin/vocab/status', 200, {
          'publishedVersion': 1,
          'hasUnpublishedChanges': false,
          'activeWords': 60,
          'activeCategories': 11,
        })
        ..on('GET /api/admin/stats', 200, statsJson());
      await pump(tester, const AdminHomeScreen());
      expect(find.text('Góp ý nhận diện'), findsOneWidget);
    });

    testUi(
      'hiện tổng quan, cặp hay nhầm, từ người dùng muốn thêm và danh sách',
      (tester) async {
        data();
        await pump(tester, const AdminFeedbackScreen());
        expect(find.text('Tổng số góp ý'), findsOneWidget);
        expect(find.text('7'), findsOneWidget);
        expect(find.text('hat → cup'), findsOneWidget);
        expect(find.text('3 lần'), findsOneWidget);
        expect(find.text('quả táo'), findsWidgets);
        expect(find.text('hat (80%) → cup'), findsOneWidget);
        expect(find.textContaining('gõ tay · từ chưa có'), findsOneWidget);
        expect(find.textContaining('model đoán đúng'), findsWidgets);
      },
    );

    testUi('lọc "Từ chưa có" gửi unknownOnly=true và chỉ còn các từ lạ', (
      tester,
    ) async {
      data();
      await pump(tester, const AdminFeedbackScreen());
      await tester.tap(find.widgetWithText(ChoiceChip, 'Từ chưa có'));
      await tester.pumpAndSettle();
      expect(
        query(server.to('GET /api/admin/feedback').last)['unknownOnly'],
        'true',
      );
      expect(find.text('hat (80%) → cup'), findsNothing);
      expect(find.text('apple (55%) → quả táo'), findsOneWidget);
    });

    testUi('xoá một góp ý phải xác nhận; huỷ thì không gọi máy chủ', (
      tester,
    ) async {
      data();
      server.on('DELETE /api/admin/feedback/f1', 204);
      await pump(tester, const AdminFeedbackScreen());
      await tester.tap(find.byTooltip('Xoá góp ý').first);
      await tester.pumpAndSettle();
      expect(find.text('Xoá góp ý này?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Huỷ'));
      await tester.pumpAndSettle();
      expect(server.to('DELETE /api/admin/feedback/f1'), isEmpty);

      await tester.tap(find.byTooltip('Xoá góp ý').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
      await tester.pumpAndSettle();
      expect(server.to('DELETE /api/admin/feedback/f1'), hasLength(1));
      expect(
        server.to('GET /api/admin/feedback/summary').length,
        2,
        reason: 'tải lại sau khi xoá',
      );
    });

    testUi('chưa có góp ý nào: nói rõ; lỗi máy chủ: hiện thông báo', (
      tester,
    ) async {
      server
        ..on('GET /api/admin/feedback/summary', 200, {
          'total': 0,
          'last7Days': 0,
          'sameAsPrediction': 0,
          'topConfusions': <Object>[],
          'unknownWords': <Object>[],
        })
        ..on('GET /api/admin/feedback', 200, paged([]));
      await pump(tester, const AdminFeedbackScreen());
      expect(find.text('Chưa có góp ý nào.'), findsOneWidget);
      expect(find.text('Chưa có từ nào.'), findsOneWidget);

      server.on('GET /api/admin/feedback/summary', 500, null);
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.textContaining('Máy chủ đang gặp sự cố'), findsOneWidget);
    });
  });
}

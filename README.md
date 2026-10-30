# English Cam

Ứng dụng Android giúp trẻ em học từ vựng tiếng Anh bằng camera: bé chụp một đồ vật, app nhận ra đó là gì, đọc tên bằng tiếng Anh, rồi bé học tiếp qua thẻ từ và game. Bắt buộc đăng nhập một lần (bố mẹ bằng email + OTP hoặc Google; hoặc máy của bé nhập mã liên kết do bố mẹ tạo); sau đó học, chơi và nhận diện vẫn dùng được khi mất mạng. Không quảng cáo. Hồ sơ bé và tiến độ do backend [english-cam-api](../english-cam-api) quản lý; ảnh bé chụp không bao giờ rời máy. Có ảnh chụp và kịch bản chạy thử trên Pixel 7 ở [docs/demo.md](docs/demo.md). Từ vựng (và mô hình) có thể cập nhật từ hosting mà không cần build lại app (xem [docs/VOCAB_PACK.md](docs/VOCAB_PACK.md)).

| Chào bé | Màn hình chính | Từ vựng | Chi tiết từ |
|---|---|---|---|
| ![](docs/screenshots/01-onboarding.png) | ![](docs/screenshots/02-home.png) | ![](docs/screenshots/04-vocab-list.png) | ![](docs/screenshots/05-vocab-detail.png) |

| Chơi | Nghe & chọn hình | Tìm vật |
|---|---|---|
| ![](docs/screenshots/06-games.png) | ![](docs/screenshots/07-match-game.png) | ![](docs/screenshots/08-hunt-game.png) |

*(Ảnh chụp trên Xiaomi 23021RAAEG, bản release.)*

## Tính năng

- **Chụp & Học:** chụp đồ vật → nhận diện trong ~0,2 giây → tự đọc từ tiếng Anh → vẽ khung vuông quanh vật. Nếu app nhận sai, bé hoặc bố mẹ bấm "Không đúng?" để chọn lại trong top-3.
- **Góp ý khi nhận diện sai:** ở "Không đúng?" bé/bố mẹ chọn một trong 3 gợi ý hoặc **"Khác…" để gõ tên đúng** (có gợi ý từ trong từ vựng, gõ không dấu cũng được). Lựa chọn được lưu trên máy (không mất khi mất mạng) và gửi lên backend, app cảm ơn: "Sự góp ý của bạn là đóng góp lớn cho ứng dụng sau này". **Chỉ gửi chữ, không gửi ảnh.** Admin xem tổng hợp trong khu quản trị (cặp model hay nhầm, từ người dùng muốn thêm).
- **Từ vựng:** 60 từ đóng gói sẵn có **ảnh minh hoạ thật**, 11 chủ đề (phiên âm, nghĩa tiếng Việt, câu ví dụ có đọc), tìm kiếm, lọc theo chủ đề, đánh dấu đã học.
- **Game:** *Nghe & chọn hình* (8 câu/ván) và *Tìm vật* (đi tìm vật thật rồi chụp). Có sao và 8 huy hiệu. Trả lời sai chỉ được khuyến khích, không bị trừ sao.
- **Cam:** linh vật 3D tự dựng, lâu lâu hiện ra nhắn bé ở mọi màn hình (xem [docs/MASCOT.md](docs/MASCOT.md)).
- **Từ vựng mới tự báo:** khi Admin xuất bản bản từ vựng mới, app tự thông báo (lúc mở, vừa đăng nhập, quay lại app, hoặc định kỳ khi đang mở); bố mẹ chỉ bấm **Cập nhật ngay** ở Cài đặt → Cập nhật từ vựng, không phải nhập địa chỉ nào ([chi tiết](docs/VOCAB_PACK.md)).
- **Dành cho bố mẹ:** Cài đặt nằm sau cổng phụ huynh (phép nhân), có tắt nhạc, tắt lời nhắn của Cam, xoá tiến độ, xem lại hướng dẫn.

## 24 từ chụp nhận diện được (trong 60 từ có sẵn)

`book, pen, bag, ruler, scissors, clock, cup, bottle, chair, table, bowl, spoon, shoe, hat, glasses, umbrella, toothbrush, towel, apple, banana, orange, ball, teddy_bear, toy_car`

## Cách chạy

Yêu cầu: Flutter 3.41+ (Dart 3.11+), Android SDK, thiết bị Android 7.0+ (API 24) hoặc emulator. Có thêm nền tảng **iOS** (iOS 13+, cần Xcode và CocoaPods; xem mục iOS trong tài liệu hướng dẫn gốc của dự án về việc ghim TFLite 2.17.0); iOS mới build/cài được, chưa kiểm tra bằng tay.

```bash
flutter pub get
flutter run                       # chạy bản debug trên thiết bị đang cắm
flutter build apk --release       # APK release: build/app/outputs/flutter-apk/app-release.apk
```

> APK release hiện ký bằng khoá debug mặc định của Flutter, chỉ để cài thử, **chưa** dùng để phát hành lên cửa hàng.

## Kiểm thử

```bash
flutter analyze                          # phân tích tĩnh
flutter test                             # 299 test đơn vị + widget
dart run tool/check_assets.dart          # nhãn model ↔ vocab ↔ ảnh ↔ âm thanh ↔ lời nhắn
dart run tool/build_pack.dart build <thư-mục> --version N   # tạo manifest cho gói từ vựng (docs/VOCAB_PACK.md)
flutter test integration_test -d <máy>   # đo độ chính xác và thời gian trên thiết bị thật
```

Kết quả đo trên thiết bị thật và hạn chế đã biết: xem [docs/TEST_REPORT.md](docs/TEST_REPORT.md).

## Mô hình nhận diện

- MobileNetV2 (fine-tune từ ImageNet), phân loại ảnh 24 lớp, file `assets/ml/model.tflite` (2,5 MB) và `labels.txt`.
- Input `[1,224,224,3]` float32, pixel giữ nguyên 0–255 (model tự `Rescaling` bên trong); output `[1,24]` softmax.
- Từ vựng và mô hình tách rời: từ có `label` mới nhận diện được, từ không có `label` chỉ để học. Nâng cấp mô hình chỉ cần thay file trong gói từ vựng.
- Ngưỡng hiển thị kết quả: xác suất ≥ 0,7; thấp hơn thì Cam nói "Mình chưa chắc, thử chụp lại nhé!".
- Chạy bằng `tflite_flutter` trong isolate riêng, 2 luồng CPU.
- **Khung quanh vật:** model chỉ phân loại cả ảnh, không có bounding box. App ước lượng vị trí bằng cách cho model xem khoảng 24 ô vuông ở 3 cỡ, gộp xác suất thành bản đồ nhiệt rồi vẽ khung vuông quanh vùng nóng ([object_localizer.dart](lib/ml/object_localizer.dart)). Đây là ước lượng, khung có thể lệch hoặc rộng hơn vật.

## Cấu trúc

```
lib/
  main.dart                  # khởi động, nạp dữ liệu, màn hình lỗi khởi động
  core/                      # theme, bảng màu, router, widget dùng chung
  data/                      # VocabRepository, huy hiệu; pack/: tải & lưu gói từ vựng (manifest, sha256, PackUpdater)
  ml/                        # ClassifierService, tiền xử lý ảnh, ObjectLocalizer
  services/                  # âm thanh, tiến độ học, sao & huy hiệu, cài đặt
  features/                  # home, camera, result, vocab, game, mascot, onboarding, settings
assets/
  ml/  vocab/  audio/  game/  mascot/  fonts/
tool/                        # check_assets.dart, generate_audio.py
integration_test/            # đo độ chính xác và thời gian trên thiết bị thật
docs/                        # MASCOT.md, TEST_REPORT.md, ảnh màn hình
```

Toàn bộ từ vựng nằm trong `assets/vocab/vocab.json`, huy hiệu trong `assets/game/badges.json`, lời nhắn của Cam trong `assets/mascot/messages.json`: sửa nội dung không cần đụng code.

## Quyền riêng tư

Sau khi đăng nhập, dùng bình thường không cần mạng. Ảnh bé chụp chỉ được xử lý trên máy và không lưu lại hay gửi đi. Khi sửa kết quả nhận diện sai, app gửi tên từ đúng (chữ) kèm nhãn model đoán và xác suất; không có ảnh, tên thật hay vị trí. Tiến độ học (từ đã học, sao, huy hiệu) lưu cục bộ bằng `shared_preferences`. Quyền: **Camera**, và **Internet** (khi bố mẹ đăng nhập, liên kết máy của bé hoặc bấm *Cập nhật từ vựng*). Chưa đăng nhập thì app chỉ hiện màn chào và không gửi gì đi.

### Tài khoản và hồ sơ bé
Cài đặt (sau cổng phụ huynh) → **Đăng nhập / Đăng ký** (email + mã OTP, quên mật khẩu, hoặc Google). Phụ huynh vào *Hồ sơ của bé*: thêm bé, **Cho bé chơi** trên máy này, hoặc **Thêm máy cho bé** để lấy mã 8 số; trên máy của bé: Cài đặt → *Máy của bé? Nhập mã liên kết*. Một bé dùng được nhiều máy; bố mẹ thấy và gỡ từng máy, đặt mục tiêu từ/ngày và giới hạn phút/ngày.

Bấm **Tiến độ** ở thẻ bé để xem dashboard: số từ đã học, sao, chuỗi ngày học liên tiếp, thời gian dùng hôm nay (so với giới hạn), biểu đồ 7/30 ngày, tiến độ theo chủ đề, các từ bé hay nhầm (có nút nghe lại), huy hiệu và hoạt động gần đây. **Chép dữ liệu** đưa bảng CSV vào clipboard để dán vào Google Sheets/Excel. **Giới hạn thời gian được thực thi:** khi bé dùng hết số phút bố mẹ đặt cho hôm nay, app phủ màn *Hết giờ chơi hôm nay rồi!* (Cam nhắc trước khi còn 5 phút). Bố mẹ bấm *Dành cho bố mẹ*, trả lời phép nhân rồi chọn cho chơi thêm 10/20/30 phút; sang ngày mới tự mở. Giờ đã dùng và giới hạn được nhớ trên máy theo từng bé nên tắt mạng hay mở lại app không né được; đứng ở màn khoá không bị tính giờ. Chế độ khách không có giới hạn.

### Quản trị (tài khoản Admin)
Đăng nhập bằng tài khoản Admin thì Cài đặt dẫn tới trang **Quản trị**: số liệu hệ thống (kể cả các từ bé hay nhầm nhất), **Người dùng** (tìm, lọc, thêm, đổi tên/vai trò, khoá, xoá), **Từ vựng** (tìm, lọc theo chủ đề, thêm/sửa/xoá/khôi phục), **Chủ đề**, và **Xuất bản cho app** (kiểm tra bản nháp rồi phát hành; app của bé chỉ thấy sau khi xuất bản). Tệp âm thanh/hình của từ mới vẫn phải tải lên bằng Swagger (`POST /api/admin/media`) rồi chọn trong form; chọn tệp từ máy cần thêm một thư viện nên chưa làm.

Địa chỉ backend mặc định là bản đã deploy. Thử với backend chạy local:
```bash
flutter run --dart-define=API_URL=http://10.0.2.2:5080          # emulator; máy thật dùng IP của Mac, ví dụ http://10.15.94.20:5080
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<Web client ID>  # khi đổi project Google
```
Đăng nhập Google cần một **Android OAuth client** trong cùng project Google Cloud với Web client ID, khai báo package `com.englishcam.english_cam` và SHA-1 của khoá ký (debug: `./gradlew signingReport` trong `android/`).

## Nguồn và giấy phép

| Thành phần | Nguồn |
|---|---|
| Giọng đọc từ và câu ví dụ | TTS của macOS (`say`, giọng Samantha), tạo bằng `tool/generate_audio.py`. **Nên thay bằng giọng thu thật nếu phát hành thương mại.** |
| Nhạc nền và hiệu ứng | Tự tổng hợp bằng sóng sin (`tool/generate_audio.py`) |
| Phông chữ | Nunito, SIL Open Font License 1.1 (`assets/fonts/OFL.txt`) |
| Hình minh hoạ từ vựng | Ảnh thật do nhóm cung cấp: 56 từ + 11 chủ đề (`assets/images/words/` và `categories/`, WebP vuông 512/256 px, khoảng 1,1 MB) và 4 từ màu dùng ảnh viên bi vẽ sẵn, tức là **cả 60 từ đều có ảnh**; emoji chỉ còn là phương án dự phòng cho từ mới của gói cập nhật chưa có ảnh. **Chưa rõ giấy phép của ảnh** (nguồn web/kho ảnh); trước khi phát hành cần thay bằng ảnh có bản quyền rõ ràng |
| Nhân vật Cam | Nhóm tự vẽ bằng code |
| Mô hình | MobileNetV2 fine-tune trên bộ ảnh của nhóm (project ML riêng, không nằm trong repo này) |

## Giai đoạn phát triển

Mỗi giai đoạn nằm trên một nhánh git: `phase-a-camera` → `phase-b-model` → `phase-c-vocab` → `phase-d-audio` → `phase-e-game` → `phase-f-ux` → `phase-f2-polish`; `main` luôn là bản mới nhất. Kế hoạch gốc: [PLAN.md](PLAN.md).

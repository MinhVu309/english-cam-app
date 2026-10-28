# Báo cáo: mở rộng từ vựng và cập nhật từ xa không cần sửa mã

Ngày thực hiện: 2026-10-28. Phạm vi: app Flutter `english-cam-app` (phần ML không đổi, không train lại).

## 1. Yêu cầu

1. Từ vựng phải đầy đủ hơn 24 từ mà model nhận diện, và mở rộng được sau này.
2. Cập nhật từ vựng (và nâng cấp model sau này) mà không phải sửa mã nguồn hay build lại APK.
3. Chọn nơi đặt dữ liệu: **GitHub Pages** (file tĩnh, không cần viết server).

## 2. Thiết kế

Trước đây từ vựng gắn 1-1 với model: `vocab.json` bắt buộc có đúng 24 `label` như `labels.txt`, và `tool/check_assets.dart` kiểm tra hai chiều. Việc này chặn mọi từ mới.

Thay đổi chính: **tách từ vựng khỏi model**.

| Trước | Sau |
|---|---|
| Mọi từ đều có `label` khớp model | `label` là tuỳ chọn. Từ có `label` thì chụp nhận diện được; từ không có `label` chỉ để học |
| Vocab = đúng 24 nhãn của model | Vocab ⊇ nhãn của model |
| Từ vựng và model nằm cố định trong APK | APK vẫn có bản đóng gói sẵn, thêm *gói từ vựng* tải từ mạng có thể thay thế cả từ vựng lẫn model |

Nguyên tắc: **offline-first**. Dữ liệu đóng gói sẵn luôn dùng được; gói tải về chỉ ghi đè khi hợp lệ, hỏng thì tự quay về bản gốc.

### Luồng cập nhật

```
Phụ huynh bấm "Cập nhật từ vựng"
  → GET manifest.json (số phiên bản + danh sách file kèm SHA-256 và kích thước)
  → nếu phiên bản <= bản đang cài: báo "đã mới nhất"
  → tải từng file vào thư mục staging/ (file không đổi thì chép từ bản cũ, không tải lại)
  → kiểm tra SHA-256 và kích thước từng file, kiểm tra vocab.json, kiểm tra model (nếu có)
  → đổi tên staging/ → current/ (lỗi giữa chừng thì giữ nguyên bản cũ)
  → nạp lại VocabRepository và ClassifierService
```

## 3. Các việc đã làm

### 3.1. Nội dung
- Thêm **36 từ** (24 → 60 từ) vào `assets/vocab/vocab.json`, kèm 6 chủ đề mới: động vật (8), đồ ăn & uống (8), phương tiện (5), cơ thể (6), thiên nhiên (5), màu sắc (4). Mỗi từ có phiên âm, nghĩa tiếng Việt, câu ví dụ và âm thanh.
- Sinh 72 file mp3 mới (36 từ × từ và câu ví dụ) bằng `tool/generate_audio.py` (giọng TTS Samantha của macOS). Thư mục `assets/audio` hiện còn 60 file mỗi loại, tổng 1,9 MB.
- 4 từ màu dùng ảnh PNG tự vẽ (`assets/images/colors/`) thay vì emoji, vì emoji 🟡🟢 chỉ có từ Android 11 trong khi app hỗ trợ từ Android 7.
- Emoji của từ mới ưu tiên ký tự đơn (không có dấu chọn dạng hiển thị) để hiển thị ổn định.

### 3.2. Mã nguồn (`lib/`)
- `data/pack/` (mới): `pack_manifest.dart` (đọc và kiểm tra manifest), `pack_store.dart` (lưu `current/`, `staging/`, khôi phục khi bị ngắt), `pack_updater.dart` (tải, kiểm tra, thay bản), `sha256.dart` (SHA-256 chạy từng đoạn, tự viết).
- `data/vocab_word.dart`, `vocab_repository.dart`: `label` tuỳ chọn; kiểm tra khi nạp (trùng id/label, chủ đề không tồn tại, đường dẫn không an toàn, tối thiểu 4 từ có hình); ưu tiên `vocab.json` của gói, hỏng thì dùng bản đóng gói.
- `ml/classifier_service.dart`: ưu tiên model trong gói; kiểm tra hợp đồng (input 1×224×224×3 float32, output 1×N float32, N bằng số nhãn); sai thì dùng lại model đóng gói. Thêm `reload()`.
- `services/audio_service.dart`, `features/vocab/word_visual.dart`: đường dẫn `assets/...` là asset đóng gói, đường dẫn tương đối là file trong gói đã tải.
- `features/settings/pack_update_screen.dart` (mới) và mục "Cập nhật từ vựng" trong Cài đặt: nhập địa chỉ, tiến độ tải, thông báo kết quả, "Quay về bản gốc".
- `features/game/hunt/hunt_game_screen.dart`: chỉ chọn đích là từ mà model hiện tại còn nhận ra.
- `features/home/home_screen.dart`: số từ trên thẻ "Từ vựng" lấy từ dữ liệu thay vì ghi cứng "24".
- `features/game/match/matching_game_screen.dart`: chữ trên thẻ đáp án tự co lại khi từ dài (từ tải về có thể dài).
- Android: thêm quyền `INTERNET`; `pubspec.yaml` thêm `path_provider` và thư mục `assets/images/colors/`.

### 3.3. Công cụ và tài liệu
- `tool/build_pack.dart` (mới): `init` tạo thư mục gói từ vocab hiện tại; `build` kiểm tra (thiếu trường, trùng id/label, file tham chiếu không tồn tại, model thiếu labels...) rồi ghi `manifest.json`.
- `tool/generate_audio.py`: thêm `--pack` (chỉ đọc các từ mà vocab của gói trỏ tới file chưa có) và `--only-missing`.
- `tool/check_assets.dart`: cho phép từ không có `label`; vẫn bắt buộc mọi nhãn model có từ vựng.
- Tài liệu: `docs/VOCAB_PACK.md` (định dạng gói, quy trình, nâng cấp model, an toàn), cập nhật `README.md` và `CLAUDE.md`.
- Thư mục gói bản 1 ở `english-cam-ml/english-cam-pack/` (1 file `vocab.json` 25 KB + `manifest.json`, chuẩn bị đưa lên GitHub Pages).

## 4. An toàn

- **Toàn vẹn:** mỗi file kiểm tra SHA-256 và kích thước; sai một file là huỷ cả lần cập nhật.
- **Đường dẫn:** manifest và vocab chỉ chấp nhận đường dẫn tương đối an toàn (không `..`, không `/` đầu, ký tự giới hạn); `PackStore.fileFor` chặn đường dẫn thoát khỏi thư mục gói. Giới hạn 2000 file, mỗi file ≤ 30 MB, manifest ≤ 1 MB.
- **Mạng:** chỉ gửi GET, không gửi dữ liệu nào đi; bản release chỉ nhận `https://`. Chỉ phụ huynh (sau cổng phép nhân) mới bấm được cập nhật; app không tự kết nối ngầm.
- **Quay lui:** thay bản bằng đổi tên thư mục nên không để lại trạng thái nửa vời; có nút xoá gói về bản gốc; model sai hợp đồng tự bị bỏ qua.
- **Giới hạn đã biết:** SHA-256 chỉ chống file hỏng/thiếu. Việc dữ liệu có đúng nguồn dựa vào https và quyền ghi vào hosting, nên ai điều khiển được repo GitHub Pages thì thay được từ vựng và model.

## 5. Kiểm thử (số liệu từ lần chạy cuối)

| Hạng mục | Kết quả |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 70 test qua (trước thay đổi: 46) |
| `dart run tool/check_assets.dart` | 24 nhãn · 60 từ (36 chỉ để học) · 0 lỗi · 2 cảnh báo (table, towel chưa có emoji, đã có từ trước) |
| `flutter build apk --debug` | Thành công |
| SHA-256 tự viết | Đúng với vector NIST ("", "abc", 56 ký tự, 1 triệu chữ a), độ dài sát ranh giới khối 55/56/64 byte, và đối chiếu với `shasum -a 256` trên `vocab.json` 25 KB |

Test mới: `sha256_test.dart`, `pack_test.dart` (manifest, vocab, kho lưu, bộ tải chạy với máy chủ HTTP cục bộ: tải mới, chỉ tải file đổi, lỗi 500/sai hash/mất file giữ bản cũ, vocab hoặc model không hợp lệ bị từ chối, địa chỉ http bị chặn khi release), `pack_update_screen_test.dart` (màn cập nhật: lỗi, đã mới nhất, thành công).

### Lỗi phát hiện và sửa khi làm
- Chuẩn hoá địa chỉ cho ra `https://x.io/p/?#` (thừa `?#`): test bắt được, đã dựng lại URI bằng các thành phần.
- Game "Nghe & chọn hình" tràn 3 px khi từ dài xuống hai dòng (test seed cố định lộ ra sau khi thêm từ mới): chữ nay co lại bằng `FittedBox`.
- Kiểm tra cỡ chữ ≥ 18sp của dự án bắt một dòng chữ 16sp mới thêm: đã sửa thành 18.

## 6. Chưa làm / hạn chế

- **Chưa chạy trên điện thoại thật.** Luồng tải đã test với máy chủ cục bộ; chưa thử với GitHub Pages thật, chưa thử nạp một model TFLite từ gói bằng TFLite thật (phần kiểm tra hợp đồng model chỉ chạy trên thiết bị, không có test tự động).
- Gói bản 1 chưa được đưa lên GitHub Pages (cần tạo repo công khai `english-cam-pack`, xem `docs/VOCAB_PACK.md` và hướng dẫn trong cuộc trao đổi).
- Giọng đọc của 36 từ mới là TTS của macOS như 24 từ cũ; nếu phát hành thương mại nên thu giọng người thật hoặc dùng TTS có giấy phép rõ ràng.
- Nâng cấp model bằng gói chỉ thay file, không làm model tốt hơn; điểm yếu đã biết của model (apple, table) không đổi.
- PLAN.md ghi "offline hoàn toàn" và "chỉ thêm `tflite_flutter`": đã nới theo yêu cầu của chủ dự án (thêm quyền INTERNET, `path_provider`); app vẫn dùng được hoàn toàn khi không có mạng.
- Các thay đổi chưa được commit trong git.

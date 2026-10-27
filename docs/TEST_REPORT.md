# Báo cáo kiểm thử

Ngày đo: 2026-10-27. Kết quả là số đo thật; các mục chưa làm được ghi rõ ở phần 5.

## 1. Thiết bị

| Thiết bị | Cấu hình | Ghi chú |
|---|---|---|
| Xiaomi 23021RAAEG (Redmi Note 12 4G) | Snapdragon 685, Android 15 | **Máy thật duy nhất** đã thử |
| Emulator Pixel 7 | Android 17 (API 37), arm64 | Dùng để phát triển, số đo thời gian không đại diện cho máy thật |

PLAN yêu cầu ≥ 2 máy Android thật; hiện mới đo được **1 máy**.

## 2. Độ chính xác nhận diện

Bộ mẫu: 48 ảnh (2 ảnh mỗi lớp) lấy từ `dataset/processed/test`. Ảnh trong bộ này đã cắt sát vật, nên đây chỉ là kiểm tra mô hình hoạt động đúng trong app, **không** thay cho thử bằng ảnh chụp thật.

| Máy | Top-1 đúng | Chắc ≥ 0,7 | Trong số chắc, đúng |
|---|---|---|---|
| Xiaomi | 43/48 (89,6%) | 44 | 41 |
| Emulator | 43/48 (89,6%) | 44 | 41 |

Kết quả khớp giữa hai máy và khớp độ chính xác test 0,888 của project ML.

Các ảnh sai: 2 ảnh `apple` (đoán thành `table`), 1 ảnh `bag` (thành `shoe`), 1 ảnh `book` (thành `scissors`), 1 ảnh `table` (thành `ruler`). Cả 2 ảnh `apple` đều có `apple` trong top-3, nên nút "Không đúng?" vẫn cứu được.

**Điểm yếu đã biết của mô hình:** `apple` (recall chỉ 0,07) và `table` (precision 0,37). App xử lý bằng cách hiện top-3 để chọn lại, và loại hai từ này khỏi game *Tìm vật*. Mô hình cũng không có lớp "không phải vật nào" nên có thể tự tin nhận nhầm thứ ngoài 24 lớp (ví dụ khuôn mặt bị nhận là `hat`).

## 3. Thời gian

### 3.1. Nhận diện

| Phép đo | Xiaomi | Ghi chú |
|---|---|---|
| Đọc ảnh mẫu + resize + suy luận (debug) | trung vị 87 ms, tối đa 115 ms | 48 ảnh nhỏ từ dataset |
| Nhận diện ảnh chụp từ camera (**release**) | 333 ms (lần đầu), rồi 194–231 ms | 5 lần chụp thật, đã gồm đọc ảnh lớn |
| Suy luận thuần TFLite, 1 luồng | 65 ms | |
| Suy luận thuần TFLite, 2 luồng | **44 ms** | app dùng 2 luồng |
| Suy luận thuần TFLite, 4 luồng | 49 ms | không nhanh hơn 2 luồng |

Mục tiêu PLAN là < 300 ms mỗi ảnh: đạt ở trạng thái ổn định (~200 ms); lần chụp đầu tiên sau khi mở app chậm hơn (333 ms).

### 3.2. Tìm khung quanh vật

Khung được ước lượng bằng cách chạy model trên nhiều ô vuông, nên thời gian tỉ lệ với số ô (~24 ô/ảnh ở 4:3, tối đa 40).

| Phép đo | Thời gian |
|---|---|
| Trước tối ưu: 4 cỡ ô, ~58 ô, 4 luồng (debug, 48 ảnh mẫu) | trung vị 4,3 s, tối đa 6,0 s |
| Sau tối ưu: 3 cỡ ô, ~24 ô, 2 luồng (debug, 48 ảnh mẫu) | trung vị 1,4 s, 90% dưới 2,3 s |
| Sau tối ưu, ảnh chụp thật từ camera (**release**) | 1,95–2,30 s (5 lần chụp) |

Khung chỉ hiện sau khi kết quả nhận diện đã hiện (app hiện "Đang tìm vật…" trong lúc chờ), nên bé không phải đợi để nghe từ. Thời gian bị giới hạn bởi tốc độ suy luận của CPU (~45 ms/ô) chứ không phải bởi code Dart, nên bản release không nhanh hơn bản debug đáng kể.

### 3.3. Chất lượng khung

Không có khung chuẩn trong dataset nên chỉ đánh giá bằng mắt trên 48 ảnh mẫu: khoảng 3/4 ảnh có vật nằm trong khung (bóng, chai, kính, mũ, thìa, gấu bông, ô, xe đồ chơi…). Khung lệch hoặc không bao hết vật ở kéo, bút, cặp, sách, thước, bàn. Khung thường rộng hơn vật vì phải là hình vuông và nhỏ nhất ~50% cạnh ngắn của ảnh. Muốn khung chính xác cần một mô hình phát hiện vật thật (ngoài phạm vi ML đã đóng băng).

## 4. Kiểm thử chức năng

| Mục | Kết quả |
|---|---|
| `flutter analyze` | Sạch |
| `flutter test` | 46 test pass (dữ liệu từ vựng, nhận diện, khung, âm thanh, game, sao/huy hiệu, onboarding, cổng phụ huynh, Cam, quy chuẩn cỡ chữ/nút) |
| `check_assets` | 24 nhãn ↔ 24 từ, 0 lỗi; 2 cảnh báo (`table`, `towel` chưa có hình minh hoạ) |
| Xin quyền camera: cấp quyền | Hoạt động trên Xiaomi |
| Xin quyền camera: từ chối / bị chặn | Hiện hướng dẫn thân thiện, không crash (thử trên Xiaomi; phần "từ chối 2 lần thì hướng dẫn vào Cài đặt" mới thử trên test, chưa thử lại trên máy thật) |
| Xoay màn hình | App khoá dọc nên không xoay |
| Luồng chụp → kết quả → khung → "Không đúng?" → chọn lại | Chạy trên Xiaomi (release) |
| Game *Nghe & chọn hình*, *Tìm vật*, cổng phụ huynh, Cài đặt | Chạy trên emulator và Xiaomi |

Lỗi thật đã gặp và sửa trong lúc thử máy thật: hộp thoại xin quyền làm app `inactive`, khiến code giải phóng camera đang khởi tạo dở và camera báo lỗi chung (chỉ lộ ra trên Xiaomi).

## 5. Chưa làm được hoặc chưa chắc

- **Máy Android thật thứ hai:** chưa có.
- **Thử `apple` bằng quả táo thật:** chưa làm; mới có 2 ảnh `apple` từ dataset (cả hai bị đoán là `table`).
- **Độ chính xác với ảnh chụp thật ngoài đời:** chưa đo có hệ thống (ảnh mẫu đã cắt sát vật). Cần bộ ảnh chụp thật bằng chính camera máy.
- **Âm thanh:** trên Xiaomi âm lượng media ban đầu bằng 0 và bị tắt tiếng (đây là lý do từng không nghe thấy gì, không phải lỗi app). Sau khi tăng âm lượng, hệ thống ghi nhận app đang phát; chưa có người nghe xác nhận chất lượng giọng đọc và nhạc.
- **Bản release chưa ký chính thức:** đang dùng khoá debug.
- **Pháo giấy, hiệu ứng nảy, Cam nhún/chớp mắt:** chưa quay video kiểm tra chuyển động trên máy thật.

## 6. Cách chạy lại phép đo

1. `adb push` ảnh mẫu `<nhãn>__<n>.jpg` vào `/data/local/tmp/samples`.
2. `flutter test integration_test/classifier_samples_test.dart -d <máy> --plain-name "<tên test>"`; ngay sau khi app được cài, chép ảnh vào `files/samples` của app bằng `adb shell run-as com.englishcam.english_cam` (xem đầu file test).
3. Các test: `phân loại` (độ chính xác + thời gian), `tìm khung` (thời gian và ảnh khung), `đo từng bước` và `suy luận thuần` (phân tích thời gian).
4. Trên Xiaomi: bấm cho phép khi máy hỏi cài ứng dụng qua USB, và chỉnh âm lượng media nếu muốn nghe tiếng.

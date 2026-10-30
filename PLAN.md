# PLAN.md — App học từ vựng tiếng Anh cho trẻ em (camera + nhận diện vật thể)

> Cho Claude Code. **ML đã đóng băng, không train lại.** Chỉ làm app: Mobile (camera, tích hợp model, giao diện) + Nội dung & UX (từ vựng, âm thanh, thiết kế, game).

## 0. Hợp đồng model (đã kiểm tra từ project ML, KHÔNG đoán khác)
- File: `model.tflite` (2.56 MB) + `labels.txt` (**24 dòng**, không có lớp `none`). Copy vào `assets/ml/`.
- Kiến trúc: MobileNetV2 (ImageNet weights, fine-tune), phân loại ảnh, không có bounding box.
- **Input:** `[1,224,224,3]` float32, **pixel giữ nguyên 0–255**, KHÔNG chuẩn hoá thêm (model đã tự `Rescaling` bên trong). Ảnh RGB, resize thẳng 224×224 (không crop giữ tỉ lệ).
- **Output:** `[1,24]` softmax; chỉ số i ↔ dòng i của `labels.txt`.
- **Ngưỡng:** chỉ hiện kết quả khi max prob ≥ **0.7**. Không có lớp `none`, nên ngưỡng là cách duy nhất để nói "chưa nhận ra".
- 24 nhãn: book, pen, bag, ruler, scissors, clock, cup, bottle, chair, table, bowl, spoon, shoe, hat, glasses, umbrella, toothbrush, towel, apple, banana, orange, ball, teddy_bear, toy_car.
- Test accuracy 0.888 (số chưa chính thức). **Điểm yếu đã biết:** `apple` recall chỉ 0.07 (hay bị đoán thành `table`/`book`); `table` hay bị đoán nhầm (precision 0.37).

## 1. Ràng buộc
- Flutter (Dart), Android trước. Không ML Kit / API cloud cho nhận diện; chỉ `tflite_flutter`, ảnh camera không rời máy. App vẫn dùng được **hoàn toàn offline** (chế độ khách).
- Trẻ em: nút lớn, ít chữ, không quảng cáo. *Cập nhật 2026-10-30:* có backend ASP.NET (`../english-cam-api`, kế hoạch ở `docs/BACKEND_PLAN.md`) cho từ vựng, trò chơi, đăng nhập và dashboard phụ huynh. Khi phụ huynh đăng nhập, app chỉ gửi dữ liệu học tập tối thiểu (biệt danh, từ đã học, kết quả ván chơi, số phút); không gửi ảnh, tên thật, vị trí. Phụ huynh xoá được toàn bộ.

## 2. Cấu trúc
```
lib/ main.dart | core/(theme,router) | data/(vocab_repository, VocabWord)
     ml/(classifier_service, image_preprocess) | services/(audio, progress)
     features/ home | camera | vocab | game
assets/ ml/ | vocab/vocab.json | images/ | audio/
tool/check_assets.dart   # kiểm tra nhãn ↔ vocab ↔ audio ↔ ảnh
```

## 3. Giai đoạn
**A. Khung app & camera.** Home 3 nút lớn (Chụp & Học / Từ vựng / Chơi). Màn camera chụp 1 ảnh, xin quyền, xử lý từ chối. *Xong khi:* chụp được ảnh, không crash khi từ chối quyền/xoay màn hình.

**B. Tích hợp model.** `ClassifierService` singleton, chạy trong isolate, tiền xử lý đúng mục 0, trả top-3. Dưới 0.7 → "Mình chưa chắc, thử chụp lại nhé!". **Lối thoát cho nhãn yếu (apple…):** màn kết quả luôn có nút "Không đúng?" hiện top-3 để bé/phụ huynh chọn lại, hoặc mở danh sách từ vựng. Kiểm thử bằng vài ảnh mẫu từ `dataset/processed/test`. *Xong khi:* chạy được trên máy thật, ~<300 ms/ảnh, kết quả hợp lý với ảnh mẫu.

**C. Từ vựng.** `vocab.json` đủ 24 mục: `{id,label,en,vi,phonetic,exampleEn,exampleVi,image,audio,category}`. `tool/check_assets.dart` fail nếu thiếu nhãn/ảnh/audio. Màn danh sách (lưới, tìm kiếm, lọc chủ đề, đánh dấu đã học) + màn chi tiết.

**D. Âm thanh.** mp3 đóng gói sẵn, tên = `id`. `AudioService` phát từ/ví dụ/hiệu ứng đúng-sai/nhạc nền (có nút tắt). Tự đọc từ sau khi nhận diện. (Dùng TTS hệ điều hành `flutter_tts` chỉ là phương án dự phòng, ghi rõ trong báo cáo.)

**E. Game.** (1) Ghép: nghe âm → chọn hình (3–4 đáp án), làm trước. (2) Tìm vật: app đọc 1 từ, bé chụp vật thật, model xác nhận (chỉ dùng nhãn ổn định, loại `apple` hoặc cho phép bấm xác nhận thủ công). Sao/huy hiệu, lưu tiến độ bằng `shared_preferences`. Sai thì khuyến khích, không phạt.

**F. Thiết kế & UX.** Bảng màu, font tròn ≥18sp, nút ≥56dp, mascot tự vẽ (không dùng nhân vật có bản quyền), onboarding 3 bước, trạng thái loading/lỗi/trống, cổng phụ huynh cho cài đặt.

**G. Kiểm thử & đóng gói.** ≥2 máy Android thật; ghi thời gian suy luận và độ chính xác thực tế (thử cả `apple`). Build APK release, README, ảnh chụp màn hình.

## 4. Ưu tiên nếu thiếu thời gian
Bắt buộc: A → B → C → D (camera + model + thẻ từ + âm thanh). Sau đó game ghép, rồi F. Game tìm vật và camera live là phần cộng thêm.

## 5. Quy tắc cho Claude Code
- Mỗi phase một nhánh git, commit nhỏ, chạy `flutter analyze` + `flutter test` trước khi báo xong.
- Không đụng vào project ML, không train lại. Chỉ thêm `tflite_flutter` cho phần ML; hỏi trước khi thêm dependency khác.
- Không hardcode từ vựng trong code, chỉ trong `vocab.json`.
- Cuối mỗi phase tóm tắt: đã làm gì, chạy thế nào, còn tồn đọng.
- Mơ hồ về model → đối chiếu mục 0, nếu vẫn không rõ thì hỏi.

## 6. Prompt khởi động
> Đọc PLAN.md. Copy `model.tflite` và `labels.txt` vào `assets/ml/`. Bắt đầu Phase A: khởi tạo project Flutter theo mục 2, làm Home và màn camera chụp ảnh. Chạy analyze, tóm tắt rồi chờ mình duyệt trước khi sang Phase B.

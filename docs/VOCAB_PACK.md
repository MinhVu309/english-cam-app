# Gói từ vựng (cập nhật không cần sửa mã)

App luôn có sẵn bộ từ vựng và mô hình đóng gói trong APK, nên chạy được khi không có mạng.
Ngoài ra bố mẹ có thể bấm **Cài đặt → Cập nhật từ vựng** để tải một *gói từ vựng* từ một địa chỉ
hosting tĩnh. Gói có thể chứa:

- `vocab.json` mới (thêm/sửa/bớt từ và chủ đề),
- file âm thanh và ảnh của các từ mới,
- tuỳ chọn: `model.tflite` + `labels.txt` mới (nâng cấp nhận diện mà không build lại APK).

Không cần viết server: chỉ cần một nơi phục vụ file tĩnh qua **https** (GitHub Pages, Firebase Hosting, S3, Netlify...).
App chỉ gửi yêu cầu GET, không gửi dữ liệu nào đi.

## Cấu trúc thư mục gói

```
pack/
  manifest.json            # do tool sinh, KHÔNG sửa tay
  vocab.json               # bắt buộc, toàn bộ từ vựng (thay thế hẳn bản đóng gói sẵn)
  audio/words/giraffe.mp3
  audio/examples/giraffe.mp3
  images/giraffe.png       # tuỳ chọn (không có thì dùng emoji)
  model.tflite             # tuỳ chọn, đi cùng labels.txt
  labels.txt
```

`manifest.json`:

```json
{
  "version": 2,
  "notes": "Thêm hươu cao cổ",
  "files": [
    { "path": "vocab.json", "sha256": "<64 hex>", "size": 25408 },
    { "path": "audio/words/giraffe.mp3", "sha256": "<64 hex>", "size": 11392 }
  ]
}
```

- `version`: số nguyên tăng dần. App chỉ cập nhật khi lớn hơn bản đang cài.
- Mỗi file có `sha256` và `size`; app kiểm tra từng file, sai một file là bỏ cả lần cập nhật.
- Đường dẫn chỉ gồm chữ, số, `_ - .` và `/`; không có `..`. Tối đa 2000 file, mỗi file ≤ 30 MB.

## Đường dẫn trong `vocab.json`

Cùng một trường (`audio`, `exampleAudio`, `image`) có hai kiểu đường dẫn:

| Kiểu | Ví dụ | Nghĩa |
|---|---|---|
| Bắt đầu bằng `assets/` | `assets/audio/words/book.mp3` | file đã đóng gói sẵn trong APK |
| Tương đối | `audio/words/giraffe.mp3` | file nằm trong gói đã tải |

Trường `label` là **tuỳ chọn**. Từ có `label` (khớp một dòng trong `labels.txt`) thì chụp ảnh nhận ra được và
dùng được trong game "Tìm vật". Từ không có `label` chỉ để học (Từ vựng, game "Nghe & chọn hình").
Khi nâng cấp mô hình để nhận thêm vật, chỉ cần thêm `label` vào từ đó trong `vocab.json`.

## Quy trình cập nhật

Chạy từ thư mục gốc của project `english-cam-app/`.

```bash
# 1. Tạo thư mục gói từ vocab.json hiện tại (chỉ làm một lần)
dart run tool/build_pack.dart init pack

# 2. Thêm từ mới vào pack/vocab.json (copy một mục có sẵn rồi sửa; id duy nhất,
#    audio "audio/words/<id>.mp3", exampleAudio "audio/examples/<id>.mp3", category có trong "categories")

# 3. Sinh âm thanh cho các từ mới (macOS: say + ffmpeg; bỏ qua file đã có)
../.venv/bin/python tool/generate_audio.py --pack pack

# 4. Kiểm tra và ghi manifest.json (tăng --version mỗi lần)
dart run tool/build_pack.dart build pack --version 2 --notes "Thêm 10 từ về nghề nghiệp"

# 5. Upload TOÀN BỘ thư mục pack/ lên hosting, giữ nguyên cấu trúc
```

`build` báo lỗi nếu: thiếu trường, trùng id/label, chủ đề không tồn tại, file được tham chiếu không có trong
thư mục, chỉ có model mà thiếu labels (hoặc ngược lại). Nó cảnh báo nếu `labels.txt` và các `label` trong
`vocab.json` lệch nhau.

Trên điện thoại: **Cài đặt** (qua cổng phụ huynh) → **Cập nhật từ vựng** → **Kiểm tra & cập nhật** (hoặc
**Cập nhật ngay (bản N)** khi máy đã biết có bản mới). **Không phải nhập địa chỉ nào:** mặc định app lấy gói từ chính
backend của nó (`<API_URL>/api/pack/`). Chỉ khi muốn dùng hosting tĩnh khác (GitHub Pages...) thì mở mục **Nâng cao**
trong màn đó và dán địa chỉ thư mục chứa `manifest.json`, ví dụ `https://ten-ban.github.io/english-cam-pack/`; địa chỉ này
được nhớ cho lần sau ("Dùng lại địa chỉ mặc định" để quên). Có thể đặt sẵn lúc build:
`flutter build apk --release --dart-define=PACK_URL=https://ten-ban.github.io/english-cam-pack/` (không đặt thì dùng backend).

## Tự báo khi có bản mới

`PackWatcher` (`lib/services/pack_watcher.dart`) tự hỏi máy chủ phiên bản mới nhất: chỉ tải `manifest.json` (vài trăm byte),
không tải gói. Nó kiểm tra: sau ~6 giây khi mở app, **ngay khi vừa đăng nhập**, mỗi lần **quay lại app** (giãn cách tối thiểu
5 phút), và mỗi 30 phút khi đang mở. Chưa có phiên đăng nhập thì không gọi mạng. Có `version` lớn hơn bản đang dùng thì:

- hiện thông báo trong app **một lần cho mỗi phiên bản** (nhớ qua các lần mở app), bấm "Cập nhật" qua cổng phép nhân để mở màn cập nhật;
- Cài đặt hiện dấu và dòng "Có bản mới: bản N. Bấm để cập nhật." cho tới khi cập nhật;
- màn cập nhật tự kiểm tra khi mở, hiện ghi chú của bản mới và nút "Cập nhật ngay (bản N)".

Việc tải gói về vẫn do người dùng bấm nút. Máy chưa tải gói nào được coi là đang ở bản `kBundledPackVersion` (= 1, bản
đầu tiên backend phát chính là từ vựng đóng gói sẵn); **tăng hằng số này khi sửa `assets/vocab/vocab.json`**.
Đây là thông báo *trong app* (app đang mở hoặc vừa mở lại). Báo khi app đã đóng hẳn cần push của hệ điều hành
(FCM/APNs): chưa làm vì phải thêm dependency và cấu hình dịch vụ.

Chỉ tải lại những file đã đổi (so `sha256` với bản đang cài). Lần đầu tải gói lớn nên dùng Wi‑Fi.
Hosting có cache (GitHub Pages khoảng 10 phút): nếu bấm cập nhật mà chưa thấy bản mới, đợi một lát rồi thử lại.

## Nâng cấp mô hình bằng gói

1. Train và xuất như bình thường (`scripts/05_export_tflite.py` ở project ML), được `model.tflite` + `labels.txt`.
2. Chép cả hai vào `pack/`, thêm `label` cho các từ mới trong `pack/vocab.json`, chạy `build` với `--version` mới.

Mô hình phải đúng hợp đồng: input `[1,224,224,3]` float32 (pixel 0–255, tự `Rescaling` bên trong), output
`[1,N]` float32 softmax với N bằng số dòng trong `labels.txt`. App kiểm tra khi nạp; nếu mô hình mới sai
hợp đồng hoặc không nạp được thì **tự dùng lại mô hình đóng gói sẵn** và báo cho phụ huynh.

## An toàn và quay lui

- Release chỉ chấp nhận `https://` (bản debug cho phép `http://` để thử với máy chủ cục bộ).
- Tải vào thư mục tạm, kiểm tra hết rồi mới thay bản đang dùng; mất mạng/tắt app giữa chừng không làm hỏng bản cũ.
- `vocab.json` của gói hỏng hoặc không hợp lệ: app dùng bản đóng gói sẵn.
- **Cài đặt → Cập nhật từ vựng → Quay về bản gốc trong app** xoá gói đã tải. Tiến độ học của bé được giữ
  (tiến độ lưu theo `id` của từ, nên đừng đổi `id` của từ đã phát hành).
- `sha256` bảo vệ khỏi file hỏng/thiếu khi tải; việc đúng nguồn dựa vào https và quyền ghi vào hosting của bạn.
  Ai ghi được vào hosting thì thay được từ vựng và mô hình, hãy bảo vệ tài khoản hosting.

## Lấy gói từ backend ASP.NET

Thay cho hosting tĩnh, backend `english-cam-api` phát cùng định dạng gói tại `/api/pack/` (xem `english-cam-api/README.md`).
Admin sửa từ vựng và tải âm thanh/ảnh qua API, rồi `POST /api/admin/vocab/publish`; server sinh `manifest.json` (sha256/size) đúng chuẩn trên.
`PackUpdater` dùng được nguyên không sửa mã; địa chỉ mặc định của app đã trỏ sẵn tới `<API_URL>/api/pack/` nên không cần đặt `PACK_URL`. Đã kiểm chứng bằng `PackUpdater` thật và trên máy ảo (xem `docs/demo.md`).

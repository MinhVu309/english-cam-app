# Nguồn âm thanh

| Thư mục | Nguồn |
|---|---|
| `words/`, `examples/` | Giọng TTS của macOS (`say -v Samantha`, en_US), tạo bằng `tool/generate_audio.py` từ `assets/vocab/vocab.json`, chuyển mp3 bằng ffmpeg. |
| `sfx/`, `music/` | Tự tổng hợp bằng sóng sin (numpy) trong `tool/generate_audio.py`, không dùng mẫu âm thanh có sẵn. |

Chạy lại: `../.venv/bin/python tool/generate_audio.py` (cần macOS, ffmpeg, numpy).

**Lưu ý trước khi phát hành:** giọng đọc sinh từ TTS hệ điều hành của Apple. Với bài môn học thì ổn,
nhưng nếu phát hành thương mại nên thu giọng người thật hoặc dùng bộ TTS có giấy phép rõ ràng.

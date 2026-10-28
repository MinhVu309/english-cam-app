#!/usr/bin/env python3
"""Tạo toàn bộ âm thanh của app (chạy một lần, kết quả đã nằm trong assets/audio).

  ../.venv/bin/python tool/generate_audio.py            # chạy từ thư mục gốc project

Cho một gói từ vựng đặt trên hosting (xem docs/VOCAB_PACK.md): chỉ đọc các từ mà
vocab.json của gói trỏ tới file chưa có (đường dẫn tương đối, không phải assets/...):
  ../.venv/bin/python tool/generate_audio.py --pack pack

- words/<id>.mp3, examples/<id>.mp3: đọc từ vocab.json bằng giọng TTS của macOS
  (`say`, giọng Samantha, en_US) rồi chuyển sang mp3 bằng ffmpeg.
- sfx/*.mp3 và music/bg.mp3: tự tổng hợp bằng numpy (sóng sin), không dùng mẫu
  âm thanh có bản quyền.

Cần: macOS (`say`), ffmpeg, numpy.
"""
import argparse
import json
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "assets" / "audio"
VOICE = "Samantha"
SR = 44100

# Cắt khoảng lặng đầu/cuối (ngưỡng thấp để không cụt âm cuối) rồi chừa 80 ms đệm.
TRIM = (
    "areverse,silenceremove=start_periods=1:start_threshold=-60dB,"
    "areverse,silenceremove=start_periods=1:start_threshold=-60dB,"
    "apad=pad_dur=0.08,"
)


def to_mp3(src: Path, dst: Path, filt: str = "", bitrate: str = "96k") -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-ac", "1", "-ar", str(SR)]
    if filt:
        cmd += ["-af", filt]
    cmd += ["-codec:a", "libmp3lame", "-b:a", bitrate, str(dst)]
    subprocess.run(cmd, check=True)


def speak(text: str, dst: Path, rate: int) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        aiff = Path(tmp) / "s.aiff"
        subprocess.run(["say", "-v", VOICE, "-r", str(rate), "-o", str(aiff), text], check=True)
        to_mp3(aiff, dst, TRIM + "loudnorm=I=-16:TP=-1.5:LRA=11")


# ---- tổng hợp hiệu ứng / nhạc --------------------------------------------

def tone(freq, dur, vol=0.5, attack=0.01, release=0.12, harm=(1.0, 0.25, 0.1)):
    t = np.arange(int(SR * dur)) / SR
    w = sum(a * np.sin(2 * np.pi * freq * (i + 1) * t) for i, a in enumerate(harm))
    w = w / sum(harm)
    env = np.minimum(1.0, t / attack) * np.exp(-t / max(release, 1e-3))
    return vol * w * env


def place(buf, sig, start):
    i = int(start * SR)
    end = min(len(buf), i + len(sig))
    buf[i:end] += sig[: end - i]


def write_wav(path: Path, data: np.ndarray) -> None:
    data = np.clip(data, -1, 1)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes((data * 32767).astype("<i2").tobytes())


def sfx_tap():
    return tone(880, 0.12, 0.4, release=0.04)


def sfx_correct():
    buf = np.zeros(int(SR * 0.7))
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        place(buf, tone(f, 0.35, 0.45, release=0.12), k * 0.09)
    return buf


def sfx_wrong():
    # nhẹ nhàng, không gắt: hai nốt trầm đi xuống
    buf = np.zeros(int(SR * 0.55))
    place(buf, tone(392.0, 0.3, 0.4, attack=0.02, release=0.12, harm=(1, 0.1)), 0.0)
    place(buf, tone(311.13, 0.35, 0.4, attack=0.02, release=0.15, harm=(1, 0.1)), 0.16)
    return buf


def sfx_star():
    buf = np.zeros(int(SR * 1.0))
    for k, f in enumerate([783.99, 1046.5, 1318.5, 1567.98, 2093.0]):
        place(buf, tone(f, 0.5, 0.35, release=0.2), k * 0.08)
    return buf


def music():
    rng = np.random.default_rng(7)
    bpm = 96
    beat = 60 / bpm
    bars = 8
    total = bars * 4 * beat
    buf = np.zeros(int(SR * (total + 1.0)))
    # C, Am, F, G, C, Am, F, G  (bass, các nốt của hợp âm cho giai điệu)
    chords = [
        (130.81, [261.63, 329.63, 392.0, 523.25]),
        (110.00, [220.00, 261.63, 329.63, 440.00]),
        (87.31, [174.61, 261.63, 349.23, 440.00]),
        (98.00, [196.00, 293.66, 392.0, 493.88]),
    ] * 2
    for b, (bass, notes) in enumerate(chords):
        t0 = b * 4 * beat
        for k in range(4):  # bass mỗi phách
            place(buf, tone(bass * (2 if k % 2 else 1), beat * 1.6, 0.16, attack=0.02, release=0.35, harm=(1, 0.15)), t0 + k * beat)
        pos = 0.0
        while pos < 4 * beat - 0.01:
            dur = float(rng.choice([0.5, 0.5, 1.0])) * beat
            if pos + dur > 4 * beat:
                dur = 4 * beat - pos
            f = float(rng.choice(notes)) * float(rng.choice([1, 1, 2]))
            place(buf, tone(f, dur * 1.8, 0.2, attack=0.015, release=0.28), t0 + pos)
            pos += dur
    # đuôi ngân ngắn rồi cắt để vòng lặp không bị giật
    buf = buf[: int(SR * total)]
    fade = int(SR * 0.05)
    buf[-fade:] *= np.linspace(1, 0, fade)
    return buf * 0.9


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", type=Path, help="thư mục gói: đọc <pack>/vocab.json, ghi mp3 vào <pack>/<đường dẫn trong vocab>")
    ap.add_argument("--only-missing", action="store_true", help="bỏ qua file mp3 đã có (mặc định khi dùng --pack)")
    ap.add_argument("--speech-only", action="store_true", help="không tạo lại sfx/nhạc nền")
    args = ap.parse_args()

    if args.pack:
        vocab_path, out_root = args.pack / "vocab.json", args.pack
        args.only_missing = args.speech_only = True
    else:
        vocab_path, out_root = ROOT / "assets" / "vocab" / "vocab.json", ROOT
    vocab = json.loads(vocab_path.read_text(encoding="utf-8"))
    for w in vocab["words"]:
        done = False
        for key, text, rate in (("audio", w["en"], 135), ("exampleAudio", w["exampleEn"], 150)):
            rel = w.get(key)
            if not rel or (args.pack and rel.startswith("assets/")):
                continue  # trong gói, đường dẫn assets/... là file đã đóng gói sẵn trong app
            dst = out_root / rel
            if args.only_missing and dst.exists():
                continue
            speak(text, dst, rate=rate)
            done = True
        if done:
            print("speech", w["id"])
    if args.speech_only:
        return

    with tempfile.TemporaryDirectory() as tmp:
        for name, sig in {
            "tap": sfx_tap(),
            "correct": sfx_correct(),
            "wrong": sfx_wrong(),
            "star": sfx_star(),
        }.items():
            wav = Path(tmp) / f"{name}.wav"
            write_wav(wav, sig)
            to_mp3(wav, AUDIO / "sfx" / f"{name}.mp3", "loudnorm=I=-18:TP=-1.5:LRA=7")
        wav = Path(tmp) / "bg.wav"
        write_wav(wav, music())
        to_mp3(wav, AUDIO / "music" / "bg.mp3", "loudnorm=I=-20:TP=-2:LRA=7", "128k")
    print("sfx + music done")


if __name__ == "__main__":
    main()

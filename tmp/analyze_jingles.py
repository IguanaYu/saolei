# -*- coding: utf-8 -*-
# NES jingles 音高轨迹分析：挑 win（大调上扬收尾）/ lose（下落收尾）+ OGG 写入能力测试
import sys, io, glob, os
import numpy as np
import soundfile as sf

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

NOTE_NAMES = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B']

def hz_to_note(f):
    if f <= 0: return '--'
    midi = int(round(12 * np.log2(f / 440.0) + 69))
    return NOTE_NAMES[midi % 12] + str(midi // 12 - 1)

def track_pitch(mono, sr, hop_s=0.09, win_s=0.18):
    """自相关基频追踪，返回每帧 (t, f0)"""
    hop = int(sr * hop_s); win = int(sr * win_s)
    frames = []
    for start in range(0, len(mono) - win, hop):
        seg = mono[start:start+win]
        if np.sqrt(np.mean(seg**2)) < 0.01:
            frames.append((start/sr, 0.0)); continue
        seg = seg - seg.mean()
        ac = np.correlate(seg, seg, 'full')[len(seg)-1:]
        # 基频范围 80-2000Hz
        lo, hi = int(sr/2000), int(sr/80)
        if hi >= len(ac): frames.append((start/sr, 0.0)); continue
        peak_idx = lo + int(np.argmax(ac[lo:hi]))
        if ac[peak_idx] > 0.3 * ac[0]:
            frames.append((start/sr, sr/peak_idx))
        else:
            frames.append((start/sr, 0.0))
    return frames

def midi_of(f):
    return 12 * np.log2(f / 440.0) + 69 if f > 0 else np.nan

JNG = "f:/godot_game/扫雷_增量/saolei/tmp/kenney_kenney_music-jingles/Audio/8-Bit jingles"
cands = ["jingles_NES00.ogg","jingles_NES03.ogg","jingles_NES04.ogg","jingles_NES05.ogg",
         "jingles_NES06.ogg","jingles_NES07.ogg","jingles_NES08.ogg","jingles_NES11.ogg",
         "jingles_NES12.ogg","jingles_NES13.ogg","jingles_NES16.ogg"]

print(f"{'file':22s} {'dur_s':>5s}  pitch_track (每帧主音)  | 首半均值midi 尾半均值midi 走向 末音")
for name in cands:
    p = f"{JNG}/{name}"
    data, sr = sf.read(p, always_2d=True)
    mono = data.mean(axis=1)
    tr = track_pitch(mono, sr)
    notes = [hz_to_note(f) for _, f in tr if f > 0]
    midis = np.array([midi_of(f) for _, f in tr])
    midis = midis[~np.isnan(midis)]
    half = len(midis)//2 if len(midis) else 0
    first_half = midis[:half].mean() if half else 0
    last_half = midis[half:].mean() if half else 0
    contour = "UP" if last_half > first_half + 1 else ("DOWN" if last_half < first_half - 1 else "FLAT")
    last_note = notes[-1] if notes else '--'
    track_str = ' '.join(notes[:16])
    print(f"{name:22s} {len(mono)/sr:5.1f}  {track_str:48s} | {first_half:6.1f} {last_half:6.1f} {contour:4s} {last_note}")

# OGG 写入能力测试
print("\n=== OGG write test ===")
try:
    t = np.linspace(0, 0.1, 4410, endpoint=False)
    test_sig = (0.5 * np.sin(2*np.pi*440*t)).astype(np.float64)
    sf.write("f:/godot_game/扫雷_增量/saolei/tmp/_ogg_test.ogg", test_sig, 44100, format='OGG', subtype='VORBIS')
    back, bsr = sf.read("f:/godot_game/扫雷_增量/saolei/tmp/_ogg_test.ogg")
    print(f"OGG write/read OK: {len(back)} samples @ {bsr}Hz")
except Exception as e:
    print(f"OGG write FAILED: {e}")

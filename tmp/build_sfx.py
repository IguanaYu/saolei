# -*- coding: utf-8 -*-
# SFX 素材加工：Kenney 原包 → 选段/增益归一/修剪 → assets/audio/sfx/*.ogg
# 目标响度（RMS dBFS）：常规 SFX ≈ -17；win/lose jingle -14；ui -25（极轻）；heartbeat -27（比批次低10dB）
import sys, io, os
import numpy as np
import soundfile as sf

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

TMP = "f:/godot_game/扫雷_增量/saolei/tmp"
IMP = f"{TMP}/kenney_kenney_impact-sounds/Audio"
INT = f"{TMP}/kenney_kenney_interface-sounds/Audio"
DIG = f"{TMP}/kenney_kenney_digital-audio/Audio"
JNG = f"{TMP}/kenney_kenney_music-jingles/Audio/8-Bit jingles"
OUT = "f:/godot_game/扫雷_增量/saolei/assets/audio/sfx"

# (输出名, 源文件, 目标RMS_dB, 修剪尾音)
PLAN = [
    ("open.ogg",      f"{IMP}/impactGeneric_light_001.ogg", -20.0, True),
    ("flag.ogg",      f"{INT}/toggle_004.ogg",              -19.0, True),
    ("mine.ogg",      f"{IMP}/impactSoft_heavy_000.ogg",    -17.0, True),
    ("coin.ogg",      f"{DIG}/twoTone1.ogg",                -17.0, True),
    ("buy.ogg",       f"{INT}/confirmation_001.ogg",        -17.0, True),
    ("upgrade.ogg",   f"{DIG}/highUp.ogg",                  -16.0, True),
    ("win.ogg",       f"{JNG}/jingles_NES12.ogg",           -14.0, False),
    ("lose.ogg",      f"{JNG}/jingles_NES00.ogg",           -14.0, False),
    ("ui.ogg",        f"{INT}/click_001.ogg",               -25.0, True),
    ("heartbeat.ogg", f"{IMP}/impactSoft_heavy_004.ogg",    -27.0, True),
]

def envelope_db(mono, sr, win_ms=20):
    win = max(1, int(sr * win_ms / 1000))
    n = len(mono) // win
    rms = np.sqrt(np.mean(mono[:n*win].reshape(n, win) ** 2, axis=1) + 1e-12)
    return 20 * np.log10(rms + 1e-12), win

def process(out_name, src, target_rms, trim_tail):
    data, sr = sf.read(src, always_2d=True)
    mono = data.mean(axis=1).astype(np.float64)
    orig_dur = len(mono) / sr
    rms = np.sqrt(np.mean(mono ** 2) + 1e-12)
    gain_db = target_rms - 20 * np.log10(rms)
    mono *= 10 ** (gain_db / 20)
    # 峰值限制到 -1dBFS
    peak = np.max(np.abs(mono))
    ceil = 10 ** (-1.0 / 20)
    if peak > ceil:
        mono *= ceil / peak
    # 修剪首部静音（>30ms 且低于 -50dB 的段）
    env_db, win = envelope_db(mono, sr)
    lead_sil = 0
    for e in env_db:
        if e < -50: lead_sil += 1
        else: break
    start = max(0, lead_sil * win - int(sr * 0.01))
    # 修剪尾部（包络低于 -45dB 后 50ms 收刀）
    if trim_tail:
        tail_sil = len(env_db)
        for i in range(len(env_db) - 1, -1, -1):
            if env_db[i] > -45: tail_sil = i + 1; break
        end = min(len(mono), tail_sil * win + int(sr * 0.05))
    else:
        end = len(mono)
    out = mono[start:end]
    os.makedirs(OUT, exist_ok=True)
    sf.write(f"{OUT}/{out_name}", out, sr, format='OGG', subtype='VORBIS')
    print(f"{out_name:14s} <- {os.path.basename(src):32s} "
          f"gain={gain_db:+5.1f}dB  {orig_dur*1000:4.0f}ms->{len(out)/sr*1000:4.0f}ms")
    return out_name

for row in PLAN:
    process(*row)

# 回读复核
print("\n=== 回读复核 ===")
print(f"{'file':14s} {'dur_ms':>6s} {'rms_db':>7s} {'peak_db':>8s}")
for name, *_ in PLAN:
    d, sr = sf.read(f"{OUT}/{name}", always_2d=True)
    m = d.mean(axis=1)
    r = 20 * np.log10(np.sqrt(np.mean(m**2)) + 1e-12)
    p = 20 * np.log10(np.max(np.abs(m)) + 1e-12)
    print(f"{name:14s} {len(m)/sr*1000:6.0f} {r:7.1f} {p:8.1f}")

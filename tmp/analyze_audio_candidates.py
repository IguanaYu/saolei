# -*- coding: utf-8 -*-
# 音效候选量化分析：时长 / RMS / 峰值 / 频谱质心 / 结尾衰减比（判断 jingle 是否渐弱收尾）
import sys, io, glob, os
import numpy as np
import soundfile as sf

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def analyze(path):
    data, sr = sf.read(path, always_2d=True)
    mono = data.mean(axis=1)
    n = len(mono)
    dur = n / sr
    rms = float(np.sqrt(np.mean(mono ** 2)) + 1e-12)
    peak = float(np.max(np.abs(mono)) + 1e-12)
    rms_db = 20 * np.log10(rms)
    peak_db = 20 * np.log10(peak)
    # 频谱质心（前 0.5s 或全长）
    seg = mono[: min(n, int(sr * 0.5))]
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
    freqs = np.fft.rfftfreq(len(seg), 1 / sr)
    centroid = float(np.sum(freqs * spec) / (np.sum(spec) + 1e-12))
    # 低频能量占比 (<200Hz)
    low_ratio = float(np.sum(spec[freqs < 200]) / (np.sum(spec) + 1e-12))
    # 结尾 300ms RMS / 整体 RMS（jingle 判断是否渐弱收尾，越小越淡出）
    tail = mono[max(0, n - int(sr * 0.3)):]
    tail_rms = float(np.sqrt(np.mean(tail ** 2)) + 1e-12)
    tail_ratio = tail_rms / rms
    return dict(dur=dur, rms_db=rms_db, peak_db=peak_db, centroid=centroid,
                low_ratio=low_ratio, tail_ratio=tail_ratio, sr=sr)

def show(label, paths):
    print(f"\n### {label}")
    print(f"{'file':44s} {'dur_ms':>7s} {'rms_db':>7s} {'peak_db':>8s} {'centroid':>9s} {'low<200':>8s} {'tail_r':>7s}")
    for p in paths:
        if not os.path.exists(p):
            print(f"{os.path.basename(p):44s} MISSING"); continue
        a = analyze(p)
        print(f"{os.path.basename(p):44s} {a['dur']*1000:7.0f} {a['rms_db']:7.1f} {a['peak_db']:8.1f} "
              f"{a['centroid']:9.0f} {a['low_ratio']:8.2f} {a['tail_ratio']:7.2f}")

TMP = "f:/godot_game/扫雷_增量/saolei/tmp"
IMP = f"{TMP}/kenney_kenney_impact-sounds/Audio"
INT = f"{TMP}/kenney_kenney_interface-sounds/Audio"
RPG = f"{TMP}/kenney_kenney_rpg-audio/Audio"
DIG = f"{TMP}/kenney_kenney_digital-audio/Audio"
JNG = f"{TMP}/kenney_kenney_music-jingles/Audio"

show("open 候选（impact-sounds 挖掘/轻击）", [f"{IMP}/impactMining_00{i}.ogg" for i in range(5)]
     + [f"{IMP}/impactGeneric_light_00{i}.ogg" for i in range(5)]
     + [f"{IMP}/footstep_grass_00{i}.ogg" for i in range(5)]
     + [f"{IMP}/footstep_concrete_00{i}.ogg" for i in range(5)])
show("flag 候选（switch/toggle/click/tick）", [f"{INT}/{n}" for n in
     ["switch_001.ogg","switch_002.ogg","switch_003.ogg","switch_004.ogg","switch_005.ogg","switch_006.ogg","switch_007.ogg",
      "toggle_001.ogg","toggle_002.ogg","toggle_003.ogg","toggle_004.ogg",
      "click_001.ogg","click_002.ogg","click_003.ogg","click_004.ogg","click_005.ogg",
      "tick_001.ogg","tick_002.ogg","tick_004.ogg"]])
show("mine 候选（重击）", [f"{IMP}/impactPunch_heavy_00{i}.ogg" for i in range(5)]
     + [f"{IMP}/impactMetal_heavy_00{i}.ogg" for i in range(5)]
     + [f"{IMP}/impactBell_heavy_00{i}.ogg" for i in range(5)]
     + [f"{IMP}/impactSoft_heavy_00{i}.ogg" for i in range(5)]
     + [f"{DIG}/lowDown.ogg", f"{DIG}/spaceTrash1.ogg", f"{DIG}/spaceTrash2.ogg", f"{DIG}/zap1.ogg"])
show("coin 候选", [f"{RPG}/handleCoins.ogg", f"{RPG}/handleCoins2.ogg", f"{RPG}/metalClick.ogg"]
     + [f"{DIG}/{n}" for n in ["twoTone1.ogg","twoTone2.ogg","highUp.ogg","tone1.ogg","threeTone1.ogg"]])
show("buy/upgrade 候选（confirmation/powerUp）", [f"{INT}/confirmation_00{i}.ogg" for i in range(1,5)]
     + [f"{DIG}/powerUp1.ogg", f"{DIG}/powerUp2.ogg", f"{DIG}/powerUp3.ogg", f"{DIG}/phaserUp7.ogg"])
show("ui 候选（最轻 click）", [f"{INT}/click_001.ogg", f"{INT}/tick_001.ogg", f"{INT}/tick_002.ogg",
     f"{INT}/pluck_001.ogg", f"{INT}/pluck_002.ogg"])
show("heartbeat 候选（低频脉冲）", [f"{DIG}/lowDown.ogg", f"{DIG}/lowThreeTone.ogg", f"{DIG}/lowRandom.ogg"]
     + [f"{IMP}/impactSoft_heavy_00{i}.ogg" for i in range(5)])

# jingles 全量时长扫描（BGM + win/lose 候选）
print("\n### music-jingles 全量（按时长排序）")
rows = []
for p in glob.glob(f"{JNG}/**/*.ogg", recursive=True):
    a = analyze(p)
    rows.append((a['dur'], os.path.relpath(p, JNG), a['tail_ratio'], a['centroid'], a['rms_db']))
rows.sort()
for dur, name, tr, ce, rd in rows:
    print(f"{name:52s} {dur:6.1f}s tail_r={tr:5.2f} centroid={ce:6.0f} rms={rd:6.1f}")

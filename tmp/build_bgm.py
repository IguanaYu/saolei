# -*- coding: utf-8 -*-
# BGM 程序合成（文档 §4.2 兜底方案）：132BPM C大调 C-G-Am-F，8小节两段体×4遍 ≈ 58s 无缝循环
# 主旋律方波 duty0.25 vol0.22 八分音符 / 贝斯三角波 vol0.30 四分音符 / 噪声hi-hat+扫频底鼓 / 软限幅 / 整小节相位对齐
import sys, io, os
import numpy as np
import soundfile as sf

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

SR = 44100
BPM = 132
QTR = round(60 / BPM * SR)          # 每拍采样数（整数，保证小节边界相位对齐）
EIGHTH = QTR // 2
BAR = QTR * 4
BARS = 32                            # 8小节 × 4遍
TOTAL = BAR * BARS
mix = np.zeros(TOTAL)

def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)

def add(dst, start, sig):
    end = min(TOTAL, start + len(sig))
    if start < TOTAL:
        dst[start:end] += sig[:end - start]

def note_env(n, attack_s=0.005, release_s=0.02, sustain=1.0):
    """音符包络：5ms 起音 + 尾部释放，防爆音"""
    a = int(attack_s * SR); r = int(release_s * SR)
    env = np.full(n, sustain)
    if a > 0: env[:a] = np.linspace(0, sustain, a)
    if r > 0: env[-r:] *= np.linspace(1, 0, r)
    return env

# ---- 主旋律：每小节 8 个八分音符（0=休止）----
PHRASE_A = [
    [76, 79, 84, 79, 81, 79, 76, 0],   # C:  E5 G5 C6 G5  A5 G5 E5 rest
    [74, 79, 83, 79, 81, 83, 86, 0],   # G:  D5 G5 B5 G5  A5 B5 D6 rest
    [72, 76, 81, 76, 84, 81, 76, 0],   # Am: C5 E5 A5 E5  C6 A5 E5 rest
    [81, 77, 72, 77, 81, 79, 77, 0],   # F:  A5 F5 C5 F5  A5 G5 F5 rest
]
PHRASE_B = [
    [79, 76, 72, 76, 79, 84, 88, 86],  # C:  G5 E5 C5 E5  G5 C6 E6 D6
    [83, 79, 74, 79, 83, 86, 79, 0],   # G:  B5 G5 D5 G5  B5 D6 G5 rest
    [81, 84, 88, 84, 81, 76, 72, 0],   # Am: A5 C6 E6 C6  A5 E5 C5 rest
    [77, 81, 84, 81, 79, 76, 72, 0],   # F:  F5 A5 C6 A5  G5 E5 C5 rest
]
MELODY = (PHRASE_A + PHRASE_B) * 4     # 32 小节

# ---- 贝斯：每小节 4 个四分音符 根-根-五度-根 ----
BASS_ROOTS = [(48, 55), (43, 50), (45, 52), (41, 48)]  # (C3,G3)(G2,D3)(A2,E3)(F2,C3)
BASS = []
for root, fifth in BASS_ROOTS:
    BASS += [root, root, fifth, root]
BASS *= 8

rng = np.random.default_rng(42)

for bar in range(BARS):
    t0 = bar * BAR
    # 主旋律
    for i, m in enumerate(MELODY[bar]):
        if m == 0:
            continue
        n = EIGHTH
        ph = (np.arange(n) / SR) * midi_hz(m)
        sq = np.where(ph % 1.0 < 0.25, 1.0, -1.0)   # 方波 duty 0.25
        sig = 0.22 * sq * note_env(n)
        add(mix, t0 + i * EIGHTH, sig)
    # 贝斯（三角波）
    for i, m in enumerate(BASS[bar * 4:(bar + 1) * 4]):
        n = QTR
        ph = (np.arange(n) / SR) * midi_hz(m)
        tri = 2.0 * np.abs(2.0 * (ph % 1.0) - 1.0) - 1.0
        env = note_env(n, 0.004, 0.03)
        env *= np.linspace(1.0, 0.75, n)             # 每音轻微衰减，不那么机械
        add(mix, t0 + i * QTR, 0.30 * tri * env)
    # 底鼓（每拍，100→50Hz 扫频 80ms）
    for i in range(4):
        n = int(0.12 * SR)
        tt = np.arange(n) / SR
        f = 100.0 * (50.0 / 100.0) ** (tt / 0.08)
        phase = 2 * np.pi * np.cumsum(f) / SR
        kick = np.sin(phase) * np.exp(-tt / 0.05)
        add(mix, t0 + i * QTR, 0.5 * kick)
    # hi-hat（每个八分，30ms 衰减；正拍加 Accent）
    for i in range(8):
        n = int(0.05 * SR)
        noise = rng.standard_normal(n) * np.exp(-np.arange(n) / SR / 0.012)
        accent = 1.6 if i % 2 == 0 else 1.0
        add(mix, t0 + i * EIGHTH, 0.06 * accent * noise)

# 软限幅 + 归一到 0.85 峰值 + 去直流
mix = np.tanh(mix / 0.9) * 0.9
mix -= mix.mean()
mix *= 0.85 / np.max(np.abs(mix))

# ---- 循环边界数值自检 ----
tail_rms = 20 * np.log10(np.sqrt(np.mean(mix[-int(0.005*SR):]**2)) + 1e-12)
head_rms = 20 * np.log10(np.sqrt(np.mean(mix[:int(0.005*SR):]**2)) + 1e-12)
print(f"时长 {TOTAL/SR:.2f}s | 小节 {BARS} | 峰值 {np.max(np.abs(mix)):.3f} | "
      f"头5ms {head_rms:.1f}dB 尾5ms {tail_rms:.1f}dB（循环点两侧均应安静）")

OUT = "f:/godot_game/扫雷_增量/saolei/assets/audio/bgm/bgm_main.ogg"
os.makedirs(os.path.dirname(OUT), exist_ok=True)
# 一次性大块 sf.write 会被环境杀进程（exit127），分块写入绕过
with sf.SoundFile(OUT, 'w', samplerate=SR, channels=1, format='OGG', subtype='VORBIS') as f:
    for i in range(0, TOTAL, SR):
        f.write(mix[i:i + SR])

d, sr = sf.read(OUT)
print(f"回读：{len(d)/sr:.2f}s @{sr}Hz  rms={20*np.log10(np.sqrt(np.mean(d**2))+1e-12):.1f}dB  "
      f"loop边界差={abs(d[0]-d[-1]):.4f}")

"""第二章原创合成音：numpy + 标准库 wave；不使用采样版权素材。"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SR = 24000
RNG = np.random.default_rng(20261012)


def tone(seconds, start, end=None, decay=12, harmonics=0.12):
    t = np.arange(round(seconds * SR)) / SR
    end = start if end is None else end
    phase = 2 * np.pi * (start * t + (end - start) * t * t / (2 * seconds))
    attack = np.minimum(t / 0.004, 1)
    release = np.minimum((seconds - t) / 0.018, 1)
    return (np.sin(phase) + harmonics * np.sin(phase * 2)) * attack * release * np.exp(-t * decay)


def noise(seconds, decay=22):
    n = round(seconds * SR)
    raw = RNG.uniform(-1, 1, n)
    filtered = np.convolve(raw, np.ones(7) / 7, mode="same")
    t = np.arange(n) / SR
    return filtered * np.minimum(t / 0.003, 1) * np.minimum((seconds - t) / 0.015, 1) * np.exp(-t * decay)


def layer(length, *items):
    out = np.zeros(round(length * SR))
    for at, audio, gain in items:
        start = round(at * SR)
        count = min(len(audio), len(out) - start)
        out[start:start + count] += audio[:count] * gain
    return out


REPORT = []


def save(relative, audio, peak=0.55):
    audio = np.nan_to_num(audio)
    audio -= np.mean(audio)
    audio *= peak / max(np.max(np.abs(audio)), 1e-8)
    audio[:96] *= np.linspace(0, 1, 96)
    audio[-96:] *= np.linspace(1, 0, 96)
    pcm = np.round(np.clip(audio, -1, 1) * 32767).astype("<i2")
    target = ROOT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(target), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())
    REPORT.append({"file": relative, "seconds": round(len(audio) / SR, 3), "peak": round(float(np.max(np.abs(audio))), 4), "rms": round(float(np.sqrt(np.mean(audio * audio))), 4), "loop_join": int(pcm[-1]) - int(pcm[0])})


def sfx():
    sounds = {
        "laser": layer(.24, (0, tone(.22, 1150, 190, 15, .22), .7), (0, noise(.10, 35), .22)),
        "wall_chip": layer(.17, (0, noise(.16, 27), .8), (0, tone(.12, 230, 125, 28), .3)),
        "wall_break": layer(.30, (0, noise(.28, 17), .7), (0, tone(.25, 160, 55, 18), .5), (.035, noise(.16, 25), .25)),
        "charge": layer(.38, (0, tone(.32, 390, 930, 7), .6), (.06, tone(.28, 780, 1860, 10), .16)),
        "ore_burst": layer(.48, (0, tone(.43, 587, None, 10), .6), (.045, tone(.40, 880, None, 11), .4), (.09, tone(.36, 1175, None, 12), .25)),
        "overload": layer(.46, (0, tone(.42, 180, 38, 12, .32), .7), (0, noise(.32, 13), .8), (.045, tone(.24, 310, 70, 15), .35)),
        "builder_rift": layer(.60, (0, tone(.25, 220, None, 11), .5), (.22, tone(.28, 277, 220, 10), .45), (.38, noise(.16, 20), .2)),
        "builder_build": layer(.23, (0, noise(.10, 35), .4), (.045, tone(.14, 180, 115, 24), .6), (.10, noise(.11, 32), .3)),
        "builder_break": layer(.33, (0, tone(.28, 360, 95, 14), .5), (0, noise(.29, 17), .5), (.06, tone(.20, 130, 65, 20), .4)),
    }
    for name, audio in sounds.items():
        save(f"assets/audio/sfx/ch02_{name}.wav", audio, .62 if name in ("overload", "wall_break") else .5)


def bgm():
    # Dm7 / Bbmaj7 / Cadd9 / Asus4；16小节，无主旋律尖峰，留出机制音效频段。
    beat = 60 / 108
    bars = 16
    total = round(bars * 4 * beat * SR)
    out = np.zeros(total)
    chords = [[50, 57, 60, 65], [46, 53, 57, 62], [48, 55, 62, 64], [45, 52, 57, 62]]

    def put(at, audio, gain):
        # 尾音环绕写入，确保最后小节的余音延续到第一小节。
        indices = (round(at * SR) + np.arange(len(audio))) % total
        np.add.at(out, indices, audio * gain)

    def hz(note):
        return 440 * 2 ** ((note - 69) / 12)

    for bar in range(bars):
        chord = chords[(bar // 2) % 4]
        start = bar * 4 * beat
        for j in range(8):
            note = chord[[0, 2, 1, 3, 0, 1, 2, 1][j]] + 12
            put(start + j * beat / 2, tone(beat * 2, hz(note), decay=5.8, harmonics=.04), .055 if j % 2 else .075)
        for j in [0, 2]:
            put(start + j * beat, tone(beat * 1.8, hz(chord[0] - 12), decay=4.5, harmonics=.25), .11)
        for j in range(4):
            put(start + j * beat, tone(.11, 90, 46, 30), .04)
            put(start + (j + .5) * beat, noise(.08, 55), .018)
        # 柔和晶体和音，每两小节一次；结尾不会切断长尾。
        if bar % 2 == 0:
            for note in chord[1:]:
                put(start + beat / 4, tone(beat * 4, hz(note + 12), decay=2.6, harmonics=.03), .022)
    # 循环边界很短的交叉淡化，保留余音而消除首尾采样跳变。
    fade = 240
    mix = (out[:fade] + out[-fade:]) / 2
    out[:fade] = mix
    out[-fade:] = mix
    save("assets/audio/bgm/bgm_ch02_v1.wav", out, .30)


if __name__ == "__main__":
    sfx()
    bgm()
    dest = ROOT / "assets/audio/ch02_v1_manifest.json"
    dest.write_text(json.dumps(REPORT, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(REPORT, indent=2))

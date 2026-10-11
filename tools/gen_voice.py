"""만화풍 비명/감탄 소리를 포먼트 합성으로 만든다 -> assets/sfx/voice_*.wav"""
import os, wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
rng = np.random.default_rng(3)


def save(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.85
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32000).astype(np.int16).tobytes())


def resonator(x, f, bw):
    # 2차 공진 필터 (포먼트)
    r = np.exp(-np.pi * bw / SR)
    a1 = -2 * r * np.cos(2 * np.pi * f / SR)
    a2 = r * r
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    for i, v in enumerate(x):
        yy = v - a1 * y1 - a2 * y2
        y[i] = yy
        y2, y1 = y1, yy
    return y


VOWELS = {"a": (800, 1250, 2600), "eu": (380, 1500, 2400), "e": (500, 1900, 2600), "i": (300, 2300, 3000), "o": (450, 850, 2500), "u": (330, 900, 2300)}


def voice(dur, f0_curve, vowel_curve, vib=5.5, vib_amt=0.03, breath=0.05):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f0 = np.interp(t, np.linspace(0, dur, len(f0_curve)), f0_curve)
    f0 = f0 * (1 + vib_amt * np.sin(2 * np.pi * vib * t))
    phase = np.cumsum(f0) / SR
    src = (phase % 1.0) * 2 - 1                          # 톱니파 성대
    src = src + breath * rng.uniform(-1, 1, n)
    # 모음이 바뀌는 구간마다 따로 필터해서 이어 붙인다
    seg = np.array_split(np.arange(n), len(vowel_curve))
    out = np.zeros(n)
    for idx, v in zip(seg, vowel_curve):
        f1, f2, f3 = VOWELS[v]
        s = src[max(0, idx[0] - 400): idx[-1] + 1]
        y = resonator(s, f1, 90) + 0.6 * resonator(s, f2, 120) + 0.25 * resonator(s, f3, 180)
        out[idx] = y[-len(idx):]
    env = np.minimum(1, t / 0.02) * np.minimum(1, (dur - t) / 0.08)
    return out * np.clip(env, 0, 1)


save("voice_ah", voice(0.32, [170, 150, 110], ["a"]))
save("voice_ugh", voice(0.5, [140, 190, 120, 90], ["eu", "a", "a"]))
save("voice_hey", voice(0.28, [150, 230], ["e"], vib_amt=0.01))
save("voice_ow", voice(0.35, [220, 260, 180], ["a", "u"]))
save("voice_kid", voice(0.3, [330, 390, 300], ["a"]))
save("voice_kid2", voice(0.32, [360, 290], ["i", "a"]))
save("voice_scream", voice(0.9, [230, 420, 380, 260, 180], ["a", "a", "a", "a"], vib=7, vib_amt=0.06))
save("voice_boss", voice(0.7, [95, 80, 65], ["o", "u"], breath=0.2))
# 재채기: 아-아- 에취!
a = voice(0.18, [200, 260], ["a"]) * 0.6
b = voice(0.2, [230, 300], ["a"]) * 0.8
n = int(SR * 0.22)
burst = rng.uniform(-1, 1, n) * np.exp(-np.arange(n) / (SR * 0.06))
burst = resonator(burst, 2500, 900) * 0.4 + voice(0.22, [320, 200], ["u"])
save("voice_achoo", np.concatenate([a, np.zeros(1500), b, np.zeros(800), burst]))
print("voices done")

# 무전기 삐빅 + 지직
n1 = int(SR * 0.09)
beep = np.sin(2 * np.pi * 1400 * np.arange(n1) / SR) * 0.5
gap = np.zeros(int(SR * 0.05))
beep2 = np.sin(2 * np.pi * 1800 * np.arange(n1) / SR) * 0.5
st = rng.uniform(-1, 1, int(SR * 0.35))
st = resonator(st, 1800, 1500) * np.linspace(1, 0, len(st)) ** 2 * 0.6
save("radio", np.concatenate([beep, gap, beep2, gap, st]))
print("radio done")

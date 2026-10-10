"""물소리 효과음과 BGM을 합성해서 assets/sfx, assets/music 에 wav로 저장한다."""
import os
import wave
import numpy as np

SR = 22050
ROOT = os.path.join(os.path.dirname(__file__), "..", "assets")
rng = np.random.default_rng(7)


def save(path, x):
    x = np.clip(x, -1, 1)
    data = (x * 32000).astype(np.int16)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def t(sec):
    return np.arange(int(SR * sec)) / SR


def noise(sec):
    return rng.uniform(-1, 1, int(SR * sec))


def lowpass(x, a):
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def highpass(x, a):
    return x - lowpass(x, a)


def env(n, attack, release_pow=2.0):
    e = np.ones(n)
    na = max(1, int(SR * attack))
    e[:na] = np.linspace(0, 1, na)
    e[na:] = np.linspace(1, 0, n - na) ** release_pow
    return e


def loopify(x, fade=0.15):
    nf = int(SR * fade)
    head, body = x[:nf], x[nf:]
    w = np.linspace(0, 1, nf)
    body[-nf:] = body[-nf:] * (1 - w) + head * w
    return body


def norm(x, peak=0.8):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


sfx = os.path.join(ROOT, "sfx")
music = os.path.join(ROOT, "music")

# 분무기 한 번 칙
x = highpass(noise(0.18), 0.25) * env(int(SR * 0.18), 0.005, 3)
save(os.path.join(sfx, "spray.wav"), norm(x, 0.6))

# 물줄기 루프 (물총/슈퍼소커)
x = lowpass(highpass(noise(1.3), 0.08), 0.5)
x *= 1 + 0.25 * np.sin(2 * np.pi * 13 * t(1.3))
save(os.path.join(sfx, "stream_loop.wav"), norm(loopify(x), 0.45))

# 소방호스 루프 (더 굵고 낮게)
x = lowpass(noise(1.3), 0.18) + 0.3 * lowpass(highpass(noise(1.3), 0.1), 0.4)
x *= 1 + 0.15 * np.sin(2 * np.pi * 7 * t(1.3))
save(os.path.join(sfx, "hose_loop.wav"), norm(loopify(x), 0.6))

# 맞을 때 철퍽
n = int(SR * 0.25)
x = lowpass(noise(0.25), 0.35) * env(n, 0.002, 4)
x += 0.5 * np.sin(2 * np.pi * (180 - 400 * t(0.25)) * t(0.25)) * env(n, 0.002, 6)
save(os.path.join(sfx, "splash.wav"), norm(x, 0.7))

# 양동이 촤악
n = int(SR * 0.9)
x = lowpass(noise(0.9), 0.3) * env(n, 0.01, 2.5)
x += 0.4 * highpass(noise(0.9), 0.3) * env(n, 0.03, 3)
save(os.path.join(sfx, "bucket.wav"), norm(x, 0.85))

# 담배 꺼질 때 치익
n = int(SR * 0.7)
x = highpass(noise(0.7), 0.5) * env(n, 0.01, 1.5)
crackle = (rng.random(n) > 0.995).astype(float) * rng.uniform(-1, 1, n)
x += lowpass(crackle, 0.6) * 3
save(os.path.join(sfx, "sizzle.wav"), norm(x, 0.6))

# 코인 띵띵
def tone(freq, sec, shape="sine"):
    ph = 2 * np.pi * freq * t(sec)
    if shape == "square":
        return np.sign(np.sin(ph))
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    return np.sin(ph)

x = np.concatenate([tone(988, 0.07, "square") * 0.5, tone(1319, 0.25, "square") * env(int(SR * 0.25), 0.002, 2) * 0.5])
save(os.path.join(sfx, "coin.wav"), norm(lowpass(x, 0.5), 0.45))

# 소방차 경적 (빠-밤)
x = np.concatenate([tone(440, 0.35, "square") + tone(554, 0.35, "square"), np.zeros(int(SR * 0.05)), tone(392, 0.5, "square") + tone(494, 0.5, "square")])
x = lowpass(x, 0.25) * env(len(x), 0.01, 0.5)
save(os.path.join(sfx, "horn.wav"), norm(x, 0.5))

# 사이렌 루프
tt = t(2.0)
f = 700 + 250 * np.sin(2 * np.pi * 0.5 * tt)
x = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR))
save(os.path.join(sfx, "siren_loop.wav"), norm(lowpass(x, 0.15), 0.35))

# 도시 소음 루프
x = lowpass(noise(8.0), 0.02) * 6 + 0.05 * lowpass(noise(8.0), 0.3)
save(os.path.join(sfx, "city_loop.wav"), norm(loopify(x, 0.5), 0.25))

# BGM: 신나는 칩튠 루프. 140bpm, 16마디.
BPM = 140
beat = 60 / BPM
bars = 16
total = int(SR * beat * 4 * bars)
song = np.zeros(total)


def put(start_beat, x):
    s = int(start_beat * beat * SR)
    e = min(total, s + len(x))
    song[s:e] += x[: e - s]


def note(midi):
    return 440 * 2 ** ((midi - 69) / 12)


# 코드 진행 C - Am - F - G (반복)
chords = [(48, [60, 64, 67]), (45, [57, 60, 64]), (41, [57, 60, 65]), (43, [55, 59, 62])]
melody_a = [72, 74, 76, 79, 76, 74, 72, 74, 72, 69, 72, 76, 74, -1, 72, 71,
            69, 72, 77, 76, 74, 72, 69, 72, 71, 74, 79, 77, 76, 74, 71, 74]
melody_b = [76, 76, 79, 76, 81, 79, 76, 74, 72, 72, 76, 72, 76, 74, 72, 69,
            72, 72, 77, 76, 77, 79, 81, 79, 79, 77, 76, 74, 74, 76, 79, 83]
for bar in range(bars):
    root, tri = chords[bar % 4]
    b0 = bar * 4
    # 베이스: 8분음표 옥타브 통통
    for i in range(8):
        m = root if i % 2 == 0 else root + 12
        x = tone(note(m), beat / 2 * 0.9, "tri") * env(int(SR * beat / 2 * 0.9), 0.005, 1.2) * 0.35
        put(b0 + i * 0.5, x)
    # 화음 엇박 스탭
    for i in [0.5, 1.5, 2.5, 3.5]:
        x = sum(tone(note(m), beat * 0.25, "square") for m in tri) / 3 * env(int(SR * beat * 0.25), 0.003, 2) * 0.12
        put(b0 + i, x)
    # 드럼: 킥, 스네어, 하이햇
    for i in range(4):
        kn = int(SR * 0.15)
        kick = np.sin(2 * np.pi * np.cumsum(np.linspace(150, 40, kn)) / SR) * env(kn, 0.001, 3) * 0.6
        if i in (0, 2):
            put(b0 + i, kick)
        if i in (1, 3):
            sn = int(SR * 0.12)
            put(b0 + i, highpass(noise(0.12), 0.3) * env(sn, 0.001, 3) * 0.35)
        hn = int(SR * 0.04)
        put(b0 + i + 0.5, highpass(noise(0.04), 0.7) * env(hn, 0.001, 3) * 0.15)
    # 멜로디: 8분음표, 앞 8마디 A, 뒤 8마디 B
    if bar >= 4:
        mel = melody_a if bar < 10 else melody_b
        for i in range(8):
            m = mel[(bar % 4) * 8 + i]
            if m < 0:
                continue
            d = beat / 2 * 0.85
            x = tone(note(m), d, "square") * env(int(SR * d), 0.005, 1.5) * 0.13
            x += tone(note(m) * 1.005, d, "square") * env(int(SR * d), 0.005, 1.5) * 0.05
            put(b0 + i * 0.5, x)

song = lowpass(song, 0.6)
save(os.path.join(music, "bgm.wav"), norm(song, 0.7))
print("done")

"""빗소리 루프를 합성해서 assets/sfx/rain_loop.wav 로 저장한다."""
import os
import wave
import numpy as np

SR = 22050
rng = np.random.default_rng(11)
sec = 8.0
n = int(SR * sec)

# 쏴아: 흰 소음을 두 번 부드럽게 (1차 저역통과를 벡터로)
def lowpass(x, a):
    from scipy.signal import lfilter
    return lfilter([a], [1, a - 1], x)

base = rng.uniform(-1, 1, n)
hiss = lowpass(base, 0.35) - lowpass(base, 0.02)
# 후두둑: 짧은 물방울 소리를 흩뿌림
drops = np.zeros(n)
for i in rng.integers(0, n - 400, 900):
    d = rng.uniform(-1, 1, 200) * np.exp(-np.linspace(0, 8, 200)) * rng.uniform(0.2, 1.0)
    drops[i:i + 200] += d
x = hiss * 0.7 + lowpass(drops, 0.5) * 0.5
# 이음새 없이 돌게 끝과 처음을 겹친다
nf = int(SR * 0.5)
head, body = x[:nf].copy(), x[nf:].copy()
w = np.linspace(0, 1, nf)
body[-nf:] = body[-nf:] * (1 - w) + head * w
body = body / (np.max(np.abs(body)) + 1e-9) * 0.5
path = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx", "rain_loop.wav")
with wave.open(path, "wb") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(SR)
    f.writeframes((np.clip(body, -1, 1) * 32000).astype(np.int16).tobytes())
print("saved", path)

"""Poly Haven(CC0) glTF 모델을 assets/ph/<이름>/ 에 받는다. (텍스처 1k)"""
import json
import os
import subprocess
import sys

UA = "Mozilla/5.0 SmokeBusterDev"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ph")
MODELS = sys.argv[1:] or ["tree_small_02", "jacaranda_tree", "street_lamp_01", "fire_hydrant",
                          "painted_wooden_bench", "planter_box_01", "concrete_road_barrier"]


def curl(url, dst=None):
    args = ["curl", "-s", "-A", UA, url]
    if dst:
        args += ["-o", dst]
        subprocess.run(args, check=True)
        return None
    return subprocess.run(args, check=True, capture_output=True).stdout


for m in MODELS:
    info = json.loads(curl("https://api.polyhaven.com/files/" + m))
    g = info["gltf"]["1k"]["gltf"]
    base = os.path.join(OUT, m)
    os.makedirs(base, exist_ok=True)
    curl(g["url"], os.path.join(base, m + ".gltf"))
    for path, inc in g.get("include", {}).items():
        dst = os.path.join(base, path)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        curl(inc["url"], dst)
    print(m, "ok", len(g.get("include", {})) + 1, "files")

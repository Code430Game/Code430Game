"""Copies the dims measured by build_vehicles.py into the vehicle catalogue.

    python3 tools/vehicle_kit/apply_dims.py <repo>

Each built id gets its length, width, height, wheelbase, track, wheel radius, front overhang
and cabin start replaced, and `model` set to its .glb, so the physics body, the wheel nodes
and the far LOD match the model. Other keys (bed and box lengths, roof length) scale with the
length."""

import json
import os
import sys

repo = os.path.abspath(sys.argv[1])
cat_path = os.path.join(repo, "game", "actors", "vehicles", "vehicles.v0.json")
with open(os.path.join(repo, "build", "vehicle_kit", "dims.json")) as f:
    dims = json.load(f)
with open(cat_path) as f:
    cat = json.load(f)
for e in cat["vehicles"]:
    m = dims.get(e["id"])
    if m is None:
        continue
    d = e["dims"]
    scale = m["length_m"] / d["length_m"]
    for k in ("roof_length_m", "bed_length_m", "box_length_m"):
        if k in d:
            d[k] = round(d[k] * scale, 3)
    for k, v in m.items():
        if v is not None:
            d[k] = v
    e["model"] = f"res://assets/vehicles/{e['id']}.glb"
with open(cat_path, "w") as f:
    json.dump(cat, f, indent=1, ensure_ascii=False)
    f.write("\n")
print("vehicle_kit: dims copied for", ", ".join(sorted(k for k in dims)))

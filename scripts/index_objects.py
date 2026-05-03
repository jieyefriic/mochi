#!/usr/bin/env python3
"""Pull all PixelLab objects and classify by (species, color, stage) via prompt."""
import json, os, re, sys, urllib.request

API = "https://api.pixellab.ai/v2"
KEY = os.environ.get("PIXELLAB_API_KEY") or "d4bf0d79-f310-44dd-ac13-b33dee5bfce7"

SPECIES = {
    "slime": "mochima",
    "dragon": "drakkin",
    "kitten": "feliq",
    "bird": "aviorn",
    "wizard": "tidle",
}
STAGE_KEYS = {
    "hatchling": 3,
    "juvenile": 4, "adolescent": 4,
    "adult": 5,
    "ultimate": 6, "elder": 6, "ancient": 6, "legendary": 6,
}
COLOR_KEYS = {
    "red":    ["magma", "volcanic", "lava", " red ", "crimson", "scarlet"],
    "blue":   ["frost", "ice", "glacial", "icy", " blue ", "frozen"],
    "green":  ["toxin", "poison", "acid", "venom", "mossy", " green "],
    "purple": ["arcane", "cosmic", "void", "shadow", "violet", " purple "],
    "gold":   ["solar", "sun", "golden", "radiant", " gold "],
}


def call(path):
    req = urllib.request.Request(
        f"{API}{path}",
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def classify(obj):
    p = (obj.get("prompt") or "").lower()
    species = next((s for k, s in SPECIES.items() if k in p), None)
    stage = next((v for k, v in STAGE_KEYS.items() if k in p), None)
    color_hits = {c: sum(1 for kw in kws if kw in p) for c, kws in COLOR_KEYS.items()}
    color = max(color_hits, key=color_hits.get) if max(color_hits.values()) > 0 else None
    return species, color, stage


def main():
    all_objs, offset, limit = [], 0, 50
    while True:
        r = call(f"/objects?limit={limit}&offset={offset}")
        all_objs.extend(r["objects"])
        if offset + limit >= r["total"]:
            break
        offset += limit
    print(f"# total: {len(all_objs)}", file=sys.stderr)

    idx = {}  # (species, color, stage) -> [obj]
    unmatched = []
    for o in all_objs:
        if o.get("status") != "completed":
            continue
        sp, col, st = classify(o)
        if sp and col and st:
            idx.setdefault((sp, col, st), []).append(o)
        else:
            unmatched.append((o["id"], sp, col, st, (o.get("prompt") or "")[:80]))

    species_list = ["mochima", "drakkin", "feliq", "aviorn", "tidle"]
    color_list = ["red", "blue", "green", "purple", "gold"]
    print("\n# Stage 3 (hatchling) matrix — count of completed objects:")
    print(f"{'species':10}", *[f"{c:>8}" for c in color_list], sep=" ")
    for sp in species_list:
        row = [f"{sp:10}"]
        for col in color_list:
            n = len(idx.get((sp, col, 3), []))
            row.append(f"{n:>8}")
        print(*row, sep=" ")

    print("\n# Stage 3 hatchling — first object_id per (species,color):")
    for sp in species_list:
        for col in color_list:
            objs = idx.get((sp, col, 3), [])
            if objs:
                print(f"{sp:10} {col:7} {objs[0]['id']}  ({len(objs)} candidates)")
            else:
                print(f"{sp:10} {col:7} -- MISSING --")

    print(f"\n# Unmatched: {len(unmatched)}")
    for u in unmatched[:30]:
        print(" ", u)


if __name__ == "__main__":
    main()

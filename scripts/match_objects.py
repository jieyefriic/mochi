#!/usr/bin/env python3
"""Byte-match cloud preview PNGs against local assets to recover object_ids."""
import hashlib, json, os, sys, urllib.request
from pathlib import Path

API = "https://api.pixellab.ai/v2"
KEY = os.environ.get("PIXELLAB_API_KEY") or "d4bf0d79-f310-44dd-ac13-b33dee5bfce7"
ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
CACHE = ROOT / "scripts" / ".obj_cache"
CACHE.mkdir(exist_ok=True)


def call(path):
    req = urllib.request.Request(
        f"{API}{path}",
        headers={"Authorization": f"Bearer {KEY}"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def fetch(url, dst):
    if dst.exists():
        return dst.read_bytes()
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        b = r.read()
    dst.write_bytes(b)
    return b


def sha(b):
    return hashlib.sha256(b).hexdigest()


def main():
    # Pull all objects
    all_objs, offset, limit = [], 0, 50
    while True:
        r = call(f"/objects?limit={limit}&offset={offset}")
        all_objs.extend(r["objects"])
        if offset + limit >= r["total"]:
            break
        offset += limit
    print(f"# total cloud objects: {len(all_objs)}", file=sys.stderr)

    # Download preview for each completed object → sha256
    cloud_hashes = {}  # sha → [obj]
    for i, o in enumerate(all_objs):
        if o.get("status") != "completed" or not o.get("preview_url"):
            continue
        dst = CACHE / f"{o['id']}.png"
        try:
            b = fetch(o["preview_url"], dst)
        except Exception as e:
            print(f"  fetch fail {o['id']}: {e}", file=sys.stderr)
            continue
        h = sha(b)
        cloud_hashes.setdefault(h, []).append(o)
        if i % 20 == 0:
            print(f"  fetched {i}/{len(all_objs)}", file=sys.stderr)

    # Hash all local hatchling base PNGs (stage 3)
    species_local = ["mochilet", "drakling", "felikit", "pip", "sigil"]
    species_canonical = {
        "mochilet": "mochima", "drakling": "drakkin",
        "felikit": "feliq", "pip": "aviorn", "sigil": "tidle",
    }
    colors = ["red", "blue", "green", "purple", "gold"]

    print("\n# Stage 3 hatchling — local PNG → cloud object_id mapping:")
    print(f"{'species':10} {'color':7} {'object_id':38} {'hash':14} {'note'}")
    missing = []
    for sp_local in species_local:
        for col in colors:
            p = ASSETS / col / f"{sp_local}.png"
            if not p.exists():
                print(f"{species_canonical[sp_local]:10} {col:7} {'(local missing)':38}")
                continue
            h = sha(p.read_bytes())
            matches = cloud_hashes.get(h, [])
            if matches:
                ids = ",".join(m["id"] for m in matches)
                print(f"{species_canonical[sp_local]:10} {col:7} {matches[0]['id']:38} {h[:12]}  match")
            else:
                print(f"{species_canonical[sp_local]:10} {col:7} {'-- NO MATCH --':38} {h[:12]}")
                missing.append((sp_local, col, h))

    # Cracking
    print("\n# Stage 2 cracking — local PNG → cloud object_id:")
    for col in colors:
        p = ASSETS / "cracking" / f"{col}.png"
        if not p.exists():
            continue
        h = sha(p.read_bytes())
        matches = cloud_hashes.get(h, [])
        if matches:
            print(f"cracking   {col:7} {matches[0]['id']:38} {h[:12]}  match")
        else:
            print(f"cracking   {col:7} {'-- NO MATCH --':38} {h[:12]}")

    print(f"\n# Hatchling missing matches: {len(missing)}")


if __name__ == "__main__":
    main()

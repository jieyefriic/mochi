#!/usr/bin/env python3
"""Batch-generate 22 missing feed animations via PixelLab REST.

Phase 1: fire all animate-object jobs (in parallel via threads).
Phase 2: poll each background-job to completion, with retries.
Phase 3: download 9 frames per animation via URL template + Mozilla UA.

Output:
  assets/anim_feed/<color>_<species_local>/frame_0..8.png  (20 hatchlings)
  assets/anim_feed_cracking/<color>/frame_0..8.png         (2 cracking)
  + _urls.txt + _job.json sibling per dir
Logs to scripts/.feed_batch.log; final summary to stdout.
"""
import json, os, sys, time, urllib.request, urllib.error, threading, traceback
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

API = "https://api.pixellab.ai/v2"
KEY = os.environ.get("PIXELLAB_API_KEY") or "d4bf0d79-f310-44dd-ac13-b33dee5bfce7"
USER_ID = "ee93d04c-74f6-4f0a-a57a-f7125e8af6eb"

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
LOG = Path(__file__).parent / ".feed_batch.log"

SPECIES_LABEL = {
    "mochima": "slime",
    "drakkin": "dragon",
    "feliq":   "kitten",
    "aviorn":  "bird",
    "tidle":   "wizard",
}
SPECIES_LOCAL = {
    "mochima": "mochilet",
    "drakkin": "drakling",
    "feliq":   "felikit",
    "aviorn":  "pip",
    "tidle":   "sigil",
}
CRACKING_PROMPT = (
    "egg absorbs magical energy: glowing arcane runes pulse on the cracked shell, "
    "mystical sparks flow inward, shell briefly brightens with magical infusion"
)


def log(msg):
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")


def call(method, path, body=None, retries=10):
    url = f"{API}{path}"
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                url,
                data=json.dumps(body).encode() if body else None,
                headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
                method=method,
            )
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            body_txt = e.read().decode()[:300]
            if e.code in (429, 503) and attempt < retries - 1:
                log(f"  retry {path} after {e.code}: {body_txt}")
                time.sleep(min(60, 5 + attempt * 5))
                continue
            raise RuntimeError(f"HTTP {e.code} on {path}: {body_txt}")
        except Exception as e:
            if attempt < retries - 1:
                wait = min(60, 5 + attempt * 7)  # 5,12,19,26,33,40,47,54,60s
                log(f"  retry {path} in {wait}s after {type(e).__name__}: {str(e)[:100]}")
                time.sleep(wait)
                continue
            raise


def fetch_png(url, dst):
    retries = 10
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=60) as r:
                b = r.read()
            if len(b) < 200 or not b.startswith(b"\x89PNG"):
                raise RuntimeError(f"bad PNG {len(b)}b head={b[:8]!r}")
            dst.write_bytes(b)
            return len(b)
        except Exception as e:
            if attempt < retries - 1:
                wait = min(45, 3 + attempt * 5)
                log(f"  retry png {dst.name} in {wait}s after {type(e).__name__}: {str(e)[:80]}")
                time.sleep(wait)
                continue
            raise


STAGE_LOCAL = {
    "mochima": {3: "mochilet", 4: "mochinix",  5: "mochilord",  6: "mochiavatar"},
    "drakkin": {3: "drakling", 4: "drakwhelp", 5: "drakwarden", 6: "drakon"},
    "feliq":   {3: "felikit",  4: "felisprout",5: "felisaber",  6: "felimythos"},
    "aviorn":  {3: "pip",      4: "fledge",    5: "skylord",    6: "talonglyph"},
    "tidle":   {3: "sigil",    4: "acolyte",   5: "archmage",   6: "aeonmage"},
}
STAGE_PROMPT = {
    3: "baby {label} hatchling eating: leans down to chomp",
    4: "young {label} eating: leans down to chomp",
    5: "adult {label} eating: leans down to chomp",
    6: "elder {label} eating: leans down to chomp",
}
STAGE_KEY = {3: "stage3_hatchling", 4: "stage4_juvenile", 5: "stage5_adult", 6: "stage6_ultimate"}
COLORS_ALL = ["red", "blue", "green", "purple", "gold"]


def build_targets(mp):
    targets = []
    # Stage 3: only 4 missing colors (red already done)
    # Stage 4/5/6: all 5 colors
    for stage_n, colors in [(3, ["blue", "green", "purple", "gold"]),
                            (4, COLORS_ALL), (5, COLORS_ALL), (6, COLORS_ALL)]:
        section = mp.get(STAGE_KEY[stage_n], {})
        for sp_canon in ["mochima", "drakkin", "feliq", "aviorn", "tidle"]:
            local = STAGE_LOCAL[sp_canon][stage_n]
            label = SPECIES_LABEL[sp_canon]
            prompt = STAGE_PROMPT[stage_n].format(label=label)
            ids = section.get(sp_canon, {})
            for col in colors:
                obj_id = ids.get(col)
                if not obj_id:
                    continue
                out = ASSETS / "anim_feed" / f"{col}_{local}"
                targets.append({
                    "tag": f"s{stage_n}/{sp_canon}/{col}",
                    "object_id": obj_id,
                    "prompt": prompt,
                    "out_dir": out,
                })
    # Cracking blue/purple (will skip if already done)
    for col in ["blue", "purple"]:
        obj_id = mp.get("stage2_cracking", {}).get(col)
        if not obj_id:
            continue
        out = ASSETS / "anim_feed_cracking" / col
        targets.append({
            "tag": f"cracking/{col}",
            "object_id": obj_id,
            "prompt": CRACKING_PROMPT,
            "out_dir": out,
        })
    return targets


def fire(target):
    """Phase 1: submit animate-object."""
    body = {
        "object_id": target["object_id"],
        "animation_description": target["prompt"],
        "frame_count": 8,
        "direction": "unknown",
    }
    try:
        r = call("POST", "/animate-object", body)
        target["job_id"] = r["background_job_id"]
        target["anim_id"] = r["animation_id"]
        log(f"  ✓ submitted {target['tag']} job={r['background_job_id'][:8]} anim={r['animation_id'][:8]}")
        return True
    except Exception as e:
        target["error"] = f"submit: {e}"
        log(f"  ✗ submit failed {target['tag']}: {e}")
        return False


def poll(target, deadline):
    """Phase 2: poll until completed/failed."""
    if "job_id" not in target:
        return False
    while time.time() < deadline:
        try:
            r = call("GET", f"/background-jobs/{target['job_id']}")
        except Exception as e:
            log(f"  poll {target['tag']} transient: {e}")
            time.sleep(10)
            continue
        st = r.get("status")
        if st == "completed":
            log(f"  ✓ done {target['tag']}")
            return True
        if st == "failed":
            target["error"] = f"job failed: {json.dumps(r)[:300]}"
            log(f"  ✗ failed {target['tag']}: {target['error']}")
            return False
        time.sleep(8)
    target["error"] = "poll timeout"
    log(f"  ✗ timeout {target['tag']}")
    return False


def download(target):
    """Phase 3: curl 9 frames."""
    out: Path = target["out_dir"]
    out.mkdir(parents=True, exist_ok=True)
    base = (
        f"https://backblaze.pixellab.ai/file/pixellab-characters/objects/"
        f"{USER_ID}/{target['object_id']}/animations/{target['anim_id']}/unknown"
    )
    urls = []
    sizes = []
    for i in range(9):  # frame_count=8 → frames 0..8 (9 total)
        url = f"{base}/{i}.png"
        urls.append(url)
        try:
            sz = fetch_png(url, out / f"frame_{i}.png")
            sizes.append(sz)
        except Exception as e:
            target["error"] = f"download frame_{i}: {e}"
            log(f"  ✗ download {target['tag']} frame_{i}: {e}")
            return False
    (out / "_urls.txt").write_text("\n".join(urls) + "\n")
    (out / "_job.json").write_text(json.dumps({
        "object_id": target["object_id"],
        "animation_id": target["anim_id"],
        "background_job_id": target["job_id"],
        "prompt": target["prompt"],
        "frame_sizes": sizes,
    }, indent=2))
    log(f"  ✓ saved {target['tag']} → {out.relative_to(ROOT)} ({sum(sizes)}b total)")
    return True


def process_one(target):
    """Sequential pipeline: skip-if-done → fire → poll → download."""
    out: Path = target["out_dir"]
    if out.exists() and len(list(out.glob("frame_*.png"))) >= 9:
        log(f"  ⊘ skip {target['tag']} (already 9 frames)")
        target["skipped"] = True
        return True
    if not fire(target):
        return False
    deadline = time.time() + 1200  # per-job 20min cap (allows network retry headroom)
    if not poll(target, deadline):
        return False
    if not download(target):
        return False
    return True


def main():
    LOG.write_text("")
    log("== feed_batch start (sequential) ==")
    mp_path = ROOT / "scripts" / "objects_map_full.json"
    if not mp_path.exists():
        mp_path = ROOT / "scripts" / "objects_map.json"
    mp = json.loads(mp_path.read_text())
    targets = build_targets(mp)
    log(f"targets: {len(targets)}")

    saved = []
    failed = []
    skipped = []
    for i, t in enumerate(targets, 1):
        log(f"--- [{i}/{len(targets)}] {t['tag']} ---")
        ok = process_one(t)
        if t.get("skipped"):
            skipped.append(t)
        elif ok:
            saved.append(t)
        else:
            failed.append(t)
            # If we hit a quota wall (every job 429s), bail out
            if "concurrent" in (t.get("error") or "").lower():
                log("  ! concurrent-limit error; backing off 30s before next")
                time.sleep(30)
            elif "max" in (t.get("error") or "").lower() and "usd" in (t.get("error") or "").lower():
                log("  ! credit/quota exhausted; aborting remaining")
                break

    log("== summary ==")
    log(f"OK: {len(saved)} / SKIPPED: {len(skipped)} / FAIL: {len(failed)} / TOTAL: {len(targets)}")
    for t in failed:
        log(f"  FAIL {t['tag']}: {(t.get('error') or '')[:200]}")
    log("== feed_batch done ==")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log("FATAL: " + traceback.format_exc())
        sys.exit(1)

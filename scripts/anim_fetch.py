#!/usr/bin/env python3
"""anim_fetch.py — fire a PixelLab object animation and download the frames.

Wraps `POST /v2/animate-object` + `GET /v2/background-jobs/{id}` (same auth
pattern as ../../encore/scripts/pixellab/pixellab.py). The MCP tool returns
animation_id but discards frame URLs; this goes around it so we can actually
land frame_*.png on disk.

Usage:
    anim_fetch.py <object_id> <out_dir> "<action_description>" [frames]

Example:
    anim_fetch.py 3c06d840-... assets/anim_feed/red_sigil \\
        "baby wizard eating: leans down to chomp" 8
"""

import json, os, sys, time, urllib.request, urllib.error
from pathlib import Path

API = "https://api.pixellab.ai/v2"
KEY = os.environ.get("PIXELLAB_API_KEY") or "d4bf0d79-f310-44dd-ac13-b33dee5bfce7"


def call(method, path, body=None):
    url = f"{API}{path}"
    headers = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=180) as resp:
        return json.loads(resp.read())


def fetch_url(url, out_path):
    # Backblaze 403s the default Python-urllib UA; pretend to be a browser.
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=120) as r:
        out_path.write_bytes(r.read())


def main():
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr); sys.exit(2)
    obj_id, out_dir, desc = sys.argv[1], sys.argv[2], sys.argv[3]
    frames = int(sys.argv[4]) if len(sys.argv) > 4 else 8

    print(f"→ animate-object: {obj_id}", file=sys.stderr)
    body = {
        "object_id": obj_id,
        "animation_description": desc,
        "frame_count": frames,
        "direction": "unknown",
    }
    try:
        r = call("POST", "/animate-object", body)
    except urllib.error.HTTPError as e:
        print(f"animate-object failed: {e.code} {e.read().decode()[:200]}", file=sys.stderr)
        sys.exit(1)

    job_id = r["background_job_id"]
    anim_id = r["animation_id"]
    print(f"  background_job_id={job_id} animation_id={anim_id}", file=sys.stderr)

    # Poll
    print("→ polling job…", file=sys.stderr)
    deadline = time.time() + 300
    while time.time() < deadline:
        time.sleep(8)
        try:
            res = call("GET", f"/background-jobs/{job_id}")
        except urllib.error.HTTPError as e:
            print(f"  poll http {e.code}: {e.read().decode()[:200]}", file=sys.stderr)
            sys.exit(1)
        status = res.get("status", "?")
        progress = res.get("progress_percent")
        print(f"  status={status} progress={progress}", file=sys.stderr)
        if status == "completed":
            break
        if status == "failed":
            print(f"  job failed: {json.dumps(res, indent=2)[:600]}", file=sys.stderr)
            sys.exit(2)
    else:
        print("  timeout", file=sys.stderr); sys.exit(3)

    # Discover frame URLs in the job result.
    urls = []
    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k == "frames" and isinstance(v, list) and v and isinstance(v[0], str):
                    urls.extend(v)
                else:
                    walk(v)
        elif isinstance(o, list):
            for x in o: walk(x)
    walk(res)

    out = Path(out_dir); out.mkdir(parents=True, exist_ok=True)
    # Always dump job result + URLs as a sidecar so a 403 doesn't lose the URLs.
    (out / "_job.json").write_text(json.dumps(res, indent=2))
    if not urls:
        print("  no frame URLs in job result. see _job.json", file=sys.stderr)
        sys.exit(4)
    (out / "_urls.txt").write_text("\n".join(urls) + "\n")
    print(f"  found {len(urls)} frame URLs:", file=sys.stderr)
    for u in urls: print(f"    {u}", file=sys.stderr)

    failed = []
    for i, u in enumerate(urls):
        p = out / f"frame_{i}.png"
        try:
            fetch_url(u, p)
            print(f"  ✓ {p}", file=sys.stderr)
        except Exception as e:
            print(f"  ✗ {p}: {type(e).__name__} {e}", file=sys.stderr)
            failed.append(i)
    if failed:
        print(f"FAILED {len(failed)} frames; URLs in _urls.txt", file=sys.stderr)
        sys.exit(5)
    print(f"done: {len(urls)} frames → {out}", file=sys.stderr)


if __name__ == "__main__":
    main()

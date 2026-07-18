#!/usr/bin/env python3
"""Curate top routes, fetch Mapbox static maps."""
import json, os, time, urllib.request, urllib.parse

OUT = os.path.dirname(os.path.abspath(__file__))
TOKEN = "pk.eyJ1IjoibWluZ3dvbyIsImEiOiJjbW1kdnp2bTUwM3VuMnJuMzRzeGdienVvIn0.CXykIJuDYcPt99tQJQnRhQ"
STYLE = "mapbox/dark-v11"

# curated picks: (key, region substring) — mix of iconic + hidden gems
PICKS = [
    ("BC 99", "Sea-to-Sky"),          # Sea-to-Sky Highway
    ("4", "Pacific Rim"),             # Hwy 4 Alberni
    ("BC 12", "Fraser"),              # Lytton-Lillooet
    ("Cowichan Lake Road", "Malahat"),
    ("Shawnigan Lake Road", "Malahat"),
    ("Callaghan Valley Road", "Sea-to-Sky"),
    ("Pemberton Meadows Road", "Sea-to-Sky"),
    ("WA 11", "Chuckanut"),           # Chuckanut Drive
    ("Fulford-Ganges Road", "Malahat"),
    ("Squamish Valley Road", "Sea-to-Sky"),
]

def encode_polyline(pts, precision=5):
    factor = 10 ** precision
    out = []; plat = plng = 0
    for lat, lng in pts:
        ilat, ilng = round(lat * factor), round(lng * factor)
        for v in (ilat - plat, ilng - plng):
            v = ~(v << 1) if v < 0 else (v << 1)
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1f)) + 63)); v >>= 5
            out.append(chr(v + 63))
        plat, plng = ilat, ilng
    return "".join(out)

def simplify(pts, max_pts):
    if len(pts) <= max_pts: return pts
    step = len(pts) / max_pts
    return [pts[int(i * step)] for i in range(max_pts)] + [pts[-1]]

routes = json.load(open(os.path.join(OUT, "routes_raw.json")))
sel = []
for key, region_sub in PICKS:
    for r in routes:
        if r["key"] == key and region_sub in r["region"]:
            sel.append(r); break

print(f"curated {len(sel)} routes")
for i, r in enumerate(sel):
    ways = sorted(r["ways"], key=len, reverse=True)[:10]
    budget = 300  # total points across overlays
    paths = []
    for w in ways:
        n = max(8, budget // len(ways))
        enc = encode_polyline(simplify(w, n))
        paths.append("path-3.5+ff3b30-0.95(" + urllib.parse.quote(enc, safe="") + ")")
    overlay = ",".join(paths)
    url = f"https://api.mapbox.com/styles/v1/{STYLE}/static/{overlay}/auto/640x400@2x?padding=40&access_token={TOKEN}"
    fn = os.path.join(OUT, f"map_{i+1:02d}.png")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "revv-guide/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            open(fn, "wb").write(resp.read())
        print(f"[OK] {i+1:2d} {r['name']} -> {os.path.getsize(fn)//1024}KB (url {len(url)} chars)")
    except Exception as ex:
        print(f"[FAIL] {i+1} {r['name']}: {ex}")
    time.sleep(1)

meta = [{k: r[k] for k in ("region","key","name","ref","km","turn_per_km","curves","tight","score")} for r in sel]
json.dump(meta, open(os.path.join(OUT, "routes_meta.json"), "w"), indent=1)

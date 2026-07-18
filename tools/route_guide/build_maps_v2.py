#!/usr/bin/env python3
"""Generate Mapbox static maps from routes_meta_v2.json geometries."""
import json, os, time, urllib.request, urllib.parse

OUT = os.path.dirname(os.path.abspath(__file__))
TOKEN = "pk.eyJ1IjoibWluZ3dvbyIsImEiOiJjbW1kdnp2bTUwM3VuMnJuMzRzeGdienVvIn0.CXykIJuDYcPt99tQJQnRhQ"
STYLE = "mapbox/dark-v11"

def encode_polyline(pts, precision=5):
    """Encode lat,lon points to polyline format."""
    factor = 10 ** precision
    out = []
    plat = plng = 0
    for lat, lng in pts:
        ilat, ilng = round(lat * factor), round(lng * factor)
        for v in (ilat - plat, ilng - plng):
            v = ~(v << 1) if v < 0 else (v << 1)
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1f)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        plat, plng = ilat, ilng
    return "".join(out)

def simplify(pts, max_pts):
    """Simplify point list to max_pts."""
    if len(pts) <= max_pts:
        return pts
    step = len(pts) / max_pts
    return [pts[int(i * step)] for i in range(max_pts)] + [pts[-1]]

routes_meta = json.load(open(os.path.join(OUT, "routes_meta_v2.json")))

print("Building maps...")
success = 0
failed = 0

for _i, route in enumerate(routes_meta, 1):
    idx = _i
    name = route.get("name") or route["key"]
    geometry = route.get("geometry", [])

    if not geometry:
        print(f"[{idx:2d}] SKIP {name}: no geometry")
        failed += 1
        continue

    # Simplify to ~180 points for URL length constraint
    simplified = simplify(geometry, 180)

    # Encode as polyline
    enc = encode_polyline(simplified)

    # Build overlay: path (continuous red line) + start marker (green) + end marker (red)
    start = geometry[0] if geometry else None
    end = geometry[-1] if geometry else None

    overlays = []

    # Main path: path-4.5+ff3b30-0.95 (4.5px, red #ff3b30, 95% opacity)
    path_overlay = "path-4.5+ff3b30-0.95(" + urllib.parse.quote(enc, safe="") + ")"
    overlays.append(path_overlay)

    # Start marker (green circle): pin-s-a+34c759
    if start:
        start_marker = f"pin-s-a+34c759({start[1]},{start[0]})"
        overlays.append(start_marker)

    # End marker (red circle): pin-s-b+ff3b30
    if end:
        end_marker = f"pin-s-b+ff3b30({end[1]},{end[0]})"
        overlays.append(end_marker)

    overlay_str = ",".join(overlays)

    # Build URL
    url = f"https://api.mapbox.com/styles/v1/{STYLE}/static/{overlay_str}/auto/640x400@2x?padding=60&access_token={TOKEN}"

    # Check URL length
    if len(url) > 8000:
        print(f"[{idx:2d}] URL too long ({len(url)} chars), reducing points...")
        simplified = simplify(geometry, 120)
        enc = encode_polyline(simplified)
        path_overlay = "path-4.5+ff3b30-0.95(" + urllib.parse.quote(enc, safe="") + ")"
        overlay_str = ",".join([path_overlay] + overlays[1:])
        url = f"https://api.mapbox.com/styles/v1/{STYLE}/static/{overlay_str}/auto/640x400@2x?padding=60&access_token={TOKEN}"

    fn = os.path.join(OUT, f"map_{idx:02d}.png")

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "revv-guide/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read()
            with open(fn, "wb") as f:
                f.write(data)
        size_kb = len(data) // 1024
        print(f"[{idx:2d}] OK {name:<30} {size_kb:5d}KB (url {len(url)} chars)")
        success += 1
    except Exception as ex:
        print(f"[{idx:2d}] FAIL {name}: {ex}")
        failed += 1

    time.sleep(1)

print(f"\n=== SUMMARY ===")
print(f"Generated: {success}/10")
print(f"Failed: {failed}/10")

# Verify PNG sizes
print(f"\n=== PNG File Sizes ===")
for idx in range(1, 11):
    fn = os.path.join(OUT, f"map_{idx:02d}.png")
    if os.path.exists(fn):
        size = os.path.getsize(fn)
        size_kb = size // 1024
        status = "OK" if size >= 30000 else "SMALL"
        print(f"map_{idx:02d}.png: {size_kb:5d}KB {status}")

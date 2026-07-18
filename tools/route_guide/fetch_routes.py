#!/usr/bin/env python3
"""Fetch winding roads in BC/PNW via Overpass, score by bearing rate (REVV-style)."""
import json, math, time, urllib.request, urllib.parse, sys, os

OUT = os.path.dirname(os.path.abspath(__file__))
OVERPASS = "https://overpass-api.de/api/interpreter"

REGIONS = [
    ("Sea-to-Sky (Squamish-Whistler)",   (49.70, -123.35, 50.40, -122.70)),
    ("Duffey Lake Rd (Pemberton-Lillooet)", (50.30, -122.65, 50.70, -121.90)),
    ("Fraser Canyon (Hope-Lytton)",      (49.35, -121.75, 50.25, -121.25)),
    ("Hwy 4 Pacific Rim (Port Alberni-Tofino)", (49.18, -125.90, 49.40, -124.70)),
    ("Malahat & Cowichan (Vancouver Island)", (48.53, -123.80, 48.90, -123.40)),
    ("Chuckanut Drive (WA, USA)",        (48.55, -122.52, 48.75, -122.38)),
    ("Mt Baker Hwy (WA, USA)",           (48.80, -122.35, 49.00, -121.60)),
]

def bearing(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    y = math.sin(lo2 - lo1) * math.cos(la2)
    x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(lo2 - lo1)
    return (math.degrees(math.atan2(y, x)) + 360) % 360

def hav_km(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2-la1)/2)**2 + math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2
    return 2 * 6371 * math.asin(math.sqrt(h))

def analyze(pts):
    total_km = 0.0; turn_sum = 0.0; curves = 0; tight = 0
    prev_b = None
    for i in range(1, len(pts)):
        total_km += hav_km(pts[i-1], pts[i])
        b = bearing(pts[i-1], pts[i])
        if prev_b is not None:
            d = abs(b - prev_b)
            if d > 180: d = 360 - d
            if d > 5: turn_sum += d
            if d > 25: curves += 1
            if d > 55: tight += 1
        prev_b = b
    return total_km, turn_sum, curves, tight

def fetch(region_name, bbox):
    s, w, n, e = bbox
    q = f"""[out:json][timeout:90];
way[highway~"^(trunk|primary|secondary|tertiary)$"][surface!~"gravel|dirt|unpaved"]({s},{w},{n},{e});
out geom tags;"""
    req = urllib.request.Request(OVERPASS, data=urllib.parse.urlencode({"data": q}).encode(),
                                 headers={"User-Agent": "revv-guide-builder/1.0"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())

routes = []
for name, bbox in REGIONS:
    try:
        data = fetch(name, bbox)
    except Exception as ex:
        print(f"[FAIL] {name}: {ex}", file=sys.stderr); time.sleep(5); continue
    groups = {}
    for el in data.get("elements", []):
        tags = el.get("tags", {})
        key = tags.get("ref") or tags.get("name")
        if not key or "geometry" not in el: continue
        groups.setdefault(key, {"name": tags.get("name") or key, "ref": tags.get("ref", ""), "ways": []})
        groups[key]["ways"].append([(p["lat"], p["lon"]) for p in el["geometry"]])
    for key, g in groups.items():
        km = t = c = ti = 0
        for w in g["ways"]:
            a = analyze(w); km += a[0]; t += a[1]; c += a[2]; ti += a[3]
        if km < 8: continue  # too short
        density = t / km  # deg per km
        score = density * math.sqrt(min(km, 80))
        routes.append({"region": name, "key": key, "name": g["name"], "ref": g["ref"],
                       "km": round(km, 1), "turn_per_km": round(density, 1),
                       "curves": c, "tight": ti, "score": round(score, 1),
                       "ways": g["ways"]})
    print(f"[OK] {name}: {len(data.get('elements', []))} ways, {len(groups)} named groups")
    time.sleep(3)

routes.sort(key=lambda r: -r["score"])
with open(os.path.join(OUT, "routes_raw.json"), "w") as f:
    json.dump(routes, f)
print("\n=== TOP 20 ===")
for r in routes[:20]:
    print(f"{r['score']:8.1f}  {r['km']:6.1f}km  {r['turn_per_km']:5.1f}°/km  curves={r['curves']:4d} tight={r['tight']:3d}  [{r['region']}] {r['name']} ({r['ref']})")

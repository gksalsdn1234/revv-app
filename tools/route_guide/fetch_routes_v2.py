#!/usr/bin/env python3
"""Fetch full route geometry/distance/duration via Mapbox Directions, score winding density.

v1 (fetch_routes.py) summed name-matched OSM way fragments inside a bbox, which
undercounted distances and produced fragmented maps. v2 routes start->end (with
via points to pin the intended road) so km/time/geometry describe the real drive.
"""
import json, math, os, sys, time, urllib.parse, urllib.request

OUT = os.path.dirname(os.path.abspath(__file__))
TOKEN = "pk.eyJ1IjoibWluZ3dvbyIsImEiOiJjbW1kdnp2bTUwM3VuMnJuMzRzeGdienVvIn0.CXykIJuDYcPt99tQJQnRhQ"

# (key, waypoints [(lat,lon) or "geocode:query"], km band, required road-name substrings (any))
ROUTES = [
    ("BC 99", [(49.3771, -123.2717), (50.1163, -122.9574), (50.3192, -122.7948)],
     (115, 145), ["Sea to Sky", "Sea-to-Sky", "99"]),
    ("4", [(49.2337, -124.8055), (49.1530, -125.9066)],
     (95, 135), ["Pacific Rim", "Alberni", "4"]),
    ("BC 12", [(50.2337, -121.5820), (50.6865, -121.9363)],
     (55, 75), ["12", "Lillooet"]),
    ("Cowichan Lake Road", [(48.7823, -123.7150), "geocode:Cowichan Lake Road, Duncan, BC", (48.8180, -124.0000), (48.8253, -124.0532)],
     (25, 40), ["Cowichan Lake"]),
    ("Shawnigan Lake Road", [(48.6520, -123.5560), "geocode:West Shawnigan Lake Road, BC", (48.6197, -123.6288), (48.6486, -123.6259)],
     (12, 30), ["Shawnigan"]),
    ("Callaghan Valley Road", [(50.0619, -123.1081), (50.1363, -123.1273)],
     (7, 16), ["Callaghan"]),
    ("Pemberton Meadows Road", [(50.3192, -122.7948), (50.4473, -122.9210)],
     (14, 30), ["Pemberton Meadows"]),
    ("WA 11", [(48.7196, -122.5030), "geocode:Chuckanut Drive, Bow, Washington", (48.4757, -122.3255)],
     (25, 40), ["Chuckanut"]),
    ("Fulford-Ganges Road", [(48.7683, -123.4497), (48.8545, -123.4966)],
     (9, 18), ["Fulford", "Ganges"]),
    ("Squamish Valley Road", [(49.7845, -123.1620), (49.9286, -123.2892)],
     (15, 35), ["Squamish Valley"]),
]

def geocode(q):
    url = ("https://api.mapbox.com/geocoding/v5/mapbox.places/"
           + urllib.parse.quote(q) + f".json?limit=1&access_token={TOKEN}")
    req = urllib.request.Request(url, headers={"User-Agent": "revv-guide/2.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        feats = json.loads(r.read()).get("features", [])
    if not feats:
        raise RuntimeError(f"geocode empty: {q}")
    lon, lat = feats[0]["center"]
    print(f"    geocode '{q}' -> {lat:.4f},{lon:.4f} ({feats[0].get('place_name','')[:60]})")
    return (lat, lon)

def directions(waypts):
    coords = ";".join(f"{lon},{lat}" for lat, lon in waypts)
    url = (f"https://api.mapbox.com/directions/v5/mapbox/driving/{urllib.parse.quote(coords, safe=';,')}"
           f"?geometries=geojson&overview=full&steps=true&access_token={TOKEN}")
    req = urllib.request.Request(url, headers={"User-Agent": "revv-guide/2.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = json.loads(r.read())
    if data.get("code") != "Ok" or not data.get("routes"):
        raise RuntimeError(f"directions failed: {data.get('code')} {data.get('message','')}")
    rt = data["routes"][0]
    geom = [(lat, lon) for lon, lat in rt["geometry"]["coordinates"]]
    names = set()
    for leg in rt["legs"]:
        for st in leg["steps"]:
            n = st.get("name") or ""
            ref = st.get("ref") or ""
            if n: names.add(n)
            if ref: names.add(ref)
    return geom, rt["distance"] / 1000.0, rt["duration"] / 60.0, names

def hav_km(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371 * math.asin(math.sqrt(h))

def bearing(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    y = math.sin(lo2 - lo1) * math.cos(la2)
    x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(lo2 - lo1)
    return (math.degrees(math.atan2(y, x)) + 360) % 360

def resample(pts, step_km=0.15):
    """Uniform point spacing so winding density is comparable across geometry sources."""
    out = [pts[0]]
    dist_since = 0.0
    for i in range(1, len(pts)):
        a, b = pts[i - 1], pts[i]
        seg = hav_km(a, b)
        if seg <= 1e-9:
            continue
        pos = 0.0
        while dist_since + (seg - pos) >= step_km:
            need = step_km - dist_since
            pos += need
            f = pos / seg
            out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
            dist_since = 0.0
        dist_since += seg - pos
    if out[-1] != pts[-1]:
        out.append(pts[-1])
    return out

def winding(pts):
    rs = resample(pts)
    km = sum(hav_km(rs[i - 1], rs[i]) for i in range(1, len(rs)))
    turn = 0.0
    prev = None
    for i in range(1, len(rs)):
        b = bearing(rs[i - 1], rs[i])
        if prev is not None:
            d = abs(b - prev)
            if d > 180:
                d = 360 - d
            turn += d
        prev = b
    return km, turn / km if km else 0.0

results, failures = [], []
for key, waypts, (lo, hi), namereq in ROUTES:
    print(f"[{key}]")
    try:
        wp = [geocode(w[8:]) if isinstance(w, str) else w for w in waypts]
        geom, km, dur_min, names = directions(wp)
        pathlen, density = winding(geom)
        ok_km = lo <= km <= hi
        ok_path = abs(pathlen - km) / km < 0.08
        ok_name = any(any(req.lower() in n.lower() for n in names) for req in namereq)
        status = "OK" if (ok_km and ok_path and ok_name) else "CHECK-FAILED"
        if status != "OK":
            failures.append((key, f"km_band={ok_km}({km:.1f} not in {lo}-{hi})"
                             f" path={ok_path}({pathlen:.1f}) name={ok_name}({sorted(names)[:6]})"))
        score = density * math.sqrt(min(km, 80))
        print(f"    {status}: {km:.1f} km, {dur_min:.0f} min, {density:.1f} deg/km, roads={sorted(names)[:4]}")
        results.append({"key": key, "km": round(km, 1), "drive_min": int(round(dur_min)),
                        "turn_per_km": round(density, 1), "score": round(score, 1),
                        "start": [wp[0][0], wp[0][1]], "end": [wp[-1][0], wp[-1][1]],
                        "road_names": sorted(names), "geometry": [[round(a, 5), round(b, 5)] for a, b in geom]})
    except Exception as ex:
        failures.append((key, str(ex)))
        print(f"    FAILED: {ex}")
    time.sleep(1)

json.dump(results, open(os.path.join(OUT, "routes_meta_v2.json"), "w"))
print(f"\nwrote routes_meta_v2.json with {len(results)} routes")
if failures:
    print("\n!! FAILURES / CHECK-FAILED:")
    for k, msg in failures:
        print(f"  {k}: {msg}")
    sys.exit(1)

#!/usr/bin/env python3
"""Assemble sellable HTML guide -> PDF via headless Chrome."""
import json, os, subprocess

OUT = os.path.dirname(os.path.abspath(__file__))
meta = json.load(open(os.path.join(OUT, "routes_meta.json")))

DISPLAY = {
    "BC 99": ("Sea-to-Sky Highway", "BC-99 · Vancouver → Whistler → Pemberton",
        "The classic. Ocean cliffs out of Horseshoe Bay, granite walls past Squamish, alpine sweepers into Whistler. Rebuilt for the 2010 Olympics, so the pavement is superb. Go at sunrise on a weekday — by 10am it belongs to the tourists.",
        "Start: Horseshoe Bay ferry terminal · Fuel: Squamish midpoint · Best light: golden hour over Howe Sound"),
    "4": ("Highway 4 — Pacific Rim", "BC-4 · Port Alberni → Tofino",
        "77 km of old-growth rainforest, lake shores, and the tight technical section over Sutton Pass. One of the most engaging full-length drives on Vancouver Island — narrow, shaded, and relentlessly curvy. Watch for logging trucks on weekdays.",
        "Start: Port Alberni · No fuel until Ucluelet junction — fill up first · Kennedy Lake pull-outs for photos"),
    "BC 12": ("Lytton–Lillooet Road", "BC-12 · Fraser Canyon benchlands",
        "The empty one. BC-12 rides the benches above the Fraser River between two small towns most people skip. Big canyon views, almost zero traffic, and a rhythm of medium-speed corners that never quite ends. Semi-arid desert light — best in late afternoon.",
        "Start: Lytton · Check conditions after heavy rain (slide-prone) · Cell coverage is patchy — download maps offline"),
    "Cowichan Lake Road": ("Cowichan Lake Road", "Duncan → Lake Cowichan",
        "A local commuter road that happens to be a fantastic drive: farmland, forest tunnels, and a steady stream of corners along the Cowichan River valley. Low traffic outside rush hours. Pairs perfectly with Shawnigan Lake Road for a full-day Island loop.",
        "Start: Duncan (Trans-Canada exit) · Coffee: Lake Cowichan townsite · Combine with Route 5 for a loop"),
    "Shawnigan Lake Road": ("Shawnigan Lake Road", "Mill Bay → Shawnigan Lake loop",
        "160°/km winding density — the second-highest score in this guide. Tight, tree-lined, constantly turning lakeside tarmac. This is a slow-speed technical drive: narrow lanes, cyclists on weekends, and corners that reward precision, not pace.",
        "Start: Mill Bay ferry or Trans-Canada · Weekday mornings are quietest · Full lake loop adds 10 km of the same"),
    "Callaghan Valley Road": ("Callaghan Valley Road", "BC-99 junction → Whistler Olympic Park",
        "A dead-end alpine climb built for the 2010 Games: wide, smooth, and empty, gaining elevation through 12.7 km of sweeping switchbacks. Because it ends at the Olympic Park, you get to drive it both ways. Highest winding density in this guide.",
        "Start: 10 min south of Whistler on BC-99 · Out-and-back — 25 km total · Snow closes it in winter"),
    "Pemberton Meadows Road": ("Pemberton Meadows Road", "Pemberton → Upper Lillooet valley",
        "Flat valley floor, 2,000-metre walls on both sides. The corners are gentle but the setting is absurd — farmland framed by glaciers. The road quietly dead-ends up the valley, so traffic is nearly zero. A decompression drive after Sea-to-Sky.",
        "Start: Pemberton village · No services past town · Best after driving BC-99 north"),
    "WA 11": ("Chuckanut Drive", "WA-11 · Bellingham → Burlington (USA)",
        "The Pacific Northwest's original scenic drive — carved into the cliffs over Samish Bay in 1896. Cross-border bonus route: 30 km of ocean-edge corners, oyster shacks, and viewpoints. Combine with a Bellingham coffee run for the perfect half-day.",
        "Start: Fairhaven district, Bellingham · US border: bring passport · Oyster stop: Taylor Shellfish Farms"),
    "Fulford-Ganges Road": ("Fulford–Ganges Road", "Salt Spring Island · ferry required",
        "The hidden gem that algorithms miss and locals love. Take the ferry from Swartz Bay, roll off at Fulford Harbour, and carve 14 km of hilly, winding island road to Ganges village. The ferry ride makes it an event; the Saturday market makes it a day.",
        "Ferry: Swartz Bay → Fulford (35 min) · Saturday market in Ganges · Island speed limits are low — cruise it"),
    "Squamish Valley Road": ("Squamish Valley Road", "Squamish → Upper Squamish valley",
        "Turn off the tourist highway and follow the Squamish River into the mountains. 22 km of river-valley corners that get wilder and emptier the further you go. Pavement ends eventually — turn around there. Eagles in winter, alpenglow in summer.",
        "Start: BC-99 north of Squamish · Pavement ends ~22 km in · Winter: bald eagle viewing area"),
}

def difficulty(d):
    if d < 60: return "SCENIC", "#4dd0a1"
    if d < 90: return "SPIRITED", "#ffd166"
    if d < 130: return "WINDING", "#ff9f43"
    return "TECHNICAL", "#ff3b30"

pages = []
for i, r in enumerate(meta):
    disp = DISPLAY[r["key"]]
    name, sub, desc, tips = disp
    label, color = difficulty(r["turn_per_km"])
    hours = r["km"] / 55
    tmin = int(round(hours * 60))
    time_s = f"{tmin//60}h {tmin%60:02d}m" if tmin >= 60 else f"{tmin} min"
    tip_items = "".join(f"<li>{t.strip()}</li>" for t in tips.split("·"))
    pages.append(f"""
<section class="page route">
  <div class="rhead">
    <div class="rnum">{i+1:02d}</div>
    <div>
      <h2>{name}</h2>
      <div class="rsub">{sub}</div>
    </div>
    <div class="badge" style="background:{color}1a;color:{color};border:1px solid {color}55">{label}</div>
  </div>
  <img class="map" src="map_{i+1:02d}.png" alt="">
  <div class="stats">
    <div class="stat"><div class="v">{r['km']:.0f} km</div><div class="k">LENGTH</div></div>
    <div class="stat"><div class="v">{r['turn_per_km']:.0f}°/km</div><div class="k">WINDING DENSITY</div></div>
    <div class="stat"><div class="v">{time_s}</div><div class="k">DRIVE TIME</div></div>
    <div class="stat"><div class="v">{r['score']:.0f}</div><div class="k">REVV SCORE</div></div>
  </div>
  <p class="desc">{desc}</p>
  <ul class="tips">{tip_items}</ul>
  <div class="pfoot"><span>REVV · Hidden Winding Roads Vol. 1</span><span>{i+1:02d} / 10</span></div>
</section>""")

html = f"""<!doctype html><html><head><meta charset="utf-8"><style>
@page {{ size: 8.5in 11in; margin: 0; }}
* {{ margin:0; padding:0; box-sizing:border-box; }}
body {{ font-family: 'Helvetica Neue', Arial, sans-serif; background:#0d0f12; color:#e8eaed; -webkit-print-color-adjust:exact; }}
.page {{ width:8.5in; height:11in; padding:0.7in; page-break-after:always; position:relative; background:#0d0f12; display:flex; flex-direction:column; }}
.cover {{ justify-content:space-between; background:linear-gradient(160deg,#0d0f12 40%,#1a0e0e 100%); }}
.brand {{ color:#ff3b30; font-weight:800; letter-spacing:0.35em; font-size:15px; }}
.cover h1 {{ font-size:54px; line-height:1.08; font-weight:800; margin-top:22px; letter-spacing:-0.02em; }}
.cover .accent {{ color:#ff3b30; }}
.cover .tag {{ color:#9aa0a6; font-size:16px; margin-top:16px; line-height:1.6; max-width:5.6in; }}
.cover .meta {{ color:#5f6368; font-size:12px; letter-spacing:0.18em; }}
.coverstats {{ display:flex; gap:14px; margin-top:34px; }}
.coverstats .stat {{ border:1px solid #2a2e35; border-radius:12px; padding:14px 20px; }}
h2 {{ font-size:26px; font-weight:800; letter-spacing:-0.01em; }}
.rhead {{ display:flex; align-items:center; gap:16px; margin-bottom:14px; }}
.rnum {{ font-size:38px; font-weight:800; color:#2a2e35; }}
.rsub {{ color:#9aa0a6; font-size:13px; margin-top:3px; }}
.badge {{ margin-left:auto; font-size:11px; font-weight:700; letter-spacing:0.12em; padding:6px 12px; border-radius:999px; }}
.map {{ width:100%; border-radius:14px; border:1px solid #23262c; }}
.stats {{ display:flex; gap:12px; margin:16px 0; }}
.stat {{ flex:1; background:#15181d; border:1px solid #23262c; border-radius:12px; padding:12px 14px; }}
.stat .v {{ font-size:20px; font-weight:800; }}
.stat .k {{ font-size:9px; letter-spacing:0.16em; color:#7a8087; margin-top:4px; }}
.desc {{ font-size:14px; line-height:1.65; color:#c8ccd2; }}
.tips {{ margin-top:12px; list-style:none; }}
.tips li {{ font-size:12px; color:#9aa0a6; padding:6px 0 6px 18px; position:relative; border-top:1px solid #1b1e24; }}
.tips li:before {{ content:"→"; position:absolute; left:0; color:#ff3b30; }}
.pfoot {{ margin-top:auto; display:flex; justify-content:space-between; font-size:10px; letter-spacing:0.14em; color:#5f6368; }}
.intro p {{ font-size:14px; line-height:1.75; color:#c8ccd2; margin-bottom:14px; max-width:6.4in; }}
.intro h2 {{ margin-bottom:18px; }}
.method {{ background:#15181d; border:1px solid #23262c; border-radius:14px; padding:20px; margin:18px 0; }}
.method code {{ color:#ff6b61; font-family:Menlo,monospace; font-size:12px; }}
.safety {{ border-left:3px solid #ffd166; padding:12px 16px; background:#16150f; border-radius:0 10px 10px 0; font-size:12px; color:#b8ab7a; line-height:1.6; }}
.cta {{ justify-content:center; text-align:center; background:linear-gradient(200deg,#0d0f12 40%,#1a0e0e 100%); }}
.cta h2 {{ font-size:36px; margin-bottom:14px; }}
.cta p {{ color:#9aa0a6; font-size:15px; line-height:1.7; max-width:5.4in; margin:0 auto 10px; }}
.cta .app {{ color:#ff3b30; font-weight:800; letter-spacing:0.25em; font-size:20px; margin-top:26px; }}
</style></head><body>

<section class="page cover">
  <div>
    <div class="brand">R E V V</div>
    <h1>Hidden Winding Roads<br>of the <span class="accent">Pacific Northwest</span></h1>
    <div class="tag">10 driving routes scored by algorithm, not opinion.<br>British Columbia &amp; Washington · Vol. 1</div>
    <div class="coverstats">
      <div class="stat"><div class="v">385 km</div><div class="k">TOTAL ROUTE LENGTH</div></div>
      <div class="stat"><div class="v">1,579</div><div class="k">WAYS ANALYZED</div></div>
      <div class="stat"><div class="v">10</div><div class="k">ROUTES THAT MADE THE CUT</div></div>
    </div>
  </div>
  <div class="meta">REVV GUIDES · 2026 EDITION · VOL. 1</div>
</section>

<section class="page intro">
  <h2>How these roads were found</h2>
  <p>Every route in this guide was discovered by an algorithm, not a listicle. We pulled every paved highway, primary and secondary road in each region from OpenStreetMap — 1,579 road segments — and scored each one on how much it actually turns.</p>
  <div class="method">
    <code>winding density = Σ|Δbearing| / distance&nbsp;&nbsp;→&nbsp;&nbsp;score = density × √km</code>
  </div>
  <p>The metric is <b>winding density</b>: degrees of direction change per kilometre. A straight freeway scores near zero. The roads in this guide score 50–180°/km — which you feel as a corner every few hundred metres, for kilometres on end. The final score rewards roads that stay interesting over real distance, not just one good hairpin.</p>
  <p>Then we curated. Algorithms don't know about ferry rides, oyster shacks, or which roads have logging-truck traffic — so every entry was reviewed and annotated by a human who drives these regions.</p>
  <div class="safety">Every road here is a public road. Posted limits, oncoming traffic, cyclists and wildlife are all part of the deal — these routes are rewarding at completely legal speeds. Drive smooth, arrive happy.</div>
  <div class="pfoot" style="margin-top:auto"><span>REVV · Hidden Winding Roads Vol. 1</span><span>METHOD</span></div>
</section>
{''.join(pages)}
<section class="page cta">
  <div>
    <h2>This guide is a snapshot.<br>The app is <span style="color:#ff3b30">live</span>.</h2>
    <p>REVV scores every road around you in real time — anywhere in North America. Find your own hidden routes, track your drives, and build your personal driving log.</p>
    <p><b style="color:#e8eaed">Want routes picked for you?</b><br>Custom Route Drop: tell us your location and how much time you have — we'll send you your 3 best local roads, scored and annotated.</p>
    <div class="app">GET REVV</div>
  </div>
</section>
</body></html>"""

fn = os.path.join(OUT, "guide.html")
open(fn, "w").write(html)
chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
pdf = os.path.join(OUT, "REVV_Hidden_Winding_Roads_Vol1.pdf")
subprocess.run([chrome, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                f"--print-to-pdf={pdf}", f"file://{fn}"], check=True, capture_output=True)
print("PDF:", pdf, os.path.getsize(pdf)//1024, "KB")

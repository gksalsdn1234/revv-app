# REVV English App Store Screenshot Set

This directory contains the English-only marketing screenshot set for the
current iOS candidate, `1.38.0+59`.

## Upload set

Upload the six files in `iphone_6_9/` in numeric order. Each file is a
1320x2868 opaque RGB PNG. The verified app UI comes from
`store_assets/screenshots/final/iphone_6_9/` and is not generated or rewritten.

1. **Find roads worth driving** — Explore curvy routes across Canada.
2. **Know the road before you go** — Preview the shape, distance, and drive time.
3. **Every curve, before the first turn** — Compare route shape, timing, and curve mix.
4. **The next curve, right on time** — Focused guidance built for the drive.
5. **Every drive becomes part of the story** — Track distance, rhythm, and season progress.
6. **Your drives. Your controls.** — Choose what stays local, synced, or deleted.

`contact_sheet.png` is a review artifact and must not be uploaded to App Store
Connect. `manifest.json` records each source capture and output SHA-256.

## Reproduction

Run:

```sh
python3 tools/app_store_assets/render_app_store_en.py
```

The abstract background in `source/revv_editorial_background.png` was created
with OpenAI's built-in image generation tool. Exact UI, English copy, typography,
dimensions, and export are composited deterministically by the renderer.

Final image-generation prompt:

> Create one premium abstract vertical background plate for an iOS App Store
> screenshot campaign for REVV, a curvy-road driving companion. Editorial
> automotive art direction, restrained race-paddock energy, deep near-black
> asphalt, warm ivory paper, and vivid signal red. Include subtle flowing road
> contours and very faint topographic linework, with elegant directional motion
> and generous clean negative space. Sophisticated, minimal, high contrast,
> crisp, flat-to-textured hybrid, no gradients that look cheap. No car, no
> motorcycle, no people, no phone, no device frame, no app UI, no text, no
> letters, no numbers, no logo, no icon, no watermark. Portrait composition
> matching roughly 1320 by 2868, designed to sit behind a real phone screenshot
> and typography. Marketing asset background only.

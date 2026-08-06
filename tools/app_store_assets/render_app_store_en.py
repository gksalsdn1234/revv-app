#!/usr/bin/env python3
"""Render the English REVV App Store screenshot set from verified captures."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "store_assets/screenshots/final/iphone_6_9"
MARKETING_ROOT = ROOT / "store_assets/screenshots/marketing/en"
OUTPUT_DIR = MARKETING_ROOT / "iphone_6_9"
BACKGROUND_PATH = MARKETING_ROOT / "source/revv_editorial_background.png"
CONTACT_SHEET_PATH = MARKETING_ROOT / "contact_sheet.png"
MANIFEST_PATH = MARKETING_ROOT / "manifest.json"

CANVAS = (1320, 2868)
FONT_PATH = "/System/Library/Fonts/SFNS.ttf"

INK = (15, 17, 17)
IVORY = (242, 235, 220)
WHITE = (255, 255, 255)
RED = (234, 32, 29)

SLIDES = [
    {
        "source": "01_route_map.png",
        "output": "01_find_roads_worth_driving.png",
        "headline": "Find roads\nworth driving",
        "subhead": "Explore curvy routes across Canada.",
        "theme": "dark",
    },
    {
        "source": "02_route_preview.png",
        "output": "02_know_the_road_before_you_go.png",
        "headline": "Know the road\nbefore you go",
        "subhead": "Preview the shape, distance, and drive time.",
        "theme": "dark",
    },
    {
        "source": "03_route_detail.png",
        "output": "03_every_curve_before_the_first_turn.png",
        "headline": "Every curve,\nbefore the first turn",
        "subhead": "Compare route shape, timing, and curve mix.",
        "theme": "light",
    },
    {
        "source": "04_drive.png",
        "output": "04_the_next_curve_right_on_time.png",
        "headline": "The next curve,\nright on time",
        "subhead": "Focused guidance built for the drive.",
        "theme": "red",
    },
    {
        "source": "05_history.png",
        "output": "05_every_drive_becomes_part_of_the_story.png",
        "headline": "Every drive becomes\npart of the story",
        "subhead": "Track distance, rhythm, and season progress.",
        "theme": "light",
    },
    {
        "source": "06_settings.png",
        "output": "06_your_drives_your_controls.png",
        "headline": "Your drives.\nYour controls.",
        "subhead": "Choose what stays local, synced, or deleted.",
        "theme": "dark",
    },
]


def font(size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    selected = ImageFont.truetype(FONT_PATH, size)
    selected.set_variation_by_name(weight)
    return selected


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return ImageOps.fit(image, size, Image.Resampling.LANCZOS, centering=(0.5, 0.5))


def background_for(plate: Image.Image, theme: str, index: int) -> Image.Image:
    base = plate.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if index % 2 else plate.copy()
    base = cover(base, CANVAS).convert("RGB")
    base = ImageEnhance.Contrast(base).enhance(1.06)

    if theme == "light":
        base = Image.blend(base, Image.new("RGB", CANVAS, IVORY), 0.78)
        top_tint = (*IVORY, 222)
    elif theme == "red":
        red_field = Image.new("RGB", CANVAS, (142, 12, 14))
        base = Image.blend(base, red_field, 0.43)
        top_tint = (55, 5, 6, 185)
    else:
        base = Image.blend(base, Image.new("RGB", CANVAS, INK), 0.38)
        top_tint = (*INK, 205)

    veil = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    veil_draw = ImageDraw.Draw(veil)
    veil_draw.rectangle((0, 0, CANVAS[0], 650), fill=top_tint)
    veil = veil.filter(ImageFilter.GaussianBlur(38))
    return Image.alpha_composite(base.convert("RGBA"), veil)


def add_screenshot(canvas: Image.Image, screenshot: Image.Image, theme: str) -> None:
    target_w = 990
    target_h = round(target_w * screenshot.height / screenshot.width)
    screenshot = screenshot.resize((target_w, target_h), Image.Resampling.LANCZOS).convert("RGB")
    frame_pad = 10
    frame_size = (target_w + frame_pad * 2, target_h + frame_pad * 2)
    radius = 68
    x = (CANVAS[0] - frame_size[0]) // 2
    y = 684

    shadow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (x + 2, y + 18, x + frame_size[0] + 2, y + frame_size[1] + 18),
        radius=radius,
        fill=(0, 0, 0, 145),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    canvas.alpha_composite(shadow)

    frame_color = RED if theme in {"light", "dark"} else IVORY
    card = Image.new("RGBA", frame_size, frame_color + (255,))
    card.alpha_composite(screenshot.convert("RGBA"), (frame_pad, frame_pad))
    mask = Image.new("L", frame_size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, frame_size[0], frame_size[1]), radius=radius, fill=255)
    card.putalpha(mask)
    canvas.alpha_composite(card, (x, y))


def add_copy(canvas: Image.Image, slide: dict[str, str], index: int) -> None:
    draw = ImageDraw.Draw(canvas)
    light = slide["theme"] == "light"
    headline_color = INK if light else WHITE
    subhead_color = (60, 60, 58) if light else (229, 225, 217)
    meta_color = (70, 68, 64) if light else (220, 215, 205)

    brand_font = font(31, "Bold")
    meta_font = font(26, "Semibold")
    headline_font = font(91, "Bold")
    subhead_font = font(35, "Medium")

    draw.rounded_rectangle((84, 78, 104, 128), radius=10, fill=RED)
    draw.text((126, 78), "REVV", font=brand_font, fill=headline_color)
    sequence = f"{index + 1:02d} / {len(SLIDES):02d}"
    sequence_w = draw.textlength(sequence, font=meta_font)
    draw.text((1236 - sequence_w, 82), sequence, font=meta_font, fill=meta_color)

    draw.multiline_text(
        (84, 174),
        slide["headline"],
        font=headline_font,
        fill=headline_color,
        spacing=-2,
    )
    draw.text((88, 554), slide["subhead"], font=subhead_font, fill=subhead_color)
    draw.rounded_rectangle((84, 628, 226, 640), radius=6, fill=RED)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def create_contact_sheet(outputs: list[Path]) -> None:
    thumb_w = 360
    thumb_h = round(thumb_w * CANVAS[1] / CANVAS[0])
    gap = 34
    margin = 44
    sheet = Image.new("RGB", (margin * 2 + thumb_w * 3 + gap * 2, margin * 2 + thumb_h * 2 + gap), IVORY)
    for i, output in enumerate(outputs):
        shot = Image.open(output).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        x = margin + (i % 3) * (thumb_w + gap)
        y = margin + (i // 3) * (thumb_h + gap)
        sheet.paste(shot, (x, y))
    sheet.save(CONTACT_SHEET_PATH, "PNG", optimize=True)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    plate = Image.open(BACKGROUND_PATH).convert("RGB")
    manifest: dict[str, object] = {
        "canvas": list(CANVAS),
        "language": "English",
        "source_build": "1.38.0+59",
        "background": str(BACKGROUND_PATH.relative_to(ROOT)),
        "outputs": [],
    }
    outputs: list[Path] = []

    for index, slide in enumerate(SLIDES):
        source_path = SOURCE_DIR / slide["source"]
        output_path = OUTPUT_DIR / slide["output"]
        source = Image.open(source_path).convert("RGB")
        if source.size != CANVAS:
            raise ValueError(f"Unexpected source dimensions: {source_path} {source.size}")

        canvas = background_for(plate, slide["theme"], index)
        add_copy(canvas, slide, index)
        add_screenshot(canvas, source, slide["theme"])
        canvas.convert("RGB").save(output_path, "PNG", optimize=True)
        outputs.append(output_path)
        manifest["outputs"].append(
            {
                "file": str(output_path.relative_to(ROOT)),
                "source": str(source_path.relative_to(ROOT)),
                "headline": slide["headline"].replace("\n", " "),
                "subhead": slide["subhead"],
                "sha256": sha256(output_path),
            }
        )

    create_contact_sheet(outputs)
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Rendered {len(outputs)} screenshots to {OUTPUT_DIR}")
    print(f"Contact sheet: {CONTACT_SHEET_PATH}")


if __name__ == "__main__":
    main()

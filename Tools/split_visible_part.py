"""Split source pixels using a reviewed, source-specific polygon and color rule.

This is a visible-pixel experiment, not automatic semantic segmentation.
Requires Pillow and NumPy. No resampling or image generation is performed here.
"""
import argparse
from collections import deque
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def split(source_path, spec_path, output):
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
    if digest != spec["source_sha256"]:
        raise ValueError("Source hash differs from reviewed mask specification")
    source = Image.open(source_path).convert("RGBA")
    if list(source.size) != spec["canvas"]:
        raise ValueError("Source dimensions differ from reviewed mask")
    pixels = np.asarray(source)
    region = Image.new("L", source.size)
    ImageDraw.Draw(region).polygon([tuple(p) for p in spec["polygon"]], fill=255)
    rgb = pixels[:, :, :3].astype(np.int16)
    # The reviewed fringe is cool blue-gray; exclude warm skin at its boundary.
    selected = (np.asarray(region) != 0) & (pixels[:, :, 3] != 0)
    selected &= rgb[:, :, 2] - rgb[:, :, 0] >= spec["minimum_blue_minus_red"]
    # Source-painted fringe tips contain warm skin reflections. Their reviewed
    # contours must override the color rule; color alone cannot identify hair.
    for polygon in spec.get("warm_tip_polygons", []):
        tip = Image.new("L", source.size)
        ImageDraw.Draw(tip).polygon([tuple(p) for p in polygon], fill=255)
        selected |= (np.asarray(tip) != 0) & (pixels[:, :, 3] != 0)
    # Keep the connected fringe; remove isolated cool pixels from adjacent eyes.
    pending = selected.copy()
    largest = []
    height, width = selected.shape
    for y, x in zip(*np.where(selected)):
        if not pending[y, x]:
            continue
        queue = deque([(int(y), int(x))])
        pending[y, x] = False
        component = []
        while queue:
            cy, cx = queue.popleft()
            component.append((cy, cx))
            for ny in range(max(0, cy - 1), min(height, cy + 2)):
                for nx in range(max(0, cx - 1), min(width, cx + 2)):
                    if pending[ny, nx]:
                        pending[ny, nx] = False
                        queue.append((ny, nx))
        if len(component) > len(largest):
            largest = component
    selected[:] = False
    for y, x in largest:
        selected[y, x] = True
    if not selected.any():
        raise ValueError("Mask selects no visible pixels")
    output.mkdir(parents=True, exist_ok=True)
    part = pixels.copy()
    rest = pixels.copy()
    part[~selected] = 0
    rest[selected] = 0
    part_image = Image.fromarray(part)
    rest_image = Image.fromarray(rest)
    combined = Image.alpha_composite(rest_image, part_image)
    actual = np.asarray(combined)
    visible = pixels[:, :, 3] != 0
    alpha_error = np.abs(actual[:, :, 3].astype(int) - pixels[:, :, 3]).max()
    color_error = np.abs(actual[visible, :3].astype(int) - pixels[visible, :3]).max()
    if alpha_error or color_error:
        raise ValueError("Recomposition changed visible source pixels")
    part_image.save(output / "front_hair.png")
    rest_image.save(output / "remainder.png")
    combined.save(output / "recomposed.png")
    Image.fromarray(selected.astype(np.uint8) * 255).save(output / "reviewed_mask.png")

    # Head comparison at original coordinates on a checkerboard.
    box = tuple(spec["preview_box"])
    w, h = box[2] - box[0], box[3] - box[1]
    yy, xx = np.indices((h, w))
    gray = np.where((xx // 12 + yy // 12) % 2, 185, 225).astype(np.uint8)
    checker = Image.fromarray(np.stack([gray, gray, gray, np.full_like(gray, 255)], -1))
    previews = [source, part_image, rest_image, combined]
    sheet = Image.new("RGB", (w * 2 * 4, h * 2 + 36), (245, 245, 245))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 18)
    for i, (title, picture) in enumerate(zip(["Source", "Front hair (visible only)", "Remainder (no inpainting)", "Recomposed"], previews)):
        draw.text((i * w * 2 + 8, 6), title, fill=(20, 20, 20), font=font)
        tile = Image.alpha_composite(checker, picture.crop(box))
        sheet.paste(tile.convert("RGB").resize((w * 2, h * 2)), (i * w * 2, 36))
    sheet.save(output / "comparison.png")
    report = {
        "source": str(source_path.resolve()), "source_sha256": digest,
        "canvas": list(source.size), "method": "reviewed polygon + cool-color boundary rule + traced warm hair tips + source pixel ownership",
        "automatic_semantic_segmentation": False, "hidden_part_completion": False,
        "selected_pixels": int(selected.sum()), "part_bounds": list(part_image.getbbox()),
        "alpha_max_difference": int(alpha_error), "visible_rgb_max_difference": int(color_error),
        "visible_rgba_changed_pixels": int(np.any(actual[visible] != pixels[visible], axis=1).sum()),
        "overlapping_visible_pixels": int(((part[:, :, 3] != 0) & (rest[:, :, 3] != 0)).sum()),
        "source_unchanged": hashlib.sha256(source_path.read_bytes()).hexdigest() == digest,
        "limitations": ["Source-specific hand-reviewed mask", "Boundary still requires visual review", "Remainder includes original background glow", "Hair removal leaves transparent holes; no hidden forehead generated", "Exact recomposition alone does not prove semantic correctness"],
    }
    (output / "verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("mask_spec", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    split(args.source, args.mask_spec, args.output)

"""Read-only verification of the saved native-size PSD and its imported assets.

Outputs are inspection reports and previews; source images and PSD are unchanged.
"""
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parents[1] / "Analysis"))
from inspect_psd import Reader, channel, inspect


def sha(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def difference(a, b):
    diff = ImageChops.difference(a, b)
    data = diff.getdata()
    return {"changed_pixels": sum(any(p) for p in data),
            "max_channel_difference": max(high for low, high in diff.getextrema())}


def main():
    out = ROOT / "final-inspection"
    out.mkdir(exist_ok=True)
    psd = ROOT / "blonde_face_layers_review.psd"
    structure = inspect(psd, ROOT, out)
    (out / "psd-structure.json").write_text(
        json.dumps(structure, ensure_ascii=False, indent=2), encoding="utf-8")
    assert structure["status"] == "ok" and not structure["warnings"], structure["warnings"]
    assert structure["header"]["width"] == 752
    assert structure["header"]["height"] == 1344
    assert structure["header"]["depth"] == 8
    assert structure["header"]["color_mode"] == 3

    original = Image.open(ROOT / "original.png").convert("RGBA")
    base = Image.open(ROOT / "prepared" / "base.png").convert("RGBA")
    expected = {
        "両目（原画画素）": ("eyes", (293, 167, 448, 208)),
        "両眉（原画画素）": ("brows", (299, 142, 439, 166)),
        "口（原画画素）": ("mouth", (358, 233, 386, 243)),
        "ベース（目眉口を肌・髪で補完）": ("base", (0, 0, 752, 1344)),
        "元画像（比較用・原寸）": ("original", (0, 0, 752, 1344)),
    }
    records = {}
    decoded = {}
    with psd.open("rb") as f:
        for layer in structure["layers"]:
            if layer["section_type"] != 0:
                continue
            name = layer["name"]
            key, bbox = expected[name]
            t, l, b, r = layer["rect"]
            assert (l, t, r, b) == bbox, layer
            size = (r - l, b - t)
            planes = {}
            for item in layer["channels"]:
                f.seek(item["offset"])
                meta, raw = channel(Reader(f, item["end"]), *size, 8, True)
                planes[item["id"]] = Image.frombytes("L", size, raw)
            img = Image.merge("RGBA", [planes[c] for c in (0, 1, 2, -1)])
            source = original if key == "original" else Image.open(
                ROOT / "prepared" / (key + ".png")).convert("RGBA")
            same = img.tobytes() == source.tobytes()
            assert same, (name, difference(img, source))
            assert layer["visible"] == (key != "original"), name
            decoded[key] = img
            records[key] = {"name": name, "bounds": bbox, "size": size,
                            "visible": layer["visible"], "rgba_matches_asset": same,
                            "alpha_range": img.getchannel("A").getextrema()}
            if key in ("eyes", "brows", "mouth"):
                same_rgb = img.convert("RGB").tobytes() == original.crop(bbox).convert("RGB").tobytes()
                assert same_rgb, name
                records[key]["rgb_matches_original_crop"] = same_rgb
                records[key]["visible_bounds_local"] = img.getchannel("A").getbbox()
    assert set(records) == {"eyes", "brows", "mouth", "base", "original"}
    assert sum(layer["section_type"] in (1, 2) for layer in structure["layers"]) == 1

    reference = base.copy()
    for key in ("mouth", "brows", "eyes"):
        bbox = records[key]["bounds"]
        reference.alpha_composite(decoded[key], (bbox[0], bbox[1]))
    merged = Image.open(psd).convert("RGBA")
    merged_check = difference(merged, reference)
    assert merged_check["max_channel_difference"] <= 2, merged_check
    face_regions = [(296, 166, 357, 213), (388, 166, 448, 213),
                    (297, 142, 356, 167), (386, 141, 443, 167),
                    (356, 231, 388, 245)]
    outside_base = outside_merged = 0
    base_changes = 0
    for p, (a, bb, mm) in enumerate(zip(original.getdata(), base.getdata(), merged.getdata())):
        x, y = p % 752, p // 752
        inside = any(l <= x < r and t <= y < b for l, t, r, b in face_regions)
        base_changes += a != bb
        if not inside:
            outside_base += a != bb
            outside_merged += a != mm
    assert outside_base == 0 and outside_merged == 0, (outside_base, outside_merged)
    merged.save(out / "merged-preview.png")
    zoom_box = (280, 130, 460, 280)
    left = original.crop(zoom_box).resize((720, 600), Image.Resampling.NEAREST)
    right = merged.crop(zoom_box).resize((720, 600), Image.Resampling.NEAREST)
    compare = Image.new("RGBA", (1440, 600), "white")
    compare.paste(left, (0, 0))
    compare.paste(right, (720, 0))
    compare.save(out / "saved-face-compare.png")
    status = json.loads((ROOT / "saved-face-status.json").read_text(encoding="utf-8-sig"))
    assert status["ok"] and status["data"]["modified"] is False and status["data"]["busy"] is False
    live_path = Path(status["data"]["fileName"])
    assert sha(psd) == sha(live_path), "workspace copy differs from managed PSD"
    report = {"result": "passed", "saved_psd": str(psd), "managed_psd": str(live_path),
              "sha256": sha(psd), "canvas": [752, 1344],
              "source_sha256": sha(ROOT / "original.png"),
              "image_layer_count": len(records), "group_count": 1,
              "layers": records, "merged_vs_prepared_composite": merged_check,
              "base_changed_pixels": base_changes,
              "base_changes_outside_face_regions": outside_base,
              "merged_changes_outside_face_regions": outside_merged,
              "body_and_background_unchanged": True,
              "saved_and_not_busy": True,
              "quality_status": "review version; user acceptance pending",
              "remaining_scope": "hair, clothing and limbs remain together in the base layer"}
    (out / "verification.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    prepared = {"parts": [{"part": key, **records[key]} for key in ("eyes", "brows", "mouth")],
                "base_changed_pixels": base_changes,
                "base_changed_pixels_outside_face_regions": outside_base,
                "body_and_background_unchanged": True}
    (ROOT / "prepared-verification.json").write_text(
        json.dumps(prepared, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()

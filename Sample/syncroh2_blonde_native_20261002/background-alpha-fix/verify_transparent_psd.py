"""Read-only PSD alpha and unchanged-layer verification, with inspection previews."""
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parents[2] / "Analysis"))
from inspect_psd import Reader, channel, inspect


def hash_file(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def read_layers(path):
    info = inspect(path, ROOT, ROOT)
    assert not info["warnings"], info["warnings"]
    images = {}
    with path.open("rb") as f:
        for layer in info["layers"]:
            if layer["section_type"]:
                continue
            t, l, b, r = layer["rect"]
            size = (r - l, b - t)
            planes = {}
            for c in layer["channels"]:
                f.seek(c["offset"])
                _, raw = channel(Reader(f, c["end"]), *size, 8, True)
                planes[c["id"]] = Image.frombytes("L", size, raw)
            images[layer["name"]] = (layer, Image.merge("RGBA", [planes[c] for c in (0, 1, 2, -1)]))
    return info, images


def main():
    before_info, before = read_layers(ROOT / "before-background-fix.psd")
    path = ROOT / "blonde_face_layers_transparent.psd"
    info, after = read_layers(path)
    old_name, new_name = "ベース（目眉口を肌・髪で補完）", "ベース（背景透過・目眉口補完）"
    assert len(before) == len(after) == 5
    assert info["header"]["width"] == 752 and info["header"]["height"] == 1344
    unchanged = []
    for name, (layer, image) in before.items():
        if name == old_name:
            continue
        current_layer, current_image = after[name]
        assert image.tobytes() == current_image.tobytes(), name
        for key in ("rect", "visible", "opacity", "blend", "clipping", "mask"):
            assert layer[key] == current_layer[key], (name, key)
        unchanged.append(name)
    base_layer, base = after[new_name]
    asset = Image.open(ROOT / "base-transparent.png").convert("RGBA")
    assert base.tobytes() == asset.tobytes(), "Saved base differs from prepared alpha PNG"
    assert base_layer["rect"] == before[old_name][0]["rect"]
    previous = before[old_name][1]
    opaque_changes = sum(a[:3] != b[:3] and b[3] == 255
                         for a, b in zip(previous.get_flattened_data(), base.get_flattened_data()))
    assert opaque_changes == 0
    assert after["元画像（比較用・原寸）"][0]["visible"] is False
    merged = Image.open(path).convert("RGBA")
    assert merged.getchannel("A").tobytes() == base.getchannel("A").tobytes()
    reference = base.copy()
    for name in ("口（原画画素）", "両眉（原画画素）", "両目（原画画素）"):
        layer, part = after[name]
        t, l, b, r = layer["rect"]
        reference.alpha_composite(part, (l, t))
    visible_diff = 0
    maximum_diff = 0
    for a, b in zip(reference.get_flattened_data(), merged.get_flattened_data()):
        # PSD merged RGB uses a white matte with a separate transparency plane.
        expected = tuple((c * a[3] + 255 * (255 - a[3]) + 127) // 255 for c in a[:3]) + (a[3],)
        difference = max(abs(x - y) for x, y in zip(expected, b))
        maximum_diff = max(maximum_diff, difference)
        visible_diff += difference != 0
    assert maximum_diff <= 1, maximum_diff
    counts = Counter(merged.getchannel("A").get_flattened_data())
    samples = {"background": (20, 500), "leg_gap": (373, 1000),
               "dress": (370, 570), "sock": (317, 1170), "shoe": (323, 1270)}
    sample_values = {name: merged.getpixel(xy) for name, xy in samples.items()}
    assert sample_values["background"][3] == sample_values["leg_gap"][3] == 0
    assert all(sample_values[name][3] == 255 for name in ("dress", "sock", "shoe"))
    # Render verified straight-RGBA layer bytes, rather than double-matting the preview.
    reference.save(ROOT / "saved-composite.png")
    checker = Image.new("RGBA", merged.size)
    pixels = checker.load()
    for y in range(merged.height):
        for x in range(merged.width):
            shade = 210 if (x // 20 + y // 20) % 2 else 160
            pixels[x, y] = (shade, shade, shade, 255)
    checker.alpha_composite(reference)
    checker.save(ROOT / "saved-checker-preview.png")
    dark = Image.new("RGBA", merged.size, (40, 60, 90, 255))
    dark.alpha_composite(reference)
    dark.save(ROOT / "saved-dark-preview.png")
    status = json.loads((ROOT / "saved-status.json").read_text(encoding="utf-8-sig"))
    assert status["ok"] and not status["data"]["modified"] and not status["data"]["busy"]
    managed = Path(status["data"]["fileName"])
    assert hash_file(path) == hash_file(managed)
    report = {"result": "passed", "saved_psd": str(path), "managed_psd": str(managed),
              "sha256": hash_file(path), "canvas": list(merged.size),
              "unchanged_layers_rgba_and_attributes": unchanged,
              "base_rgba_matches_imported_png": True, "opaque_interior_rgb_changes": opaque_changes,
              "merged_alpha_matches_base": True, "transparent_pixels": counts[0],
              "opaque_pixels": counts[255], "partial_alpha_pixels": sum(v for k, v in counts.items() if 0 < k < 255),
              "merged_rgb_white_matte": True,
              "merged_vs_expected_white_matte_pixel_differences": visible_diff,
              "merged_max_difference": maximum_diff,
              "sample_rgba": sample_values, "source_original_hidden": True,
              "saved_and_not_busy": True, "quality_status": "review version; user acceptance pending"}
    (ROOT / "verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    (ROOT / "psd-structure.json").write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()

"""Independent PSD output checks; requires Pillow, numpy, psd-tools."""
import base64
import json
import sys
import struct
from pathlib import Path

import numpy as np
from PIL import Image
from psd_tools import PSDImage


def verify(folder):
    assertions = 0

    def check(condition, label):
        nonlocal assertions
        assert condition, label
        assertions += 1

    def layers(actual, expected):
        check(len(actual) == len(expected), "layer count")
        # psd-tools lists bottom-to-top; Core lists top-to-bottom.
        for layer, item in zip(reversed(actual), expected):
            check(layer.name == item["name"], "Unicode name")
            check(layer.visible == item["visible"], "visibility")
            check(layer.opacity == item["opacity"], "opacity")
            check(layer.is_group() == (item["kind"] == 1), "group kind")
            if layer.is_group():
                layers(list(layer), item["children"])
            else:
                check(list(layer.bbox) == item["bounds"], "bounds")
                pixels = layer.topil(apply_icc=False).convert("RGBA").tobytes()
                check(pixels == base64.b64decode(item["pixels_base64"]), "layer RGBA")
                check((layer.mask is not None) == item.get("has_mask", False), "mask presence")
                if item.get("has_mask"):
                    mask = layer.mask
                    check(list(mask.bbox) == item["mask_bounds"], "mask bounds")
                    check(mask.background_color == item["mask_default"], "mask exterior default")
                    check(mask.disabled == item["mask_disabled"], "mask disabled")
                    check(layer._record.mask_data.flags.invert_mask == item["mask_invert"], "mask inversion")
                    check(mask.topil().tobytes() == base64.b64decode(item["mask_pixels_base64"]), "mask plane")

    items = json.loads((folder / "expected.json").read_text(encoding="utf-8-sig"))
    for item in items:
        path = folder / item["file"]
        psd = PSDImage.open(path)
        check(psd.size == (item["width"], item["height"]), "canvas")
        layers(list(psd), item["layers"])
        rgba = np.frombuffer(base64.b64decode(item["render_rgba_base64"]), dtype=np.uint8)
        rgba = rgba.reshape(item["height"], item["width"], 4).astype(np.uint32)
        expected = rgba.copy()
        alpha = rgba[:, :, 3:4]
        expected[:, :, :3] = (rgba[:, :, :3] * alpha + 255 * (255 - alpha) + 127) // 255
        with Image.open(path) as image:
            check(np.array_equal(np.asarray(image.convert("RGBA")), expected.astype(np.uint8)),
                  "merged white-matted RGB and transparency")
        if item["file"].startswith("mask_"):
            # Independent analytic single-layer mask composition, from decoded planes.
            layer = psd[0]
            source = np.asarray(layer.topil().convert("RGBA"), dtype=np.float64)
            coverage = np.full((item["height"], item["width"]), layer.mask.background_color, dtype=float)
            left, top, right, bottom = layer.mask.bbox
            plane = np.asarray(layer.mask.topil(), dtype=float)
            for y in range(item["height"]):
                for x in range(item["width"]):
                    if left <= x < right and top <= y < bottom:
                        coverage[y, x] = plane[y - top, x - left]
            if layer._record.mask_data.flags.invert_mask:
                coverage = 255 - coverage
            if layer.mask.disabled:
                coverage.fill(255)
            oracle = np.zeros((item["height"], item["width"], 4), dtype=np.uint8)
            left, top, right, bottom = layer.bbox
            for y in range(item["height"]):
                for x in range(item["width"]):
                    if left <= x < right and top <= y < bottom:
                        pixel = source[y - top, x - left]
                        alpha = pixel[3] * layer.opacity / 255 * coverage[y, x] / 255
                        if alpha > 0:
                            oracle[y, x, :3] = pixel[:3]
                            oracle[y, x, 3] = np.rint(alpha)
            check(np.array_equal(oracle, rgba.astype(np.uint8)), "independent mask alpha/opacity composition")
    raw = PSDImage.open(folder / "edges_raw.psd")
    rle = PSDImage.open(folder / "edges_rle.psd")
    check(raw[0].topil().tobytes() == rle[0].topil().tobytes(), "PackBits edge layer pixels")
    with Image.open(folder / "edges_raw.psd") as a, Image.open(folder / "edges_rle.psd") as b:
        check(a.tobytes() == b.tobytes(), "PackBits edge merged pixels")
    def archive_parts(path):
        data = path.read_bytes()
        def u32(offset):
            return struct.unpack_from(">I", data, offset)[0]
        pos = 26
        pos += 4 + u32(pos)
        resources = data[pos:pos + 4 + u32(pos)]
        pos += len(resources) + 8  # layer-mask length and layer-info length
        count = abs(struct.unpack_from(">h", data, pos)[0])
        pos += 2
        records = []
        for _ in range(count):
            n = struct.unpack_from(">H", data, pos + 16)[0]
            flags = data[pos + 18 + n * 6 + 10]
            pos += 18 + n * 6 + 12
            end = pos + 4 + u32(pos)
            pos += 4
            pos += 4 + u32(pos)  # mask
            pos += 4 + u32(pos)  # blending ranges
            n = data[pos]
            pos += ((n + 1 + 3) // 4) * 4
            tags = []
            while end - pos >= 12:
                key = data[pos + 4:pos + 8]
                block = data[pos:pos + 12 + u32(pos + 8)]
                if key != b"luni":
                    tags.append(block)
                pos += len(block)
            records.append((flags & 0xfd, tags))
            pos = end
        return resources, records
    source_resources, source_records = archive_parts(folder / "edit_source.psd")
    for name in ("edited_raw.psd", "edited_rle.psd"):
        resources, records = archive_parts(folder / name)
        check(resources == source_resources, "original resource bytes")
        check(records == source_records, "original IDs, group tags and other flag bits")
    real = json.loads((folder / "real_masks.json").read_text(encoding="utf-8-sig"))
    actual = PSDImage.open(real["source"])
    records = actual._record.layer_and_mask_information.layer_info.layer_records
    indices = {id(record): i for i, record in enumerate(records)}
    actual_layers = {indices[id(layer._record)]: layer for layer in actual.descendants()}
    for entry in real["masks"]:
        mask = actual_layers[entry["source_index"]].mask
        check(list(mask.bbox) == entry["bounds"], "real sample mask rectangle")
        check(mask.background_color == entry["default"], "real sample mask default")
        check(mask.topil().tobytes() == (folder / entry["file"]).read_bytes(), "real sample mask decoded plane")
    report = {"status": "PASS", "assertions": assertions,
              "readers": ["psd-tools", "Pillow"], "files": [item["file"] for item in items]}
    (folder / "independent_verification.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    verify(Path(sys.argv[1]))

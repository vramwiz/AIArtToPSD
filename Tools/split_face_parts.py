"""Source-specific visible facial parts; source pixels, no redraw or inpainting."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont


def run(source_path, output, job):
    source = Image.open(source_path).convert("RGBA")
    pixels = np.asarray(source)
    if source.size != (1024, 1536):
        raise ValueError("Mask landmarks are only reviewed for this 1024x1536 source")
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != "58ece460e16d10beba67aa0b239c6e7075200c73dd6afdac6135f6c9bb1fff07":
        raise ValueError("Source differs from reviewed sample")
    specs = [
        ("eye_left", "目（画面左）", [(446,170),(453,165),(465,163),(475,163),(484,166),(493,171),(497,177),(496,184),(491,190),(482,194),(471,193),(462,191),(453,186),(446,182),(442,178)]),
        ("eye_right", "目（画面右）", [(524,162),(531,157),(539,155),(546,154),(549,153),(549,157),(553,155),(555,158),(560,157),(563,161),(568,163),(568,170),(565,175),(561,180),(553,185),(544,187),(535,185),(530,181),(526,176),(523,169)]),
        ("brow_left", "眉（画面左・可視部のみ）", [(452,147),(460,144),(470,144),(479,146),(483,149),(481,151),(470,149),(460,149),(452,150)]),
        ("brow_right", "眉（画面右・可視部のみ）", [(517,144),(522,140),(530,138),(539,137),(550,138),(554,141),(550,143),(538,141),(529,142),(522,145),(517,147)]),
        ("mouth", "口", [(498,220),(502,221),(510,222),(519,222),(525,220),(532,217),(536,217),(536,221),(530,225),(520,228),(510,228),(503,226),(498,225)]),
    ]
    output.mkdir(parents=True, exist_ok=True)
    owner = np.zeros(pixels.shape[:2], dtype=np.uint8)
    layers = []
    rgb = pixels[:, :, :3].astype(np.int16)
    for index, (key, name, polygon) in enumerate(specs, 1):
        mask = Image.new("L", source.size)
        ImageDraw.Draw(mask).polygon(polygon, fill=255)
        selected = (np.asarray(mask) != 0) & (pixels[:, :, 3] != 0)
        if key.startswith("brow"):
            # Isolate dark warm/neutral brow ink; exclude blue hair and pale skin.
            selected &= rgb.mean(axis=2) < 180
            if key == "brow_left":
                selected &= rgb[:, :, 0] >= rgb[:, :, 2]
                # Only the two exposed skin gaps; brow hidden by hair is excluded.
                visible_gaps = Image.new("L", source.size)
                d = ImageDraw.Draw(visible_gaps)
                d.polygon([(463,145),(470,144),(468,150),(461,150)], fill=255)
                d.polygon([(477,145),(482,147),(482,151),(475,150)], fill=255)
                selected &= np.asarray(visible_gaps) != 0
            else:
                selected[:, 549:] = False
        if np.any(selected & (owner != 0)):
            raise ValueError("Part masks overlap")
        owner[selected] = index
        part = np.zeros_like(pixels)
        part[selected] = pixels[selected]
        image = Image.fromarray(part)
        image.save(output / (key + ".png"))
        mask_image = Image.fromarray(selected.astype(np.uint8) * 255)
        mask_image.save(output / (key + "_mask.png"))
        layers.append((key, name, image, int(selected.sum()), polygon))
    remaining = pixels.copy()
    remaining[owner != 0] = 0
    remainder = Image.fromarray(remaining)
    remainder.save(output / "remainder.png")
    combined = remainder.copy()
    for _, _, image, _, _ in layers:
        combined = Image.alpha_composite(combined, image)
    actual = np.asarray(combined)
    visible = pixels[:, :, 3] != 0
    assert np.array_equal(actual[visible], pixels[visible])
    assert np.array_equal(actual[:, :, 3], pixels[:, :, 3])
    combined.save(output / "recomposed.png")
    box = (430,130,580,235)
    size = (450,315)
    yy, xx = np.indices((105,150))
    gray = np.where((xx//5+yy//5)%2, 185, 225).astype(np.uint8)
    checker = Image.fromarray(np.stack([gray,gray,gray,np.full_like(gray,255)], -1))
    sheet = Image.new("RGB", (450*4,351*2), (245,245,245))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 17)
    panels = [("Source",source)] + [(key,image) for key,_,image,_,_ in layers] + [("Remainder (no fill)",remainder),("Recomposed",combined)]
    for i,(title,picture) in enumerate(panels):
        x,y = (i%4)*450,(i//4)*351
        draw.text((x+8,y+7),title,fill=(20,20,20),font=font)
        tile = Image.alpha_composite(checker,picture.crop(box)).convert("RGB").resize(size)
        sheet.paste(tile,(x,y+36))
    sheet.save(output / "comparison.png")
    report = {"canvas":list(source.size),"parts":[{"id":k,"name":n,"pixels":c,"polygon":p} for k,n,_,c,p in layers],"visible_rgba_changed_pixels":0,"alpha_changed_pixels":0,"automatic_segmentation":False,"inpainting":False,"source_sha256":hashlib.sha256(source_path.read_bytes()).hexdigest(),"limitations":["Source-specific manually reviewed masks","Part edges include source skin-colored antialiasing","Left eyebrow is partially hidden by bangs","Removal leaves transparent holes; no skin fill"]}
    (output/"verification.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    if job:
        request = json.loads((job/"request.json").read_text(encoding="utf-8-sig"))
        result = {k:request[k] for k in ["schemaVersion","requestId","jobId","documentId","ifRevision"]}
        assets, operations = [], []
        source_id = request["layers"][0]["layerId"]
        bounds = {"left":0,"top":0,"right":1024,"bottom":1536}
        for key,image in [(k,im) for k,_,im,_,_ in layers]+[("remainder",remainder)]:
            dest=job/"images"/(key+".png")
            image.save(dest)
            assets.append({"assetId":key,"path":"images/"+dest.name,"sha256":hashlib.sha256(dest.read_bytes()).hexdigest(),"width":1024,"height":1536,"pixelFormat":"RGBA8","colorSpace":"sRGB"})
        operations += [{"op":"set_attributes","layerId":source_id,"visible":False,"opacity":255},{"op":"rename_layer","layerId":source_id,"name":"元画像（比較用）"}]
        operations.append({"op":"add_group","layerId":"face-parts","name":"顔パーツ（分離試験）","parentId":"","beforeLayerId":source_id,"visible":True,"opacity":255})
        for key,name,_,_,_ in layers:
            operations.append({"op":"add_layer","layerId":key,"name":name,"parentId":"face-parts","beforeLayerId":"","visible":True,"opacity":255,"assetId":key,"bounds":bounds})
        operations.append({"op":"add_layer","layerId":"remainder","name":"残り（顔パーツ以外・補完なし）","parentId":"","beforeLayerId":source_id,"visible":True,"opacity":255,"assetId":"remainder","bounds":bounds})
        result.update(assets=assets,operations=operations)
        temp=job/"result.json.tmp"
        temp.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
        temp.replace(job/"result.json")
    print(json.dumps({"parts":{k:c for k,_,_,c,_ in layers},"visible_rgba_changed_pixels":0,"alpha_changed_pixels":0},ensure_ascii=False))


if __name__ == "__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    p.add_argument("output",type=Path)
    p.add_argument("--job",type=Path)
    a=p.parse_args()
    run(a.source,a.output,a.job)

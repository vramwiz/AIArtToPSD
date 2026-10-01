"""Verify actual app exports. No source-image editing or layer generation."""
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
BEFORE = ROOT / 'Exchange/{837E50DB-FAB5-4BC8-80F6-892098A2A079}'
AFTER = Path(json.loads((HERE / 'after-export.json').read_text(encoding='utf-8-sig'))['data']['directory'])

def read(folder):
    return json.loads((folder / 'request.json').read_text(encoding='utf-8-sig'))

old, new = read(BEFORE), read(AFTER)
old_layers = {x['layerId']: x for x in old['layers']}
new_layers = {x['layerId']: x for x in new['layers']}
old_assets = {x['assetId']: x for x in old['assets']}
new_assets = {x['assetId']: x for x in new['assets']}
base = next(x for x in old['layers'] if x['name'] == 'ベース（目・眉・口消去済み）')
assert old['canvas'] == new['canvas'] == {'width': 1024, 'height': 1536}
assert old['documentId'] == new['documentId']
assert len(new_layers) == len(old_layers) + 3
assert [x['layerId'] for x in new['layers'] if x['layerId'] in old_layers] == list(old_layers)
for ident, layer in old_layers.items():
    expected = dict(layer)
    actual = dict(new_layers[ident])
    if ident == base['layerId']:
        expected['visible'] = False
    if layer['kind'] == 'image':
        src = old_assets[expected.pop('assetId')]
        dst = new_assets[actual.pop('assetId')]
        assert src['sha256'] == dst['sha256'], layer['name']
        assert hashlib.sha256((AFTER / dst['path']).read_bytes()).hexdigest() == dst['sha256']
    assert expected == actual, layer['name']

source = Image.open(BEFORE / old_assets[base['assetId']]['path']).convert('RGBA')
original = np.array(source)
parts = [x for x in new['layers'] if x['layerId'] not in old_layers and x['kind'] == 'image']
combined = Image.new('RGBA', source.size)
occupied = np.zeros((1536, 1024), dtype=np.uint8)
part_records = []
for label, layer in zip(('head', 'body'), parts):
    asset = new_assets[layer['assetId']]
    file = AFTER / asset['path']
    im = Image.open(file).convert('RGBA')
    b = layer['bounds']
    box = (b['left'], b['top'], b['right'], b['bottom'])
    assert im.size == (box[2] - box[0], box[3] - box[1])
    a = np.array(im)
    ref = original[box[1]:box[3], box[0]:box[2]]
    visible = a[:, :, 3] > 0
    assert np.array_equal(a[visible], ref[visible]), label
    if label == 'head':
        assert box[3] == 274
    else:
        assert box[1] == 274
    occupied[box[1]:box[3], box[0]:box[2]] += visible
    combined.alpha_composite(im, dest=(box[0], box[1]))
    shutil.copy2(file, HERE / f'{label}.png')
    part_records.append({'part': label, 'name': layer['name'], 'bounds': b, 'size': list(im.size), 'visible_pixels': int(visible.sum()), 'retained_rgba_exact': True, 'sha256': asset['sha256']})

assert np.array_equal(occupied, (original[:, :, 3] > 0).astype(np.uint8))
joined = np.array(combined)
assert np.array_equal(joined[:, :, 3], original[:, :, 3])
assert np.array_equal(joined[original[:, :, 3] > 0], original[original[:, :, 3] > 0])
preview_before = np.array(Image.open(BEFORE / 'preview.png').convert('RGBA'))
preview_after = np.array(Image.open(AFTER / 'preview.png').convert('RGBA'))
assert np.array_equal(preview_before, preview_after), 'Application composite changed'

# Diagnostic views of the actual app output, composited on checkerboard.
def checker(size):
    im = Image.new('RGBA', size, (225, 225, 225, 255))
    d = ImageDraw.Draw(im)
    for y in range(0, size[1], 16):
        for x in range(0, size[0], 16):
            if (x // 16 + y // 16) % 2:
                d.rectangle((x, y, x+15, y+15), fill=(180, 180, 180, 255))
    return im

qa = Image.new('RGB', (1024, 818), 'white')
draw = ImageDraw.Draw(qa)
for i, label in enumerate(('head', 'body')):
    layer = parts[i]
    im = Image.open(HERE / f'{label}.png').convert('RGBA')
    full = checker((1024, 1536))
    full.alpha_composite(im, dest=(layer['bounds']['left'], layer['bounds']['top']))
    qa.paste(full.resize((512, 768)), (i*512, 40))
    draw.text((i*512+16, 12), f'{label.upper()} | original position | 50% preview', fill='black')
qa.save(HERE / 'parts_review.png')
shutil.copy2(AFTER / 'request.json', HERE / 'after_request.json')
shutil.copy2(AFTER / 'preview.png', HERE / 'preview.png')
shutil.copy2(AFTER / 'snapshot.psd', HERE / 'head_body_review.psd')
record = {
    'status': 'app_imported_verified_awaiting_user_visual_review',
    'canvas': new['canvas'], 'split_y': 274, 'resampling': False,
    'parts': part_records, 'existing_images_unchanged': len(old_assets),
    'existing_attributes_change': 'original base visibility true -> false only',
    'original_base_retained': True, 'visible_pixel_coverage_exact': True,
    'overlapping_visible_pixels': 0, 'missing_visible_pixels': 0,
    'recomposed_base_visible_rgba_exact': True,
    'application_preview_rgba_exact': True,
    'image_count': len(new_assets), 'group_count': len(new_layers)-len(new_assets),
    'psd_sha256': hashlib.sha256((HERE / 'head_body_review.psd').read_bytes()).hexdigest(),
    'limitations': ['Fixed-pose separation at neck; no hidden neck/hair completion or pose generation.', 'Eyes and brows remain hidden as in the input document.', 'Transparent RGB may be discarded by trimming; visible RGBA and alpha coverage are exact.']
}
(HERE / 'verification.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(json.dumps(record, ensure_ascii=False, indent=2))

"""Independent stage 13 PNG and PSD exchange checks. Requires Pillow + psd-tools."""
import hashlib
import json
import sys
from pathlib import Path
from PIL import Image
from psd_tools import PSDImage

folder = Path(sys.argv[1])
checks = 0

def check(value, message):
    global checks
    checks += 1
    if not value:
        raise AssertionError(message)

expected = bytes([255,255,255,255,40,70,90,128,255,255,255,255,255,255,255,255])
files = list(folder.glob('*/all_operations.psd')) + list(folder.glob('*/roundtrip.psd')) + list(folder.glob('*/mask_replaced.psd'))
check(bool(files), 'No exchange PSDs found')
check(any(p.name == 'mask_replaced.psd' for p in files), 'Mask output missing')
for path in files:
    request = json.loads((path.parent / 'request.json').read_text(encoding='utf-8-sig'))
    check(request['schemaVersion'] == 1, 'Request schema')
    check(request['canvas'] == {'width': 2, 'height': 2}, 'Request canvas')
    asset = request['assets'][0]
    data = (path.parent / asset['path']).read_bytes()
    check(hashlib.sha256(data).hexdigest() == asset['sha256'], 'Input hash')
    check(Image.open(path.parent / asset['path']).convert('RGBA').tobytes() == expected, 'PNG color/alpha')
    psd = PSDImage.open(path)
    check(psd.size == (2, 2), 'PSD canvas')
    # psd-tools enumerates bottom-to-top; the exchange protocol is topmost-first.
    layers = list(reversed(list(psd)))
    if path.name == 'all_operations.psd':
        check(len(psd) == 2 and layers[0].is_group(), 'Group/order')
        check(layers[0].name == '表情' and len(layers[0]) == 2, 'Group children')
        check(layers[0][1].name == '*neutral' and not layers[0][1].visible, 'Neutral state')
        check(layers[0][0].name == '*smile' and layers[0][0].visible, 'Smile state')
        check(layers[1].bbox == (-1,1,1,3), 'Replacement bounds')
        check(layers[1].opacity == 123 and not layers[1].visible, 'Replacement attributes')
    elif path.name == 'roundtrip.psd':
        check(len(psd) == 2 and layers[1].name == '*追加', 'Added layer')
    else:
        check(layers[0].mask is not None, 'Replacement mask dropped')
        check(layers[0].bbox == (3,4,5,6), 'Masked replacement bounds')
        check(layers[0].mask.bbox == (3,4,5,6), 'Mask position')
        check(layers[0].mask.topil().tobytes() == bytes([255,128,0,255]), 'Mask pixels')
    for layer in psd.descendants():
        if not layer.is_group():
            check(layer.topil(apply_icc=False).convert('RGBA').tobytes() == expected, 'PSD layer color/alpha')
report = {'status': 'PASS', 'assertions': checks, 'files': len(files)}
(folder / 'stage13_independent_verification.json').write_text(json.dumps(report), encoding='utf-8')
print(json.dumps(report))


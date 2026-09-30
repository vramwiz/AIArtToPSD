"""Independent checks for PSDs saved after cross-process recovery and Undo/Redo."""
from pathlib import Path
import json
import sys
from psd_tools import PSDImage

folder = Path(sys.argv[1])
checks = 0

def check(value, message):
    global checks
    checks += 1
    if not value:
        raise AssertionError(message)

for name in ('recovered_child.psd', 'recovered.psd'):
    psd = PSDImage.open(folder / name)
    layers = list(reversed(list(psd)))
    check(psd.size == (16,16), 'Recovery canvas')
    check(len(layers) == 2 and layers[0].is_group(), 'Recovery group ordering')
    check(layers[0].name == '*AI結果:flipx' and layers[0].visible, 'Recovered result name/state')
    check(len(layers[0]) == 1, 'Recovery group child')
    child = layers[0][0]
    check(child.bbox == (0,0,16,16), 'Recovered child bounds')
    check(child.topil(apply_icc=False).convert('RGBA').getpixel((0,0)) == (90,255,255,128), 'Recovery RGBA')
    check(layers[1].name == '*AI結果:flipx', 'Recovery original layer name')
    check(layers[1].topil(apply_icc=False).convert('RGBA').getpixel((0,0)) == (255,255,255,255), 'Original pixels')
    merged = psd.topil().convert('RGBA').getpixel((0,0))
    check(abs(merged[0]-172) <= 1 and merged[1:] == (255,255,255), 'Independent merge after recovery')
report = {'status':'PASS','assertions':checks,'files':2}
(folder / 'stage14_independent_verification.json').write_text(json.dumps(report), encoding='utf-8')
print(json.dumps(report))

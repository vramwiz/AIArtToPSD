"""Independent metadata/pixel checks after recovery and editing of a real PSD copy."""
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image
from psd_tools import PSDImage

folder = Path(sys.argv[1])
source = PSDImage.open(sys.argv[2])
saved = PSDImage.open(folder / 'real_recovered.psd')
checks = 0

def check(value, message):
    global checks
    checks += 1
    if not value:
        raise AssertionError(message)

check(source.size == saved.size, 'Canvas')
check(source._record.image_resources.tobytes() == saved._record.image_resources.tobytes(), 'Resources')
a = source._record.layer_and_mask_information
b = saved._record.layer_and_mask_information
check(a.tagged_blocks.tobytes() == b.tagged_blocks.tobytes(), 'Outer metadata')
check(len(a.layer_info.layer_records) == len(b.layer_info.layer_records), 'Record count')
for before, after in zip(a.layer_info.layer_records, b.layer_info.layer_records):
    check(before.blending_ranges.tobytes() == after.blending_ranges.tobytes(), 'Blending ranges')
    check(before.mask_data == after.mask_data, 'Mask metadata')
    for key, block in before.tagged_blocks.items():
        if key != b'luni':
            check(key in after.tagged_blocks and block.tobytes() == after.tagged_blocks[key].tobytes(), 'Tag '+str(key))
originals = list(source.descendants())
actual = list(saved.descendants())
check(len(originals) == len(actual), 'Layer count')
edited = list(source)[-1]
for before, after in zip(originals, actual):
    check(before.layer_id == after.layer_id, 'Stable PSD layer ID')
    check(before.bbox == after.bbox, 'Bounds')
    if before is edited:
        check(after.name == '再開PSDテスト' and after.opacity == 128 and after.visible, 'Recovered edit')
    else:
        check(before.name == after.name and before.opacity == after.opacity and before.visible == after.visible, 'Unchanged attributes')
    if not before.is_group():
        check(before.topil(apply_icc=False).convert('RGBA').tobytes() == after.topil(apply_icc=False).convert('RGBA').tobytes(), 'Source pixels')
reference = saved.composite(force=True, apply_icc=False).convert('RGBA')
matted = Image.new('RGBA', reference.size, (255,255,255,255))
matted.alpha_composite(reference)
check(np.max(np.abs(np.asarray(saved.topil().convert('RGB')).astype(int)-np.asarray(matted.convert('RGB')).astype(int))) <= 2, 'Independent composite')
report = {'status':'PASS', 'assertions':checks, 'files':1}
(folder / 'stage14_real_independent_verification.json').write_text(json.dumps(report), encoding='utf-8')
print(json.dumps(report))

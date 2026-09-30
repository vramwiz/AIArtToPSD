"""Independent verification of real aiueo layer-property UI saves."""
from pathlib import Path
import json
import sys
import numpy as np
from PIL import Image
from psd_tools import PSDImage

source = PSDImage.open(sys.argv[1])
folder = Path(sys.argv[2])
assertions = 0

def check(value, message):
    global assertions
    assertions += 1
    if not value:
        raise AssertionError(message)

initial = np.frombuffer((folder / 'aiueo_initial.rgba').read_bytes(), np.uint8).reshape(source.height, source.width, 4)
reference = np.array(source.composite(force=True, apply_icc=False).convert('RGBA'))
check(np.max(np.abs(initial.astype(int)-reference.astype(int))) <= 1, 'Initial group renderer differs from psd-tools')

for name in ['aiueo_ui_edited.psd', 'aiueo_ui_renamed.psd', 'aiueo_ui_hidden.psd']:
    saved = PSDImage.open(folder / name)
    check(saved.image_resources.tobytes() == source.image_resources.tobytes(), 'Image resources changed')
    orig_lm = source._record.layer_and_mask_information
    new_lm = saved._record.layer_and_mask_information
    check(orig_lm.tagged_blocks.tobytes() == new_lm.tagged_blocks.tobytes(), 'Outer metadata changed')
    check(orig_lm.global_layer_mask_info.tobytes() == new_lm.global_layer_mask_info.tobytes(), 'Global mask changed')
    check(orig_lm.layer_info.channel_image_data.tobytes() == new_lm.layer_info.channel_image_data.tobytes(), 'Original channel bytes changed')
    check(len(orig_lm.layer_info.layer_records) == len(new_lm.layer_info.layer_records), 'Record count changed')
    for a,b in zip(orig_lm.layer_info.layer_records,new_lm.layer_info.layer_records):
        check(a.blending_ranges.tobytes() == b.blending_ranges.tobytes(), 'Blending ranges changed')
        check(a.mask_data == b.mask_data, 'Layer mask metadata changed')
        for key,block in a.tagged_blocks.items():
            if key != b'luni':
                check(key in b.tagged_blocks and block.tobytes() == b.tagged_blocks[key].tobytes(), 'Additional info changed: '+str(key))
    by_id = {layer.layer_id:layer for layer in saved.descendants()}
    top = list(source)[-1]
    first_child = list(top)[-1]
    check(by_id[top.layer_id].opacity == 96, 'Normal group opacity not saved')
    check(by_id[first_child.layer_id].opacity == 128, 'Nested group opacity not saved')
    leaf = list(first_child)[-1]
    check(by_id[leaf.layer_id].opacity == 160, 'Image opacity not saved')
    check(by_id[top.layer_id].visible == (name != 'aiueo_ui_hidden.psd'), 'Visibility not saved')
    if name != 'aiueo_ui_edited.psd':
        check(by_id[top.layer_id].name.endswith('背景再編集'), 'Rename not saved')
    composite = saved.composite(force=True, apply_icc=False).convert('RGBA')
    matted = Image.new('RGBA', composite.size, (255,255,255,255))
    matted.alpha_composite(composite)
    actual = np.array(saved.topil().convert('RGB'))
    expected = np.array(matted.convert('RGB'))
    check(np.max(np.abs(actual.astype(int)-expected.astype(int))) <= 2, 'Saved composite differs from independent rendering')
report = {'status':'PASS','assertions':assertions,'source':str(sys.argv[1]),'initial_max_difference':int(np.max(np.abs(initial.astype(int)-reference.astype(int))))}
(folder/'ui_real_independent_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))

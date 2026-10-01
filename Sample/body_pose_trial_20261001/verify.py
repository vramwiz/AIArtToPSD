"""Compare actual app exports, preserve provenance, and build inspection views."""
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))
before = Path(load(HERE / 'export.json')['data']['directory'])
after = Path(load(HERE / 'after-export.json')['data']['directory'])
old, new = load(before / 'request.json'), load(after / 'request.json')
ol = {x['layerId']: x for x in old['layers']}
nl = {x['layerId']: x for x in new['layers']}
oa = {x['assetId']: x for x in old['assets']}
na = {x['assetId']: x for x in new['assets']}
body = next(x for x in old['layers'] if x['name'] == '体（首下部・衣装・手足）')
assert old['canvas'] == new['canvas'] == {'width':1024, 'height':1536}
assert old['documentId'] == new['documentId']
assert len(nl) == len(ol) + 1
assert [x['layerId'] for x in new['layers'] if x['layerId'] in ol] == list(ol)
for ident, original in ol.items():
    expected, actual = dict(original), dict(nl[ident])
    if ident == body['layerId']:
        expected['visible'] = False
    if original['kind'] == 'image':
        s = oa[expected.pop('assetId')]
        t = na[actual.pop('assetId')]
        assert s['sha256'] == t['sha256'], original['name']
        assert hashlib.sha256((after/t['path']).read_bytes()).hexdigest() == t['sha256']
    assert expected == actual, original['name']
variant = next(x for x in new['layers'] if x['layerId'] not in ol)
assert variant['parentId'] == body['parentId'] and variant['visible']
assert variant['kind'] == 'image' and not variant['hasMask']
asset = na[variant['assetId']]
im = Image.open(after/asset['path']).convert('RGBA')
b = variant['bounds']
assert im.size == (b['right']-b['left'], b['bottom']-b['top'])
assert b['top'] == 274
src = Image.open(HERE/'body_source.png').convert('RGBA')
original_body = Image.new('RGBA',(1024,1536))
original_body.alpha_composite(src,(body['bounds']['left'],body['bounds']['top']))
new_body = Image.new('RGBA',(1024,1536))
new_body.alpha_composite(im,(b['left'],b['top']))
a, z = np.array(original_body), np.array(new_body)
def interval(arr, y):
    xs = np.where(arr[y,:,3]>128)[0]
    return [int(xs[0]),int(xs[-1])]
def iou(y):
    x, v = a[y:,:,3]>128, z[y:,:,3]>128
    return float(np.logical_and(x,v).sum()/np.logical_or(x,v).sum())
old_preview = Image.open(before/'preview.png').convert('RGBA')
new_preview = Image.open(after/'preview.png').convert('RGBA')
assert np.array_equal(np.array(old_preview)[:274],np.array(new_preview)[:274]), 'Head or facial composite changed'
assert np.array_equal(np.array(new_preview)[274:],z[274:]), 'Visible body differs from imported variant'
qa = Image.new('RGB',(1024,800),'white')
draw = ImageDraw.Draw(qa)
for i, preview in enumerate((old_preview,new_preview)):
    bg = Image.new('RGBA',(1024,1536),(200,200,200,255))
    qa.paste(Image.alpha_composite(bg,preview).resize((512,768)),(i*512,32))
    draw.text((i*512+14,10),('BEFORE','POSE VARIANT')[i],fill='black')
qa.save(HERE/'app_comparison.png')
bg=Image.new('RGBA',(1024,1536),(180,180,180,255))
Image.alpha_composite(bg,new_preview).crop((390,220,690,345)).resize((1200,500)).save(HERE/'app_neck_review.png')
shutil.copy2(after/asset['path'],HERE/'body_pose_app.png')
shutil.copy2(after/'preview.png',HERE/'preview.png')
shutil.copy2(after/'request.json',HERE/'after_request.json')
shutil.copy2(after/'snapshot.psd',HERE/'body_pose_review.psd')
record={
    'status':'imported_verified_awaiting_user_visual_review',
    'generation_mode':'built-in image_gen edit, one call',
    'canvas':new['canvas'], 'generated_size':[1097,1434],
    'app_resample_size':[945,1236], 'placement_before_trim':[67,274,1012,1510],
    'horizontal_neck_alignment_adjustment_px':2,
    'app_layer_bounds':b,'app_layer_size':list(im.size),
    'neck_top_source_alpha128_interval':interval(a,274),
    'neck_top_variant_alpha128_interval':interval(z,274),
    'lower_body_alpha128_iou_from_canvas_y724':iou(724),
    'existing_images_preserved':len(oa),'head_and_face_preview_rgba_exact':True,
    'original_body_retained_hidden':True,'other_existing_attributes_unchanged':True,
    'image_count':len(na),'group_count':len(nl)-len(na),
    'visual_review':'Same body proportions, outfit, stance and style; requested viewer-left hand on hip. Small redraw differences in clothing folds, legs and boots remain. No substantial departure identified; imported under user condition.',
    'limitations':['Generated body pixels are not identical to original.','Neck color/contour continuity and appearance require user visual acceptance.','No claim of pose-invariant exact geometry.'],
    'psd_sha256':hashlib.sha256((HERE/'body_pose_review.psd').read_bytes()).hexdigest()
}
(HERE/'verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(record,ensure_ascii=True,indent=2))

"""Verify imported parts, unchanged existing layers, and localized pose change."""
from pathlib import Path
import hashlib
import json
import shutil
import numpy as np
from PIL import Image
P=Path(__file__).resolve().parent
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
before=Path(read(P/'export.json')['data']['directory'])
after=Path(read(P/'after-export.json')['data']['directory'])
old,new=read(before/'request.json'),read(after/'request.json')
ol={x['layerId']:x for x in old['layers']}; nl={x['layerId']:x for x in new['layers']}
oa={x['assetId']:x for x in old['assets']}; na={x['assetId']:x for x in new['assets']}
assert old['canvas']==new['canvas']=={'width':1024,'height':1536}
assert old['documentId']==new['documentId']
assert len(nl)==len(ol)+8
assert [x['layerId'] for x in new['layers'] if x['layerId'] in ol]==list(ol)
for ident,layer in ol.items():
    a,b=dict(layer),dict(nl[ident])
    if layer['kind']=='image':
        source=oa[a.pop('assetId')]; target=na[b.pop('assetId')]
        assert source['sha256']==target['sha256'],layer['name']
        assert hashlib.sha256((after/target['path']).read_bytes()).hexdigest()==target['sha256']
    assert a==b,layer['name']

manifest=read(P/'result.json')
added={o['assetId']:nl[o['layerId']] for o in manifest['operations'] if o['op']=='add_layer'}
parts={}
records=[]
for name,layer in added.items():
    asset=na[layer['assetId']]; b=layer['bounds']
    im=Image.open(after/asset['path']).convert('RGBA')
    assert im.size==(b['right']-b['left'],b['bottom']-b['top'])
    full=Image.new('RGBA',(1024,1536)); full.paste(im,(b['left'],b['top']))
    a=np.array(full); reference=np.array(Image.open(P/(name+'.png')).convert('RGBA'))
    assert np.array_equal(a[:,:,3],reference[:,:,3])
    visible=reference[:,:,3]>0
    assert np.array_equal(a[visible],reference[visible]),name
    parts[name]=full
    if name=='right_arm_hip':
        vy,vx=np.where(a[:,:,3]>0)
        assert vx.max()<=480 and vy.max()<590 and len(vy)<50000, 'Arm contains unrelated body regions'
    records.append({'part':name,'bounds':b,'size':list(im.size),'visible':layer['visible'],'rgba_preserved':True})
    shutil.copy2(after/asset['path'],P/(name+'_app.png'))
def compose(names):
    im=Image.new('RGBA',(1024,1536))
    for name in names: im=Image.alpha_composite(im,parts[name])
    return im
base=['right_leg_original','left_leg_original','torso','left_arm_original']
original=compose(base+['right_arm_original'])
trial=compose(base+['right_arm_hip'])
ref=np.array(Image.open(P/'original_recomposed.png').convert('RGBA'))
orig=np.array(original); posed=np.array(trial)
assert np.array_equal(orig[:,:,3],ref[:,:,3])
assert np.array_equal(orig[ref[:,:,3]>0],ref[ref[:,:,3]>0])
scope=(np.array(parts['right_arm_original'])[:,:,3]>0)|(np.array(parts['right_arm_hip'])[:,:,3]>0)
assert np.array_equal(orig[~scope],posed[~scope]),'Change outside right-arm coverage'
changed=np.any(orig!=posed,axis=2)
old_preview=np.array(Image.open(before/'preview.png').convert('RGBA'))
new_preview=np.array(Image.open(after/'preview.png').convert('RGBA'))
assert np.array_equal(old_preview[:274],new_preview[:274]),'Head/face state changed'
# Compare the independent Pillow composite with the application's renderer.
# Raw imported pixels above are exact. Different alpha/rounding paths can
# differ by one RGB level; alpha and geometry must still be identical.
delta=np.abs(posed[274:].astype(np.int16)-new_preview[274:].astype(np.int16))
assert int(delta[:,:,3].max())==0,'Application alpha differs'
assert int(delta[:,:,:3].max())<=1,'Application composite exceeds one RGB level'
for file,target in [('request.json','after_request.json'),('preview.png','preview.png'),('snapshot.psd','limb_pose_review.psd')]:
    shutil.copy2(after/file,P/target)
record={
 'status':'imported_verified_awaiting_user_visual_review',
 'approach':'fixed original torso and independent original limbs; reuse accepted bent arm',
 'new_image_generation_calls':0,
 'initial_import_issue':'Initial hole-filling mask accidentally selected the whole body; import was undone at unchanged revision 21. Corrected bounded hand-hole fill and arm-extent validation before fresh export/import.',
 'existing_images_unchanged':len(oa),'all_existing_attributes_and_visibility_unchanged':True,
 'image_count':len(na),'group_count':len(nl)-len(na),
 'original_limb_recomposition_visible_rgba_exact':True,
 'fixed_region_outside_swapped_arm_rgba_exact':True,
 'changed_pixels_outside_arm_coverage':int((changed&~scope).sum()),
 'changed_pixels_total':int(changed.sum()),
 'head_and_face_preview_unchanged':True,
 'head_visible_at_input':next(x['visible'] for x in old['layers'] if x['name']=='頭部ベース（髪・顔・首上部）'),
 'app_preview_alpha_matches_trial_exactly':True,
 'app_preview_vs_pillow_max_rgb_error':int(delta[:,:,:3].max()),
 'app_preview_vs_pillow_differing_pixels':int(np.any(delta!=0,axis=2).sum()),
 'parts':records,
 'limitations':['No newly generated standalone limb; bent arm is from the accepted approach-1 output.', 'Legs are visible original regions only; hidden thighs and other leg poses are untested.', 'Masks are specific to this illustration and fixed placement.'],
 'psd_sha256':hashlib.sha256((P/'limb_pose_review.psd').read_bytes()).hexdigest()
}
(P/'verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(record,ensure_ascii=True,indent=2))

"""Verify a generated arm behind the existing torso; keep existing pixels exact."""
from pathlib import Path
import json,hashlib,shutil
import numpy as np
from PIL import Image,ImageDraw
P=Path(__file__).resolve().parent
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
before=Path(read(P/'export.json')['data']['directory'])
after=Path(read(P/'after-export.json')['data']['directory'])
old,new=read(before/'request.json'),read(after/'request.json')
ol={l['layerId']:l for l in old['layers']}; nl={l['layerId']:l for l in new['layers']}
oa={a['assetId']:a for a in old['assets']}; na={a['assetId']:a for a in new['assets']}
front=next(l for l in old['layers'] if l['name']=='右腕（画面左・一つずつ表示）')
torso=next(l for l in new['layers'] if l['name']=='固定素体（首・胴体・衣装／手足なし）')
assert old['documentId']==new['documentId']
assert old['canvas']==new['canvas']=={'width':1024,'height':1536}
assert len(nl)==len(ol)+1
assert [l['layerId'] for l in new['layers'] if l['layerId'] in ol]==list(ol)
for ident,l in ol.items():
    a,b=dict(l),dict(nl[ident])
    if ident==front['layerId']: a['visible']=False
    if l['kind']=='image':
        src=oa[a.pop('assetId')]; dst=na[b.pop('assetId')]
        assert src['sha256']==dst['sha256'],l['name']
        assert hashlib.sha256((after/dst['path']).read_bytes()).hexdigest()==dst['sha256']
    assert a==b,l['name']
arm=next(l for l in new['layers'] if l['layerId'] not in ol)
assert arm['kind']=='image' and arm['visible'] and arm['parentId']==torso['parentId']
siblings=[l['layerId'] for l in new['layers'] if l['parentId']==torso['parentId']]
assert siblings.index(arm['layerId'])==siblings.index(torso['layerId'])+1
def full(layer):
    im=Image.new('RGBA',(1024,1536)); b=layer['bounds']
    part=Image.open(after/na[layer['assetId']]['path']).convert('RGBA')
    assert part.size==(b['right']-b['left'],b['bottom']-b['top'])
    im.paste(part,(b['left'],b['top']))
    return im
af,tf=full(arm),full(torso)
ap,tp=np.array(af),np.array(tf)
rgb=ap[:,:,:3].astype(np.int16)
yy,xx=np.indices(ap.shape[:2])
hand=(ap[:,:,3]>16)&(yy>=580)&(xx>=455)&(rgb[:,:,0]-rgb[:,:,1]>18)&(rgb[:,:,0]-rgb[:,:,2]>30)
assert int(hand.sum())>100,'Hand region not found'
assert np.all(tp[:,:,3][hand]>=250),'Hand extends outside the near-opaque torso'
hidden=(ap[:,:,3]>0)&(tp[:,:,3]==255)
visible=(ap[:,:,3]>0)&(tp[:,:,3]<255)
assert int(visible.sum())>1000,'No visible sleeve remains'
old_preview=Image.open(before/'preview.png').convert('RGBA')
new_preview=Image.open(after/'preview.png').convert('RGBA')
op,npix=np.array(old_preview),np.array(new_preview)
assert np.array_equal(op[:274],npix[:274]),'Head/face state changed'
fixed=tp[:,:,3]==255
fixed_delta=np.abs(op[fixed].astype(np.int16)-npix[fixed].astype(np.int16))
if fixed_delta.size:
    assert int(fixed_delta.max())<=1,'Opaque fixed torso appearance changed'
near_opaque=(tp[:,:,3]>=250)&(tp[:,:,3]<255)&(ap[:,:,3]>16)
near_delta=np.abs(op[near_opaque].astype(np.int16)-npix[near_opaque].astype(np.int16))
for file,target in [('request.json','after_request.json'),('preview.png','preview.png'),('snapshot.psd','arm_behind_review.psd')]:
    shutil.copy2(after/file,P/target)
shutil.copy2(after/na[arm['assetId']]['path'],P/'arm_behind_app.png')
qa=Image.new('RGB',(1200,630),'white'); d=ImageDraw.Draw(qa)
for i,(label,im) in enumerate([('BEFORE: ARM DOWN',old_preview),('AFTER: ARM BEHIND TORSO',new_preview)]):
    bg=Image.new('RGBA',im.size,(190,190,190,255))
    qa.paste(Image.alpha_composite(bg,im).crop((230,270,830,870)),(i*600,30))
    d.text((i*600+12,10),label,fill='black')
qa.save(P/'app_comparison.png')
bg=Image.new('RGBA',new_preview.size,(190,190,190,255))
Image.alpha_composite(bg,new_preview).crop((330,285,455,550)).resize((500,1060)).save(P/'shoulder_review.png')
record={
 'status':'imported_verified_awaiting_user_visual_review',
 'new_image_generation_calls':1,'mode':'built-in image_gen edit',
 'pose':'character right arm (viewer left) behind back',
 'layer_order':'fixed torso directly above new rear arm',
 'existing_images_unchanged':len(oa),'existing_attribute_change':'front right-arm group visibility -> false only',
 'image_count':len(na),'group_count':len(nl)-len(na),
 'generated_size':[1254,1254],'source_crop':[216,32,610,762],
 'app_resample_size':[201,373],'placement_before_trim':[350,286,551,659],
 'app_layer_bounds':arm['bounds'],
 'arm_pixels_fully_hidden_by_torso':int(hidden.sum()),
 'arm_pixels_not_fully_hidden_by_torso':int(visible.sum()),
 'sampled_hand_pixels':int(hand.sum()),'sampled_hand_within_near_opaque_torso':True,
 'sampled_hand_torso_alpha_range':[int(tp[:,:,3][hand].min()),int(tp[:,:,3][hand].max())],
 'sampled_hand_fully_occluded':bool(np.all(tp[:,:,3][hand]==255)),
 'near_opaque_overlap_max_rgba_difference':near_delta.max(axis=0).tolist(),
 'head_and_face_preview_exact':True,
 'fully_opaque_torso_pixel_count':int(fixed.sum()),
 'opaque_fixed_torso_preview_max_difference':int(fixed_delta.max()) if fixed_delta.size else None,
 'limitations':['Existing fixed armhole cut remains; shoulder/armpit contour and shading require user visual review.','Existing torso alpha over the hand is 253-254, so it is visually covered but not mathematically fully occluded; rear color contributes slightly. No existing alpha was changed.','Only one rear-arm pose tested. No general conclusion about arbitrary limb separation.','Hand region is inferred by bounded color sampling and visually reviewed, not generic semantic segmentation.'],
 'psd_sha256':hashlib.sha256((P/'arm_behind_review.psd').read_bytes()).hexdigest()
}
(P/'verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(record,ensure_ascii=True,indent=2))

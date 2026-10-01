"""Verify current app import, neck registration, preserved sources and placement."""
from pathlib import Path
import json,hashlib,shutil
import numpy as np
from PIL import Image,ImageDraw
P=Path(__file__).resolve().parent
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
before=Path(read(P/'export.json')['data']['directory']); after=Path(read(P/'after-export.json')['data']['directory'])
old,new=read(before/'request.json'),read(after/'request.json')
ol={l['layerId']:l for l in old['layers']}; nl={l['layerId']:l for l in new['layers']}
oa={a['assetId']:a for a in old['assets']}; na={a['assetId']:a for a in new['assets']}
manifest=read(P/'result.json')
changes={o['layerId']:o for o in manifest['operations'] if o['op']=='set_attributes'}
assert old['documentId']==new['documentId'] and old['canvas']==new['canvas']=={'width':1024,'height':1536}
assert len(nl)==len(ol)+1
assert [l['layerId'] for l in new['layers'] if l['layerId'] in ol]==list(ol)
for ident,l in ol.items():
    a,b=dict(l),dict(nl[ident])
    if ident in changes:
        a.update({k:changes[ident][k] for k in ('visible','opacity')})
    if l['kind']=='image':
        src,dst=oa[a.pop('assetId')],na[b.pop('assetId')]
        assert src['sha256']==dst['sha256'],l['name']
        assert hashlib.sha256((after/dst['path']).read_bytes()).hexdigest()==dst['sha256']
    assert a==b,l['name']
pose=next(l for l in new['layers'] if l['layerId'] not in ol)
head=next(l for l in new['layers'] if l['name']=='頭部ベース（髪・顔・首上部）')
assert pose['visible'] and head['visible'] and pose['parentId']==head['parentId']
assert pose['bounds']['top']==274==head['bounds']['bottom']
im=Image.open(after/na[pose['assetId']]['path']).convert('RGBA')
b=pose['bounds']
assert im.size==(b['right']-b['left'],b['bottom']-b['top'])
full=Image.new('RGBA',(1024,1536)); full.paste(im,(b['left'],b['top']))
arr=np.array(full)
row=np.where(arr[274,:,3]>128)[0]
original=Image.open(P/'body_source.png').convert('RGBA')
refrow=np.where(np.array(original)[0,:,3]>128)[0]+65
assert row.tolist()==refrow.tolist(), 'Neck seam width/position differs from original'
assert [int(row[0]),int(row[-1])]==[489,548]
preview=Image.open(after/'preview.png').convert('RGBA')
assert np.array_equal(np.array(preview)[274:],arr[274:]),'Visible body differs from new pose'
reference=Image.new('RGBA',(1024,1536)); reference.alpha_composite(original,(65,274))
head_image=Image.open(after/na[head['assetId']]['path']).convert('RGBA')
reference.alpha_composite(head_image,(head['bounds']['left'],head['bounds']['top']))
for l in reversed(old['layers']):
    if l['kind']=='image' and l['visible'] and l['bounds']['bottom']<=274:
        image=Image.open(before/oa[l['assetId']]['path']).convert('RGBA')
        reference.alpha_composite(image,(l['bounds']['left'],l['bounds']['top']))
qa=Image.new('RGB',(1024,800),'white'); d=ImageDraw.Draw(qa)
for i,(label,pic) in enumerate([('ORIGINAL BODY REFERENCE',reference),('COORDINATED WHOLE-BODY POSE',preview)]):
    bg=Image.new('RGBA',pic.size,(190,190,190,255))
    qa.paste(Image.alpha_composite(bg,pic).resize((512,768)),(i*512,32))
    d.text((i*512+12,10),label,fill='black')
qa.save(P/'app_comparison.png')
bg=Image.new('RGBA',preview.size,(190,190,190,255))
Image.alpha_composite(bg,preview).crop((380,225,680,355)).resize((1200,520)).save(P/'neck_review.png')
for file,target in [('request.json','after_request.json'),('preview.png','preview.png'),('snapshot.psd','full_body_pose_review.psd')]:
    shutil.copy2(after/file,P/target)
shutil.copy2(after/na[pose['assetId']]['path'],P/'pose_app.png')
record={
 'status':'imported_verified_awaiting_user_visual_review','mode':'built-in image_gen edit','generation_calls':1,
 'pose':'both arms, torso twist, hip weight shift, skirt drape, bent knee and changed feet',
 'generated_size':[1097,1434],'app_resample_size':[905,1183],
 'scale_x':905/1097,'scale_y':1183/1434,'placement_before_trim':[54,274,959,1457],
 'app_layer_bounds':b,'app_layer_size':list(im.size),
 'neck_y':274,'neck_alpha128_interval':[int(row[0]),int(row[-1])],
 'neck_center_x':float((row[0]+row[-1])/2),'neck_alpha128_exact_match':True,
 'existing_images_unchanged':len(oa),'image_count':len(na),'group_count':len(nl)-len(na),
 'attribute_changes':[{ 'name':ol[k]['name'],'visible':v['visible']} for k,v in changes.items()],
 'head_pixels_and_position_unchanged':True,
 'limitations':['Geometric seam registration is verified at alpha>128; generated neck shading is not pixel-identical to the source.','Body is scaled uniformly to the neck width (approximately 4.2% smaller than scaling output to the original body canvas); changed stance also changes overall silhouette height.','User visual acceptance is pending.'],
 'psd_sha256':hashlib.sha256((P/'full_body_pose_review.psd').read_bytes()).hexdigest()
}
(P/'verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(record,ensure_ascii=True,indent=2))

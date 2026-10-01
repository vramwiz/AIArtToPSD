"""Source-specific original-pixel partition; no redrawing or resampling.

The bent arm is reused from the already accepted approach-1 image. This trial
tests fixed torso + independently switchable limbs, not new limb generation.
"""
from pathlib import Path
import hashlib
import json
from collections import deque
import numpy as np
from PIL import Image, ImageDraw

P=Path(__file__).resolve().parent
W,H=1024,1536
def canvas(file,origin):
    out=Image.new('RGBA',(W,H))
    out.paste(Image.open(P/file).convert('RGBA'),origin)
    return np.array(out)
source=canvas('original_body.png',(65,274))
pose=canvas('accepted_pose_body.png',(109,274))
def poly(points):
    im=Image.new('L',(W,H))
    ImageDraw.Draw(im).polygon(points,fill=255)
    return np.array(im)>0

# Armhole seams measured on the original blouse, in canvas pixels.
left_seam=[(398,299),(398,318),(402,340),(410,360),(419,375),
           (414,391),(410,405),(412,424),(418,444),(426,463),
           (434,480),(429,495),(426,504)]
right_seam=[(635,301),(632,320),(630,340),(624,362),(620,380),
            (624,397),(625,414),(619,435),(610,456),(602,478),
            (605,495),(608,505)]
left=poly([(0,274),(398,274)]+left_seam+[(430,512),(448,519),
          (458,540),(448,565),(437,590),(423,620),(412,650),
          (394,685),(377,720),(363,750),(363,825),(0,850)])
right=poly([(635,274),(1023,274),(1023,850),(655,830),
           (644,741),(635,700),(638,675),(632,649),(618,618),
           (609,590),(601,568),(598,545),(605,512)]+list(reversed(right_seam)))
rgb=source[:,:,:3].astype(np.int16)
yy,xx=np.indices((H,W))
# At the sleeve/skirt overlap keep teal cloth in the fixed torso. This color
# rule is restricted to this reviewed source and these already defined regions.
teal=(rgb[:,:,2]-rgb[:,:,0]>5)&(rgb[:,:,1]-rgb[:,:,0]>8)
left &= ~((yy>=508)&teal)
right &= ~((yy>=508)&teal)
# Legs start at the visible skin under the skirt hem; preserve skirt contour.
leg_region=(yy>=1000)&(yy<1536)&(xx>=380)&(xx<=650)
warm=(rgb[:,:,0]-rgb[:,:,2]>8)
legs=leg_region&((yy>=1050)|warm)
left_leg=legs&(xx<525)
right_leg=legs&~left_leg
left &= ~legs
right &= ~legs & ~left
torso=~(left|right|legs)
masks={'torso':torso,'right_arm_original':left,'left_arm_original':right,
       'right_leg_original':left_leg,'left_leg_original':right_leg}

# Keep the bent sleeve through its armhole, and isolate the warm-colored hand
# where it overlays the teal skirt. The opposite arm, blouse and belt are excluded.
bent_region=poly([(0,274),(398,274)]+left_seam[:7]+[
    (414,416),(403,430),(399,446),(399,500),(399,590),(0,590)])
prgb=pose[:,:,:3].astype(np.int16)
hand_region=(xx>=370)&(xx<=480)&(yy>=510)&(yy<=587)
skin=(prgb[:,:,0]-prgb[:,:,1]>14)|(prgb[:,:,0]-prgb[:,:,2]>32)
bent=bent_region|(hand_region&skin)
bent &= (pose[:,:,3]>0)
# Keep the connected arm and hand, excluding isolated warm fragments of blouse
# or source alpha debris caught by the bounded skin-color test.
pending=bent.copy(); largest=[]
for sy,sx in zip(*np.where(bent)):
    if not pending[sy,sx]: continue
    queue=deque([(int(sy),int(sx))]); pending[sy,sx]=False; component=[]
    while queue:
        y,x=queue.popleft(); component.append((y,x))
        for ny in range(max(0,y-1),min(H,y+2)):
            for nx in range(max(0,x-1),min(W,x+2)):
                if pending[ny,nx]:
                    pending[ny,nx]=False; queue.append((ny,nx))
    if len(component)>len(largest): largest=component
bent[:]=False
for y,x in largest: bent[y,x]=True
# Bright fingernail/highlight pixels enclosed by the selected hand are part of
# the hand, not transparent background. Open gaps between fingers stay empty.
local=bent[507:588,370:481].copy()
visited=np.zeros_like(local)
for sy,sx in zip(*np.where(~local)):
    if visited[sy,sx]: continue
    queue=deque([(int(sy),int(sx))]); visited[sy,sx]=True
    component=[]; touches_boundary=False
    while queue:
        cy,cx=queue.popleft(); component.append((cy,cx))
        if cy in (0,local.shape[0]-1) or cx in (0,local.shape[1]-1): touches_boundary=True
        for ny,nx in ((cy-1,cx),(cy+1,cx),(cy,cx-1),(cy,cx+1)):
            if 0<=ny<local.shape[0] and 0<=nx<local.shape[1] and not local[ny,nx] and not visited[ny,nx]:
                visited[ny,nx]=True; queue.append((ny,nx))
    if not touches_boundary and len(component)<=40:
        for cy,cx in component:
            if pose[cy+507,cx+370,3]>0: bent[cy+507,cx+370]=True
by,bx=np.where(bent)
assert bx.max()<=480 and by.max()<590 and by.min()>=274
assert int(bent.sum())<50000, 'Arm mask contains unrelated body regions'

parts={}
for name,mask in masks.items():
    out=source.copy(); out[~mask]=0
    parts[name]=out
out=pose.copy(); out[~bent]=0
parts['right_arm_hip']=out
for name,out in parts.items():
    Image.fromarray(out).save(P/(name+'.png'))

visible=source[:,:,3]>0
partition=sum((parts[n][:,:,3]>0).astype(np.uint8) for n in masks)
assert np.array_equal(partition,visible.astype(np.uint8))
original=Image.new('RGBA',(W,H))
for name in masks:
    original=Image.alpha_composite(original,Image.fromarray(parts[name]))
joined=np.array(original)
assert np.array_equal(joined[:,:,3],source[:,:,3])
assert np.array_equal(joined[visible],source[visible])
trial=Image.new('RGBA',(W,H))
for name in ['torso','right_leg_original','left_leg_original','left_arm_original','right_arm_hip']:
    trial=Image.alpha_composite(trial,Image.fromarray(parts[name]))
trial.save(P/'trial_composite.png')
original.save(P/'original_recomposed.png')
def checker():
    val=np.where((xx//16+yy//16)%2,190,225).astype(np.uint8)
    return Image.fromarray(np.stack([val,val,val,np.full_like(val,255)],axis=2))
qa=Image.new('RGB',(1536,800),'white')
d=ImageDraw.Draw(qa)
for i,(label,im) in enumerate([('ORIGINAL',original),('FIXED TORSO',Image.fromarray(parts['torso'])),('ARM SWAP',trial)]):
    qa.paste(Image.alpha_composite(checker(),im).resize((512,768)),(i*512,32))
    d.text((i*512+12,10),label,fill='black')
qa.save(P/'parts_trial_review.png')
for name in ('torso','right_arm_original','left_arm_original','right_arm_hip'):
    Image.alpha_composite(checker(),Image.fromarray(parts[name])).crop((230,285,770,850)).resize((810,848)).save(P/(name+'_review.png'))
record={
 'method':'source-specific original-pixel partition; accepted generated arm reuse',
 'source_sha256':hashlib.sha256((P/'original_body.png').read_bytes()).hexdigest(),
 'accepted_pose_sha256':hashlib.sha256((P/'accepted_pose_body.png').read_bytes()).hexdigest(),
 'source_canvas':[W,H], 'armhole_left':left_seam,'armhole_right':right_seam,
 'original_recomposition_visible_rgba_exact':True,
 'parts':{n:{'alpha_bbox':Image.fromarray(a).getchannel('A').getbbox(),'visible_pixels':int((a[:,:,3]>0).sum()),'sha256':hashlib.sha256((P/(n+'.png')).read_bytes()).hexdigest()} for n,a in parts.items()},
 'limitations':['Visible original limbs only; hidden upper thighs and sleeves under the skirt are not reconstructed.','Arm pose is reused from approach 1, not independently regenerated.','Source-specific masks and coordinates must not be reused on a different illustration.']
}
(P/'partition_verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Exact original recomposition verified. Inspect torso and shoulder joins before import.')
